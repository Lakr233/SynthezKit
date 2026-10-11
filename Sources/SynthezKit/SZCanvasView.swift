//
//  SZCanvasView.swift
//  SynthezKit
//

#if canImport(UIKit)
    import DisplayLink
    @_exported import SynthezCore
    import UIKit

    /// A view that runs an immediate-mode UI and shows it as pixel art.
    ///
    /// ```swift
    /// let canvas = SZCanvasView(palette: palette, resolution: .fixed(width: 640, height: 400))
    /// canvas.body = { ctx in
    ///     if button(&ctx, "PLAY").clicked { player.play() }
    /// }
    /// ```
    ///
    /// The canvas only works while it has to. A ``DisplayLink`` bound to the
    /// view ticks while there is input, an animation in flight, a change
    /// waiting to be drawn, or CRT afterglow fading; otherwise it pauses and
    /// the view costs nothing. Call ``invalidate()`` when state the body
    /// reads changes from outside.
    ///
    /// Each frame runs the body to build a draw list. A list identical to the
    /// last one skips rasterizing and uploading.
    ///
    /// Text widgets get the system keyboard through a hidden key-input view,
    /// and every interactive widget is exposed to VoiceOver and UI tests as
    /// an accessibility element.
    @MainActor
    open class SZCanvasView: UIView, DisplayLinkDelegate {
        override open class var layerClass: AnyClass {
            CAMetalLayer.self
        }

        public let ui: SZUI

        /// Builds each frame.
        public var body: ((inout SZContext) -> Void)? {
            didSet { invalidate() }
        }

        public var resolution: SZResolution {
            didSet {
                if resolution != oldValue {
                    setNeedsLayout()
                }
            }
        }

        public var scheduler: SZFrameScheduler {
            get { frameScheduler }
            set {
                frameScheduler = newValue
                wake()
            }
        }

        /// The CRT post-process. While enabled, frames keep coming for the
        /// afterglow to fade after each change.
        public var crt = SZCRTSettings() {
            didSet {
                guard crt != oldValue else { return }
                frameScheduler.settleDuration = crt.afterglow
                needsPresent = true
                wake()
            }
        }

        /// The frame rate the canvas asks for while active.
        public var preferredFrameRateRange: DisplayLinkFrameRateRange = .default {
            didSet { displayLink?.preferredFrameRateRange = preferredFrameRateRange }
        }

        /// The virtual screen for the current bounds.
        public private(set) var screen: SZScreen

        /// Frames run and frames presented, for diagnostics.
        public private(set) var framesBuilt = 0
        public private(set) var framesRasterized = 0
        public private(set) var framesPresented = 0

        private var metalLayer: CAMetalLayer {
            layer as! CAMetalLayer
        }

        private let presenter: SZMetalPresenter?
        private let surface = SZSurface(width: 0, height: 0)
        private var displayLink: DisplayLink?
        private var pendingEvents: [SZInputEvent] = []
        private var frameEvents: [SZInputEvent] = []
        private var needsPresent = true
        private var needsUpload = true
        private var lastPresentTime: Double?
        private var frameScheduler: SZFrameScheduler
        private weak var primaryTouch: UITouch?
        private lazy var keyboard = SZKeyboardProxy(canvas: self)
        private var accessibilityCache: (frame: UInt64, elements: [SZAccessibilityElement])?

        public init(palette: SZPalette, background: SZColor = 0, resolution: SZResolution = .pixelScale(3), scheduler: SZFrameScheduler = SZFrameScheduler()) {
            ui = SZUI(palette: palette, background: background)
            self.resolution = resolution
            frameScheduler = scheduler
            presenter = SZMetalPresenter()
            screen = SZScreen(resolution: resolution, deviceWidth: 1, deviceHeight: 1)
            super.init(frame: .zero)
            isOpaque = true
            backgroundColor = .black
            isMultipleTouchEnabled = false
            accessibilityIdentifier = "SZCanvas"
            presenter?.configure(metalLayer)
            installPointerRecognizers()
            addSubview(keyboard)
        }

        @available(*, unavailable)
        public required init?(coder _: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }

        // MARK: - Frames

        /// Draws a new frame at the next refresh.
        public func invalidate() {
            frameScheduler.invalidate()
            wake()
        }

        private func wake() {
            guard window != nil else { return }
            if let displayLink {
                displayLink.isPaused = false
            } else {
                let link = DisplayLink(context: .view(self), preferredFrameRateRange: preferredFrameRateRange)
                link.delegate = self
                displayLink = link
            }
        }

        public func displayLink(_: DisplayLink, didUpdate frame: DisplayLinkFrame) {
            step(at: frame.targetTimestamp)
        }

        /// Runs one refresh. Exposed for tests and for hosts that drive
        /// frames themselves.
        public func step(at time: Double) {
            guard let body, screen.size.width > 0, screen.size.height > 0 else {
                displayLink?.isPaused = true
                return
            }
            let hasInput = !pendingEvents.isEmpty
            guard frameScheduler.isDue(at: time, hasInput: hasInput) || needsPresent else {
                if !frameScheduler.hasPendingWake {
                    displayLink?.isPaused = true
                }
                return
            }

            swap(&pendingEvents, &frameEvents)
            pendingEvents.removeAll(keepingCapacity: true)
            let result = ui.frame(time: time, size: screen.size, events: frameEvents, body)
            frameEvents.removeAll(keepingCapacity: true)
            framesBuilt += 1

            if result.changed {
                surface.render(ui.drawList)
                framesRasterized += 1
                needsPresent = true
                needsUpload = true
            }
            // Afterglow evolves even when the picture does not.
            if crt.isEnabled {
                needsPresent = true
            }
            if needsPresent, let presenter {
                let dt = lastPresentTime.map { min(max(time - $0, 0), 0.1) } ?? 1.0 / 60
                if presenter.present(surface, upload: needsUpload, palette: ui.palette, screen: screen, crt: crt, dt: dt, to: metalLayer) {
                    needsPresent = false
                    needsUpload = false
                    lastPresentTime = time
                    framesPresented += 1
                }
            }
            updateKeyboard(result.textInput)
            if UIAccessibility.isVoiceOverRunning, ui.accessibilityItems.count != accessibilityCache?.elements.count {
                UIAccessibility.post(notification: .layoutChanged, argument: nil)
            }
            let keepTicking = frameScheduler.didDraw(at: time, result: result) || needsPresent || !pendingEvents.isEmpty
            if !keepTicking {
                displayLink?.isPaused = true
            }
        }

        // MARK: - Layout

        override open func didMoveToWindow() {
            super.didMoveToWindow()
            if window == nil {
                displayLink = nil
            } else {
                setNeedsLayout()
                wake()
            }
        }

        override open func layoutSubviews() {
            super.layoutSubviews()
            let scale = window?.screen.scale ?? traitCollection.displayScale
            metalLayer.contentsScale = scale
            let deviceSize = CGSize(width: (bounds.width * scale).rounded(), height: (bounds.height * scale).rounded())
            if metalLayer.drawableSize != deviceSize {
                metalLayer.drawableSize = deviceSize
            }
            let newScreen = SZScreen(resolution: resolution, deviceWidth: deviceSize.width, deviceHeight: deviceSize.height)
            if newScreen != screen {
                screen = newScreen
                surface.resize(width: screen.size.width, height: screen.size.height)
                frameScheduler.invalidate()
            }
            needsPresent = true
            needsUpload = true
            wake()
        }

        /// The view rectangle (points) of a virtual rectangle.
        public func viewRect(for rect: SZRect) -> CGRect {
            let scale = metalLayer.contentsScale
            return CGRect(
                x: (screen.viewportX + Double(rect.x) * screen.scale) / scale,
                y: (screen.viewportY + Double(rect.y) * screen.scale) / scale,
                width: Double(rect.width) * screen.scale / scale,
                height: Double(rect.height) * screen.scale / scale,
            )
        }

        // MARK: - Input

        private func virtualPoint(_ location: CGPoint) -> SZPoint {
            let scale = metalLayer.contentsScale
            return screen.virtualPoint(deviceX: location.x * scale, deviceY: location.y * scale)
        }

        /// Queues an event for the next frame.
        public func send(_ event: SZInputEvent) {
            pendingEvents.append(event)
            wake()
        }

        override open func touchesBegan(_ touches: Set<UITouch>, with _: UIEvent?) {
            guard primaryTouch == nil, let touch = touches.first else { return }
            primaryTouch = touch
            send(.pointerDown(virtualPoint(touch.location(in: self)), kind: .touch))
        }

        override open func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
            guard let touch = primaryTouch, touches.contains(touch) else { return }
            // Coalesced touches keep fast drags smooth and their velocity right.
            for sample in event?.coalescedTouches(for: touch) ?? [touch] {
                send(.pointerMove(virtualPoint(sample.location(in: self)), kind: .touch))
            }
        }

        override open func touchesEnded(_ touches: Set<UITouch>, with _: UIEvent?) {
            guard let touch = primaryTouch, touches.contains(touch) else { return }
            primaryTouch = nil
            send(.pointerUp(virtualPoint(touch.location(in: self)), kind: .touch))
        }

        override open func touchesCancelled(_ touches: Set<UITouch>, with _: UIEvent?) {
            guard let touch = primaryTouch, touches.contains(touch) else { return }
            primaryTouch = nil
            send(.pointerCancel)
        }

        private func installPointerRecognizers() {
            addGestureRecognizer(UIHoverGestureRecognizer(target: self, action: #selector(handleHover(_:))))
            let scroll = UIPanGestureRecognizer(target: self, action: #selector(handleScroll(_:)))
            scroll.allowedScrollTypesMask = .all
            scroll.allowedTouchTypes = []
            addGestureRecognizer(scroll)
        }

        @objc private func handleHover(_ recognizer: UIHoverGestureRecognizer) {
            switch recognizer.state {
            case .began, .changed:
                send(.pointerMove(virtualPoint(recognizer.location(in: self)), kind: .mouse))
            default:
                send(.pointerExit)
            }
        }

        @objc private func handleScroll(_ recognizer: UIPanGestureRecognizer) {
            guard recognizer.state == .began || recognizer.state == .changed else { return }
            let translation = recognizer.translation(in: self)
            recognizer.setTranslation(.zero, in: self)
            let scale = metalLayer.contentsScale / max(screen.scale, 1)
            send(.wheel(virtualPoint(recognizer.location(in: self)), dx: -translation.x * scale, dy: -translation.y * scale))
        }

        // MARK: - Keyboard

        private func updateKeyboard(_ request: SZTextInputRequest?) {
            if let request {
                keyboard.frame = viewRect(for: request.caret)
                if !keyboard.isFirstResponder {
                    keyboard.keyboardType = request.numeric ? .numbersAndPunctuation : .asciiCapable
                    keyboard.becomeFirstResponder()
                }
            } else if keyboard.isFirstResponder {
                keyboard.resignFirstResponder()
            }
        }

        // MARK: - Accessibility

        override open var isAccessibilityElement: Bool {
            get { false }
            set {}
        }

        override open var accessibilityElements: [Any]? {
            get { currentAccessibilityElements() }
            set {}
        }

        private func currentAccessibilityElements() -> [SZAccessibilityElement] {
            if let cache = accessibilityCache, cache.frame == ui.frameNumber {
                return cache.elements
            }
            let modal = ui.modalLayer
            let elements = ui.accessibilityItems.filter { $0.layer >= modal }.map { item in
                let element = SZAccessibilityElement(accessibilityContainer: self)
                element.canvas = self
                element.item = item
                element.accessibilityLabel = item.label
                element.accessibilityValue = item.value
                element.accessibilityIdentifier = item.label
                element.accessibilityFrameInContainerSpace = viewRect(for: item.rect)
                var traits: UIAccessibilityTraits = []
                if item.traits.contains(.button) {
                    traits.insert(.button)
                }
                if item.traits.contains(.selected) {
                    traits.insert(.selected)
                }
                if item.traits.contains(.adjustable) {
                    traits.insert(.adjustable)
                }
                if item.traits.contains(.staticText) {
                    traits.insert(.staticText)
                }
                if item.traits.contains(.notEnabled) {
                    traits.insert(.notEnabled)
                }
                if item.traits.contains(.header) {
                    traits.insert(.header)
                }
                if item.traits.contains(.tab) {
                    traits.insert(.tabBar)
                }
                element.accessibilityTraits = traits
                return element
            }
            accessibilityCache = (ui.frameNumber, elements)
            return elements
        }

        /// Taps the center of `rect`, for VoiceOver activation.
        func tap(_ rect: SZRect) {
            let center = SZPoint(rect.x + rect.width / 2, rect.y + rect.height / 2)
            send(.pointerDown(center, kind: .touch))
            send(.pointerUp(center, kind: .touch))
        }

        /// Nudges an adjustable control with wheel steps.
        func adjust(_ rect: SZRect, by direction: Double) {
            let center = SZPoint(rect.x + rect.width / 2, rect.y + rect.height / 2)
            send(.wheel(center, dx: 6 * direction, dy: -6 * direction))
        }
    }

    /// One widget as VoiceOver sees it.
    final class SZAccessibilityElement: UIAccessibilityElement {
        weak var canvas: SZCanvasView?
        var item: SZAccessibilityItem?

        override func accessibilityActivate() -> Bool {
            guard let canvas, let item else { return false }
            canvas.tap(item.rect)
            return true
        }

        override func accessibilityIncrement() {
            if let canvas, let item {
                canvas.adjust(item.rect, by: 1)
            }
        }

        override func accessibilityDecrement() {
            if let canvas, let item {
                canvas.adjust(item.rect, by: -1)
            }
        }
    }

    /// The first responder that brings up the keyboard for text widgets and
    /// turns typing into ``SZInputEvent``s.
    final class SZKeyboardProxy: UIView, UIKeyInput {
        private weak var canvas: SZCanvasView?

        var keyboardType = UIKeyboardType.asciiCapable
        var autocorrectionType = UITextAutocorrectionType.no
        var autocapitalizationType = UITextAutocapitalizationType.allCharacters
        var spellCheckingType = UITextSpellCheckingType.no
        var smartQuotesType = UITextSmartQuotesType.no
        var smartDashesType = UITextSmartDashesType.no
        var returnKeyType = UIReturnKeyType.done
        var keyboardAppearance = UIKeyboardAppearance.dark

        init(canvas: SZCanvasView) {
            self.canvas = canvas
            super.init(frame: CGRect(x: 0, y: 0, width: 1, height: 1))
            isUserInteractionEnabled = false
            alpha = 0.02
            isAccessibilityElement = false
        }

        @available(*, unavailable)
        required init?(coder _: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }

        override var canBecomeFirstResponder: Bool {
            true
        }

        var hasText: Bool {
            true
        }

        func insertText(_ text: String) {
            if text == "\n" {
                canvas?.send(.key(.enter, modifiers: []))
            } else {
                canvas?.send(.text(text))
            }
        }

        func deleteBackward() {
            canvas?.send(.key(.backspace, modifiers: []))
        }

        override func pressesBegan(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
            var handled = false
            for press in presses {
                guard let key = press.key else { continue }
                var modifiers: SZModifiers = []
                if key.modifierFlags.contains(.shift) {
                    modifiers.insert(.shift)
                }
                if key.modifierFlags.contains(.command) {
                    modifiers.insert(.command)
                }
                if key.modifierFlags.contains(.alternate) {
                    modifiers.insert(.option)
                }
                if key.modifierFlags.contains(.control) {
                    modifiers.insert(.control)
                }
                let code: SZKeyCode? = switch key.keyCode {
                case .keyboardEscape: .escape
                case .keyboardLeftArrow: .left
                case .keyboardRightArrow: .right
                case .keyboardUpArrow: .up
                case .keyboardDownArrow: .down
                case .keyboardHome: .home
                case .keyboardEnd: .end
                case .keyboardDeleteForward: .deleteForward
                default: nil
                }
                if let code {
                    canvas?.send(.key(code, modifiers: modifiers))
                    handled = true
                }
            }
            if !handled {
                super.pressesBegan(presses, with: event)
            }
        }
    }
#endif

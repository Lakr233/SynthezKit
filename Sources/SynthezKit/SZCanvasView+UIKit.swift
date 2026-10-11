//
//  SZCanvasView+UIKit.swift
//  SynthezKit
//

#if canImport(UIKit)
    import DisplayLink
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
    /// The canvas only works while it has to. A display link bound to the
    /// view ticks while there is input, an animation in flight, a change
    /// waiting to be drawn, or CRT afterglow fading; otherwise it pauses and
    /// the view costs nothing. Call ``invalidate()`` when state the body
    /// reads changes from outside.
    ///
    /// Text widgets get the system keyboard through a hidden key-input view,
    /// and every interactive widget is exposed to VoiceOver and UI tests as
    /// an accessibility element.
    @MainActor
    open class SZCanvasView: UIView {
        override open class var layerClass: AnyClass {
            CAMetalLayer.self
        }

        /// The platform-independent part of the canvas.
        public private(set) var engine: SZCanvasEngine!

        private weak var primaryTouch: UITouch?
        private lazy var keyboard = SZKeyboardProxy(engine: engine)
        private var accessibilityCache: (frame: UInt64, elements: [SZAccessibilityElement])?

        public init(palette: SZPalette, background: SZColor = 0, resolution: SZResolution = .pixelScale(3), scheduler: SZFrameScheduler = SZFrameScheduler()) {
            super.init(frame: .zero)
            engine = SZCanvasEngine(view: self, layer: layer as! CAMetalLayer, palette: palette, background: background, resolution: resolution, scheduler: scheduler)
            isOpaque = true
            backgroundColor = .black
            isMultipleTouchEnabled = false
            accessibilityIdentifier = "SZCanvas"
            installPointerRecognizers()
            addSubview(keyboard)
            engine.onTextInput = { [weak self] in self?.updateKeyboard($0) }
        }

        @available(*, unavailable)
        public required init?(coder _: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }

        // MARK: - Forwarding

        public var ui: SZUI {
            engine.ui
        }

        public var body: ((inout SZContext) -> Void)? {
            get { engine.body }
            set { engine.body = newValue }
        }

        public var resolution: SZResolution {
            get { engine.resolution }
            set { engine.resolution = newValue }
        }

        public var scheduler: SZFrameScheduler {
            get { engine.scheduler }
            set { engine.scheduler = newValue }
        }

        public var crt: SZCRTSettings {
            get { engine.crt }
            set { engine.crt = newValue }
        }

        public var preferredFrameRateRange: DisplayLinkFrameRateRange {
            get { engine.preferredFrameRateRange }
            set { engine.preferredFrameRateRange = newValue }
        }

        public var screen: SZScreen {
            engine.screen
        }

        public func invalidate() {
            engine.invalidate()
        }

        public func send(_ event: SZInputEvent) {
            engine.send(event)
        }

        public func step(at time: Double) {
            engine.step(at: time)
        }

        public func viewRect(for rect: SZRect) -> CGRect {
            engine.viewRect(for: rect)
        }

        // MARK: - Layout

        override open func didMoveToWindow() {
            super.didMoveToWindow()
            if window == nil {
                engine.detach()
            } else {
                setNeedsLayout()
                engine.wake()
            }
        }

        override open func layoutSubviews() {
            super.layoutSubviews()
            engine.layout(size: bounds.size, scale: Double(window?.screen.scale ?? traitCollection.displayScale))
        }

        // MARK: - Input

        override open func touchesBegan(_ touches: Set<UITouch>, with _: UIEvent?) {
            guard primaryTouch == nil, let touch = touches.first else { return }
            primaryTouch = touch
            engine.send(.pointerDown(engine.virtualPoint(touch.location(in: self)), kind: .touch))
        }

        override open func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
            guard let touch = primaryTouch, touches.contains(touch) else { return }
            // Coalesced touches keep fast drags smooth and their velocity right.
            for sample in event?.coalescedTouches(for: touch) ?? [touch] {
                engine.send(.pointerMove(engine.virtualPoint(sample.location(in: self)), kind: .touch))
            }
        }

        override open func touchesEnded(_ touches: Set<UITouch>, with _: UIEvent?) {
            guard let touch = primaryTouch, touches.contains(touch) else { return }
            primaryTouch = nil
            engine.send(.pointerUp(engine.virtualPoint(touch.location(in: self)), kind: .touch))
        }

        override open func touchesCancelled(_ touches: Set<UITouch>, with _: UIEvent?) {
            guard let touch = primaryTouch, touches.contains(touch) else { return }
            primaryTouch = nil
            engine.send(.pointerCancel)
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
                engine.send(.pointerMove(engine.virtualPoint(recognizer.location(in: self)), kind: .mouse))
            default:
                engine.send(.pointerExit)
            }
        }

        @objc private func handleScroll(_ recognizer: UIPanGestureRecognizer) {
            guard recognizer.state == .began || recognizer.state == .changed else { return }
            let translation = recognizer.translation(in: self)
            recognizer.setTranslation(.zero, in: self)
            engine.wheel(at: recognizer.location(in: self), dx: -translation.x, dy: -translation.y)
        }

        // MARK: - Keyboard

        private func updateKeyboard(_ request: SZTextInputRequest?) {
            if let request {
                keyboard.frame = engine.viewRect(for: request.caret)
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
            if let cache = accessibilityCache, cache.frame == engine.ui.frameNumber {
                return cache.elements
            }
            let elements = engine.visibleAccessibilityItems.map { item in
                let element = SZAccessibilityElement(accessibilityContainer: self)
                element.engine = engine
                element.item = item
                element.accessibilityLabel = item.label
                element.accessibilityValue = item.value
                element.accessibilityIdentifier = item.label
                element.accessibilityFrameInContainerSpace = engine.viewRect(for: item.rect)
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
            accessibilityCache = (engine.ui.frameNumber, elements)
            return elements
        }
    }

    /// One widget as VoiceOver sees it.
    final class SZAccessibilityElement: UIAccessibilityElement {
        weak var engine: SZCanvasEngine?
        var item: SZAccessibilityItem?

        override func accessibilityActivate() -> Bool {
            guard let engine, let item else { return false }
            engine.tap(item.rect)
            return true
        }

        override func accessibilityIncrement() {
            if let engine, let item {
                engine.adjust(item.rect, by: 1)
            }
        }

        override func accessibilityDecrement() {
            if let engine, let item {
                engine.adjust(item.rect, by: -1)
            }
        }
    }

    /// The first responder that brings up the keyboard for text widgets and
    /// turns typing into ``SZInputEvent``s.
    final class SZKeyboardProxy: UIView, UIKeyInput {
        private weak var engine: SZCanvasEngine?

        var keyboardType = UIKeyboardType.asciiCapable
        var autocorrectionType = UITextAutocorrectionType.no
        var autocapitalizationType = UITextAutocapitalizationType.allCharacters
        var spellCheckingType = UITextSpellCheckingType.no
        var smartQuotesType = UITextSmartQuotesType.no
        var smartDashesType = UITextSmartDashesType.no
        var returnKeyType = UIReturnKeyType.done
        var keyboardAppearance = UIKeyboardAppearance.dark

        init(engine: SZCanvasEngine) {
            self.engine = engine
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
                engine?.send(.key(.enter, modifiers: []))
            } else {
                engine?.send(.text(text))
            }
        }

        func deleteBackward() {
            engine?.send(.key(.backspace, modifiers: []))
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
                    engine?.send(.key(code, modifiers: modifiers))
                    handled = true
                }
            }
            if !handled {
                super.pressesBegan(presses, with: event)
            }
        }
    }
#endif

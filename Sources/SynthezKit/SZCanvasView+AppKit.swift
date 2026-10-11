//
//  SZCanvasView+AppKit.swift
//  SynthezKit
//

#if !canImport(UIKit) && canImport(AppKit)
    import AppKit
    import DisplayLink

    /// A view that runs an immediate-mode UI and shows it as pixel art.
    ///
    /// The AppKit counterpart of the UIKit canvas: the same engine, driven
    /// by the mouse, the trackpad and the keyboard. The view is flipped, so
    /// its coordinates match the canvas's top-left origin.
    @MainActor
    open class SZCanvasView: NSView {
        /// The platform-independent part of the canvas.
        public private(set) var engine: SZCanvasEngine!

        private let metalLayer = CAMetalLayer()
        private var tracking: NSTrackingArea?
        private var isEditingText = false
        private var accessibilityCache: (frame: UInt64, elements: [SZAccessibilityElement])?

        public init(palette: SZPalette, background: SZColor = 0, resolution: SZResolution = .pixelScale(3), scheduler: SZFrameScheduler = SZFrameScheduler()) {
            super.init(frame: .zero)
            wantsLayer = true
            layerContentsRedrawPolicy = .never
            engine = SZCanvasEngine(view: self, layer: metalLayer, palette: palette, background: background, resolution: resolution, scheduler: scheduler)
            metalLayer.backgroundColor = NSColor.black.cgColor
            setAccessibilityIdentifier("SZCanvas")
            setAccessibilityRole(.group)
            engine.onTextInput = { [weak self] in self?.updateKeyboard($0) }
        }

        @available(*, unavailable)
        public required init?(coder _: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }

        override open func makeBackingLayer() -> CALayer {
            metalLayer
        }

        override open var isFlipped: Bool {
            true
        }

        override open var isOpaque: Bool {
            true
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

        override open func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if window == nil {
                engine.detach()
            } else {
                relayout()
            }
        }

        override open func viewDidChangeBackingProperties() {
            super.viewDidChangeBackingProperties()
            relayout()
        }

        override open func setFrameSize(_ newSize: NSSize) {
            super.setFrameSize(newSize)
            relayout()
        }

        override open func layout() {
            super.layout()
            relayout()
        }

        private func relayout() {
            engine.layout(size: bounds.size, scale: Double(window?.backingScaleFactor ?? 2))
        }

        override open func updateTrackingAreas() {
            super.updateTrackingAreas()
            if let tracking {
                removeTrackingArea(tracking)
            }
            let area = NSTrackingArea(rect: .zero, options: [.mouseMoved, .mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect], owner: self)
            addTrackingArea(area)
            tracking = area
        }

        // MARK: - Mouse

        private func point(_ event: NSEvent) -> SZPoint {
            engine.virtualPoint(convert(event.locationInWindow, from: nil))
        }

        override open func acceptsFirstMouse(for _: NSEvent?) -> Bool {
            true
        }

        override open func mouseDown(with event: NSEvent) {
            engine.send(.pointerDown(point(event), kind: .mouse))
        }

        override open func mouseDragged(with event: NSEvent) {
            engine.send(.pointerMove(point(event), kind: .mouse))
        }

        override open func mouseUp(with event: NSEvent) {
            engine.send(.pointerUp(point(event), kind: .mouse))
        }

        override open func mouseMoved(with event: NSEvent) {
            engine.send(.pointerMove(point(event), kind: .mouse))
        }

        override open func mouseExited(with _: NSEvent) {
            engine.send(.pointerExit)
        }

        override open func scrollWheel(with event: NSEvent) {
            // Precise (trackpad) deltas are in points; a wheel's are in lines.
            let factor: Double = event.hasPreciseScrollingDeltas ? 1 : 10
            engine.wheel(at: convert(event.locationInWindow, from: nil), dx: -event.scrollingDeltaX * factor, dy: -event.scrollingDeltaY * factor)
        }

        // MARK: - Keyboard

        override open var acceptsFirstResponder: Bool {
            true
        }

        private func updateKeyboard(_ request: SZTextInputRequest?) {
            let editing = request != nil
            guard editing != isEditingText else { return }
            isEditingText = editing
            if editing, window?.firstResponder !== self {
                window?.makeFirstResponder(self)
            }
        }

        override open func keyDown(with event: NSEvent) {
            var modifiers: SZModifiers = []
            if event.modifierFlags.contains(.shift) {
                modifiers.insert(.shift)
            }
            if event.modifierFlags.contains(.command) {
                modifiers.insert(.command)
            }
            if event.modifierFlags.contains(.option) {
                modifiers.insert(.option)
            }
            if event.modifierFlags.contains(.control) {
                modifiers.insert(.control)
            }
            let code: SZKeyCode? = switch event.keyCode {
            case 51: .backspace
            case 117: .deleteForward
            case 36, 76: .enter
            case 53: .escape
            case 48: .tab
            case 123: .left
            case 124: .right
            case 125: .down
            case 126: .up
            case 115: .home
            case 119: .end
            default: nil
            }
            if let code {
                engine.send(.key(code, modifiers: modifiers))
            } else if modifiers.contains(.command) || modifiers.contains(.control) {
                if let character = event.charactersIgnoringModifiers?.lowercased().first {
                    engine.send(.key(.character(character), modifiers: modifiers))
                } else {
                    super.keyDown(with: event)
                }
            } else if let text = event.characters, !text.isEmpty, text.unicodeScalars.allSatisfy({ $0.value >= 0x20 && $0.value != 0x7F }) {
                engine.send(.text(text))
            } else {
                super.keyDown(with: event)
            }
        }

        // MARK: - Accessibility

        override open func isAccessibilityElement() -> Bool {
            false
        }

        override open func accessibilityChildren() -> [Any]? {
            if let cache = accessibilityCache, cache.frame == engine.ui.frameNumber {
                return cache.elements
            }
            let elements = engine.visibleAccessibilityItems.map { item in
                let element = SZAccessibilityElement()
                element.engine = engine
                element.item = item
                element.setAccessibilityParent(self)
                element.setAccessibilityLabel(item.label)
                element.setAccessibilityIdentifier(item.label)
                element.setAccessibilityValue(item.value)
                element.setAccessibilityFrameInParentSpace(engine.viewRect(for: item.rect))
                element.setAccessibilitySelected(item.traits.contains(.selected))
                element.setAccessibilityEnabled(!item.traits.contains(.notEnabled))
                let role: NSAccessibility.Role = if item.traits.contains(.adjustable) {
                    .slider
                } else if item.traits.contains(.textField) {
                    .textField
                } else if item.traits.contains(.staticText) || item.traits.contains(.header) {
                    .staticText
                } else if item.traits.contains(.tab) {
                    .radioButton
                } else {
                    .button
                }
                element.setAccessibilityRole(role)
                return element
            }
            accessibilityCache = (engine.ui.frameNumber, elements)
            return elements
        }
    }

    /// One widget as VoiceOver sees it.
    final class SZAccessibilityElement: NSAccessibilityElement {
        weak var engine: SZCanvasEngine?
        var item: SZAccessibilityItem?

        /// Accessibility calls arrive on the main thread.
        override func accessibilityPerformPress() -> Bool {
            guard let engine, let item else { return false }
            MainActor.assumeIsolated { engine.tap(item.rect) }
            return true
        }

        override func accessibilityPerformIncrement() -> Bool {
            guard let engine, let item else { return false }
            MainActor.assumeIsolated { engine.adjust(item.rect, by: 1) }
            return true
        }

        override func accessibilityPerformDecrement() -> Bool {
            guard let engine, let item else { return false }
            MainActor.assumeIsolated { engine.adjust(item.rect, by: -1) }
            return true
        }
    }
#endif

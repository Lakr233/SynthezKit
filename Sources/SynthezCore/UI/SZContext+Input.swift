//
//  SZContext+Input.swift
//  SynthezCore
//

public enum SZEdge: Sendable {
    case top
    case bottom
    case left
    case right
}

public extension SZContext {
    // MARK: - Pointer

    var isPointerDown: Bool {
        ui.isPointerDown
    }

    /// The pointer in local coordinates.
    var pointer: SZPoint? {
        ui.pointer.map { $0 - origin }
    }

    /// Where the current press started, in local coordinates.
    var pressOrigin: SZPoint {
        ui.pressOrigin - origin
    }

    /// Virtual pixels per second; after a release, the fling velocity.
    var pointerVelocity: (x: Double, y: Double) {
        ui.pointerVelocity
    }

    /// Whether `id` may take the pointer from the control holding it.
    func canCapturePointer(_ id: SZID) -> Bool {
        ui.canCapture(id)
    }

    /// Takes the pointer: from now on `id` is held and the control that was
    /// pressed will not click. Scroll views call this once a drag passes
    /// their slop.
    func capturePointer(_ id: SZID) {
        ui.capture(id)
    }

    func focus(_ id: SZID?) {
        ui.setFocus(id)
    }

    // MARK: - Keyboard

    /// Takes a key press no one consumed yet.
    func takeKey(_ key: SZKeyCode, modifiers: SZModifiers = []) -> Bool {
        ui.takeKey(key, modifiers: modifiers)
    }

    /// For a focused text widget: claims the keyboard, tells the host where
    /// the caret is (local), and takes this frame's key and text events.
    func textEvents(for it: SZInteraction, caret: SZRect, numeric: Bool = false) -> [SZInputEvent] {
        guard it.focused else { return [] }
        return ui.takeTextEvents(caret: absolute(caret), numeric: numeric)
    }

    // MARK: - Hints and accessibility

    /// Shows `text` in the status line and tooltip while `it` is hovered or
    /// held.
    func hint(_ text: String?, for it: SZInteraction, rect: SZRect) {
        guard let text, it.hovered || it.held else { return }
        ui.setHint(text, owner: it.id, rect: absolute(rect).intersection(clipRect))
    }

    /// Describes `rect` (local) to screen readers and UI tests.
    func accessibility(_ rect: SZRect, label: String, value: String? = nil, traits: SZAccessibilityTraits = .button, id: SZID) {
        let abs = absolute(rect).intersection(clipRect)
        guard !abs.isEmpty else { return }
        ui.addAccessibility(SZAccessibilityItem(id: id, rect: abs, layer: layer, label: label, value: value, traits: traits))
    }

    /// Hides everything below this layer from screen readers this frame.
    func markModal() {
        ui.raiseModalLayer(layer)
    }

    // MARK: - Filters

    /// Moves what is drawn in `rect` (local) toward `target` by `field`
    /// (local coordinates).
    func filter(_ rect: SZRect, field: SZStrengthField, toward target: SZColor, blend: SZFilterBlend = .dither) {
        let abs = absolute(rect)
        guard !abs.isEmpty, abs.intersection(clipRect).isEmpty == false else { return }
        if case let .constant(s) = field, s <= 0 {
            return
        }
        list.append(.filter(abs, field.offsetBy(origin.x, origin.y), ui.palette.filterMaps(toward: target), blend), clip: clipIndex, layer: layer)
    }

    /// A field from 0 at the far side of `rect` to `strength` at `edge`.
    func ramp(_ rect: SZRect, toward edge: SZEdge, strength: Double = 1) -> SZStrengthField {
        switch edge {
        case .top: .linear(from: SZPoint(rect.x, rect.maxY), to: SZPoint(rect.x, rect.y), start: 0, end: strength)
        case .bottom: .linear(from: SZPoint(rect.x, rect.y), to: SZPoint(rect.x, rect.maxY), start: 0, end: strength)
        case .left: .linear(from: SZPoint(rect.maxX, rect.y), to: SZPoint(rect.x, rect.y), start: 0, end: strength)
        case .right: .linear(from: SZPoint(rect.x, rect.y), to: SZPoint(rect.maxX, rect.y), start: 0, end: strength)
        }
    }

    // MARK: - Text

    /// Wrapped text, laid out once and reused while it stays the same.
    func layoutText(_ text: String, font: SZBitmapFont, width: Int, scale: Int = 1, wrap: SZTextWrap = .word) -> SZTextLayout {
        ui.textLayouts.layout(text, font: font, width: width, scale: scale, wrap: wrap)
    }

    /// Draws `layout` with its top-left at `p`.
    func text(_ layout: SZTextLayout, at p: SZPoint, font: SZBitmapFont, color: SZColor, scale: Int = 1, align: SZAlignment = .start, width: Int? = nil) {
        var y = p.y
        let width = width ?? layout.width
        for line in layout.lines {
            let lineWidth = align == .start ? 0 : font.measure(line) * scale
            let x = switch align {
            case .start, .stretch: p.x
            case .center: p.x + (width - lineWidth) / 2
            case .end: p.x + width - lineWidth
            }
            text(line, at: SZPoint(x, y), font: font, color: color, scale: scale)
            y += layout.lineHeight
        }
    }
}

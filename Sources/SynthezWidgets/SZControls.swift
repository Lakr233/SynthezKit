//
//  SZControls.swift
//  SynthezWidgets
//

import SynthezCore

// Widgets are free functions over an `inout SZContext`. Each returns what
// happened this frame; none keeps callbacks. Without a `rect`, a widget
// places itself at its natural size in the region's flow. Every interactive
// widget describes itself for accessibility and shows its `hint` in the
// status line and tooltip while touched.

// MARK: - Label

/// One line of text at its natural size.
@discardableResult
public func label(
    _ ctx: inout SZContext,
    _ text: String,
    color: SZColor? = nil,
    scale: Int = 1,
    in rect: SZRect? = nil,
) -> SZRect {
    let theme = ctx.theme
    let font = theme.font
    let size = SZSize(font.measure(text) * scale, font.glyphHeight * scale)
    let frame = rect ?? ctx.place(size)
    let origin = frame.centered(size).origin
    ctx.text(text, at: SZPoint(rect == nil ? frame.x : origin.x, origin.y), font: font, color: color ?? theme.text, scale: scale)
    return frame
}

/// Wrapped text as wide as the region (or `width`).
@discardableResult
public func paragraph(
    _ ctx: inout SZContext,
    _ text: String,
    color: SZColor? = nil,
    scale: Int = 1,
    width: Int? = nil,
    align: SZAlignment = .start,
) -> SZRect {
    let theme = ctx.theme
    let width = width ?? ctx.bounds.width
    let layout = ctx.layoutText(text, font: theme.font, width: width, scale: scale)
    let frame = ctx.place(SZSize(width, max(layout.height - scale, 0)))
    ctx.text(layout, at: frame.origin, font: theme.font, color: color ?? theme.text, scale: scale, align: align, width: width)
    return frame
}

// MARK: - Buttons

private func pressable(
    _ ctx: inout SZContext,
    id: SZID,
    frame: SZRect,
    disabled: Bool,
    label: String,
    on: Bool,
    hint: String?,
) -> SZInteraction {
    var it = ctx.interaction(frame, sense: disabled ? [] : .button, id: id)
    if disabled {
        it = SZInteraction(id: id)
    }
    var traits: SZAccessibilityTraits = .button
    if on {
        traits.insert(.selected)
    }
    if disabled {
        traits.insert(.notEnabled)
    }
    ctx.accessibility(frame, label: label, traits: traits, id: id)
    ctx.hint(hint, for: it, rect: frame)
    return it
}

/// A bordered text button.
@discardableResult
public func button(
    _ ctx: inout SZContext,
    _ title: String,
    on: Bool = false,
    disabled: Bool = false,
    height: Int = 11,
    padding: Int = 4,
    hint: String? = nil,
    key: SZKey? = nil,
    in rect: SZRect? = nil,
) -> SZInteraction {
    let theme = ctx.theme
    let id = ctx.makeKey(key)
    let textWidth = theme.font.measure(title)
    let frame = rect ?? ctx.place(SZSize(textWidth + padding * 2 + 2, height))
    let it = pressable(&ctx, id: id, frame: frame, disabled: disabled, label: title, on: on, hint: hint)
    let tone = theme.tone(it, on: on, disabled: disabled)
    ctx.fill(frame, color: tone.fill)
    ctx.stroke(frame, color: tone.border)
    let textOrigin = frame.centered(SZSize(textWidth, theme.font.glyphHeight)).origin
    ctx.text(title, at: SZPoint(textOrigin.x, textOrigin.y + (it.held ? 1 : 0)), font: theme.font, color: tone.ink)
    return it
}

/// A square button showing a 1-bit icon.
@discardableResult
public func iconButton(
    _ ctx: inout SZContext,
    _ icon: SZBitmap,
    label: String,
    on: Bool = false,
    disabled: Bool = false,
    size: Int = 11,
    hint: String? = nil,
    key: SZKey? = nil,
    in rect: SZRect? = nil,
) -> SZInteraction {
    let theme = ctx.theme
    let id = ctx.makeKey(key)
    let frame = rect ?? ctx.place(SZSize(size, size))
    let it = pressable(&ctx, id: id, frame: frame, disabled: disabled, label: label, on: on, hint: hint)
    let tone = theme.tone(it, on: on, disabled: disabled)
    ctx.fill(frame, color: tone.fill)
    ctx.stroke(frame, color: tone.border)
    let origin = frame.centered(SZSize(icon.width, icon.height)).origin
    ctx.bitmap(icon, at: SZPoint(origin.x, origin.y + (it.held ? 1 : 0)), color: tone.ink)
    return it
}

/// Text that reacts like a link: no frame, underline while touched.
@discardableResult
public func textButton(
    _ ctx: inout SZContext,
    _ title: String,
    color: SZColor? = nil,
    disabled: Bool = false,
    hint: String? = nil,
    key: SZKey? = nil,
    in rect: SZRect? = nil,
) -> SZInteraction {
    let theme = ctx.theme
    let id = ctx.makeKey(key)
    let size = SZSize(theme.font.measure(title), theme.font.glyphHeight + 2)
    let frame = rect ?? ctx.place(size)
    let it = pressable(&ctx, id: id, frame: frame, disabled: disabled, label: title, on: false, hint: hint)
    let ink = disabled ? theme.textDim : it.held ? theme.accentBright : (color ?? theme.accent)
    let origin = frame.centered(size).origin
    ctx.text(title, at: origin, font: theme.font, color: ink)
    if it.isActive {
        ctx.fill(SZRect(origin.x, origin.y + size.height - 1, size.width, 1), color: ink)
    } else {
        ctx.fill(SZRect(origin.x, origin.y + size.height - 1, size.width, 1), color: ink, pattern: SZPatterns.half)
    }
    return it
}

// MARK: - Checkbox

/// A box and a label. Returns the interaction; toggle on `clicked`.
@discardableResult
public func checkbox(
    _ ctx: inout SZContext,
    _ title: String,
    checked: Bool,
    disabled: Bool = false,
    hint: String? = nil,
    key: SZKey? = nil,
    in rect: SZRect? = nil,
) -> SZInteraction {
    let theme = ctx.theme
    let id = ctx.makeKey(key)
    let box = 9
    let width = box + 4 + theme.font.measure(title)
    let frame = rect ?? ctx.place(SZSize(width, box))
    let it = pressable(&ctx, id: id, frame: frame, disabled: disabled, label: title, on: checked, hint: hint)
    let boxRect = SZRect(frame.x, frame.y + (frame.height - box) / 2, box, box)
    let tone = theme.tone(it, disabled: disabled)
    ctx.fill(boxRect, color: theme.background)
    ctx.stroke(boxRect, color: it.isActive ? theme.text : tone.border)
    // The check grows in and out.
    let fill = ctx.animatedValue(checked ? 1 : 0, id: id.part("check"), easing: 0.35, snap: 0.05)
    let inset = 2 + Int(((1 - fill) * 2.5).rounded())
    if fill > 0, inset < 5 {
        ctx.fill(boxRect.inset(by: inset), color: disabled ? theme.textDim : theme.accent)
    }
    ctx.text(title, at: SZPoint(boxRect.maxX + 4, boxRect.y + 1), font: theme.font, color: disabled ? theme.textDim : it.isActive ? theme.paper : theme.text)
    return it
}

// MARK: - Segmented

/// An option with an optional icon.
public struct SZOption: Hashable, Sendable {
    public var label: String
    public var icon: SZBitmap?
    public var hint: String?

    public init(_ label: String, icon: SZBitmap? = nil, hint: String? = nil) {
        self.label = label
        self.icon = icon
        self.hint = hint
    }
}

extension SZOption: ExpressibleByStringLiteral {
    public init(stringLiteral value: String) {
        self.init(value)
    }
}

/// Equal-width segments with a light that glides to the selection.
/// Returns the newly picked index, or nil.
public func segmented(
    _ ctx: inout SZContext,
    _ options: [SZOption],
    selected: Int,
    height: Int = 13,
    key: SZKey? = nil,
    in rect: SZRect? = nil,
) -> Int? {
    guard !options.isEmpty else { return nil }
    let theme = ctx.theme
    let id = ctx.makeKey(key)
    let frame = rect ?? ctx.place(SZSize(0, height))
    let inner = frame.inset(by: 1)
    let segment = max(inner.width / options.count, 1)
    ctx.fill(frame, color: theme.background)
    ctx.stroke(frame, color: theme.lineStrong)

    let selected = min(max(selected, 0), options.count - 1)
    let lightX = ctx.animatedValue(Double(selected * segment), id: id.part("light"), easing: 0.25, snap: 0.5)
    // The last cell takes the remainder; the light stretches into it.
    let lightLeft = Int(lightX.rounded())
    let lastStart = (options.count - 1) * segment
    let stretch = max(0, lightLeft + segment - lastStart) * (inner.width - options.count * segment) / max(segment, 1)
    let light = SZRect(inner.x + lightLeft, inner.y, segment + stretch, inner.height)
    ctx.fill(light, color: theme.accent)

    var picked: Int?
    for (i, option) in options.enumerated() {
        let cell = SZRect(inner.x + i * segment, inner.y, i == options.count - 1 ? inner.maxX - (inner.x + i * segment) : segment, inner.height)
        let cellID = id.child(7, UInt32(i))
        let it = ctx.interaction(cell, id: cellID)
        ctx.accessibility(cell, label: option.label, traits: i == selected ? [.button, .selected] : .button, id: cellID)
        ctx.hint(option.hint, for: it, rect: cell)
        if it.clicked, i != selected {
            picked = i
        }
        // Cells the light covers read in background ink.
        let covered = abs(Double(i * segment) - lightX) < Double(segment) / 2
        let ink = covered ? theme.background : it.isActive ? theme.paper : theme.textDim
        if let icon = option.icon {
            ctx.bitmap(icon, at: cell.centered(SZSize(icon.width, icon.height)).origin, color: ink)
        } else {
            let textSize = SZSize(theme.font.measure(option.label), theme.font.glyphHeight)
            ctx.text(option.label, at: cell.centered(textSize).origin, font: theme.font, color: ink)
        }
    }
    return picked
}

// MARK: - Chips

/// Chips that wrap onto new lines, each toggled independently. Returns the
/// index tapped this frame.
public func chipGroup(
    _ ctx: inout SZContext,
    _ options: [SZOption],
    selected: Set<Int>,
    height: Int = 11,
    gap: Int = 3,
    padding: Int = 4,
    key: SZKey? = nil,
) -> Int? {
    let theme = ctx.theme
    let id = ctx.makeKey(key)
    let width = ctx.bounds.width
    var x = 0, y = 0
    var tapped: Int?
    var frames: [SZRect] = []
    frames.reserveCapacity(options.count)
    for option in options {
        let w = option.icon.map { $0.width + padding * 2 + 2 } ?? theme.font.measure(option.label) + padding * 2 + 2
        if x > 0, x + w > width {
            x = 0
            y += height + gap
        }
        frames.append(SZRect(x, y, w, height))
        x += w + gap
    }
    let area = ctx.place(SZSize(width, y + height))
    for (i, option) in options.enumerated() {
        let frame = frames[i].offsetBy(area.x, area.y)
        let on = selected.contains(i)
        let chipID = id.child(9, UInt32(i))
        let it = ctx.interaction(frame, id: chipID)
        ctx.accessibility(frame, label: option.label, traits: on ? [.button, .selected] : .button, id: chipID)
        ctx.hint(option.hint, for: it, rect: frame)
        if it.clicked {
            tapped = i
        }
        let tone = theme.tone(it, on: on)
        ctx.fill(frame, color: tone.fill)
        ctx.stroke(frame, color: tone.border)
        if let icon = option.icon {
            ctx.bitmap(icon, at: frame.centered(SZSize(icon.width, icon.height)).origin, color: tone.ink)
        } else {
            let size = SZSize(theme.font.measure(option.label), theme.font.glyphHeight)
            ctx.text(option.label, at: frame.centered(size).origin, font: theme.font, color: tone.ink)
        }
    }
    return tapped
}

// MARK: - Slider

/// A horizontal or vertical slider. Returns the new value while dragging,
/// or nil. Double-tap returns `reset`.
public func slider(
    _ ctx: inout SZContext,
    value: Double,
    range: ClosedRange<Double> = 0 ... 1,
    step: Double? = nil,
    axis: SZAxis = .horizontal,
    bipolar: Bool = false,
    reset: Double? = nil,
    length: Int = 0,
    thickness: Int = 9,
    label: String = "SLIDER",
    hint: String? = nil,
    key: SZKey? = nil,
    in rect: SZRect? = nil,
) -> Double? {
    let theme = ctx.theme
    let id = ctx.makeKey(key)
    let frame = rect ?? ctx.place(axis == .horizontal ? SZSize(length, thickness) : SZSize(thickness, length == 0 ? 48 : length))
    let it = ctx.interaction(frame, sense: [.click, .focus, .wheel, .drag], id: id)
    let span = max(range.upperBound - range.lowerBound, .ulpOfOne)
    let travel = max((axis == .horizontal ? frame.width : frame.height) - 3, 1)
    ctx.accessibility(frame, label: label, value: String(Int(((value - range.lowerBound) / span * 100).rounded())) + "%", traits: .adjustable, id: id)
    ctx.hint(hint, for: it, rect: frame)

    // A press jumps the thumb under the finger, then drags from there.
    let dragStart = ctx.state(id: id.part("start"), value)
    if it.pressed, let p = ctx.pointer {
        let along = axis == .horizontal ? Double(p.x - frame.x - 1) : Double(frame.maxY - 2 - p.y)
        dragStart.value = range.lowerBound + min(max(along / Double(travel), 0), 1) * span
    }

    var newValue: Double?
    if it.held || it.pressed {
        let delta = axis == .horizontal ? Double(it.dx) : -Double(it.dy)
        newValue = dragStart.value + delta / Double(travel) * span
    }
    let wheel = axis == .horizontal ? it.wheelX : -it.wheelY
    if wheel != 0 {
        newValue = (newValue ?? value) + wheel / Double(travel) * span
    }
    if it.doubleClicked, let reset {
        newValue = reset
    }
    if var v = newValue {
        if let step, step > 0 {
            v = ((v - range.lowerBound) / step).rounded() * step + range.lowerBound
        }
        v = min(max(v, range.lowerBound), range.upperBound)
        newValue = v == value ? nil : v
    }

    let shown = newValue ?? value
    let t = (shown - range.lowerBound) / span
    // The thumb glides a little, so steps and jumps read as motion.
    let pos = Int(ctx.animatedValue(t * Double(travel), id: id.part("thumb"), easing: it.held ? 0.6 : 0.3, snap: 0.5).rounded())
    let origin = bipolar ? Int((((0 - range.lowerBound) / span) * Double(travel)).rounded()) : 0
    let thumb = it.held ? theme.accentBright : it.isActive ? theme.paper : theme.accent
    ctx.fill(frame, color: theme.background)
    ctx.stroke(frame, color: it.isActive ? theme.textDim : theme.line)
    let a = min(origin, pos), b = max(origin, pos)
    switch axis {
    case .horizontal:
        ctx.fill(SZRect(frame.x + 1 + a, frame.y + 2, b - a + 1, frame.height - 4), color: theme.accentDim)
        if bipolar {
            ctx.fill(SZRect(frame.x + 1 + origin, frame.y + 1, 1, frame.height - 2), color: theme.textDim)
        }
        ctx.fill(SZRect(frame.x + pos, frame.y, 3, frame.height), color: thumb)
    case .vertical:
        ctx.fill(SZRect(frame.x + 2, frame.maxY - 2 - b, frame.width - 4, b - a + 1), color: theme.accentDim)
        if bipolar {
            ctx.fill(SZRect(frame.x + 1, frame.maxY - 2 - origin, frame.width - 2, 1), color: theme.textDim)
        }
        ctx.fill(SZRect(frame.x, frame.maxY - 3 - pos, frame.width, 3), color: thumb)
    }
    return newValue
}

// MARK: - Card

/// A titled panel. `body` lays out inside its padding; the card is as tall
/// as `height`, or as its content when nil.
public func card(
    _ ctx: inout SZContext,
    _ title: String,
    height: Int? = nil,
    padding: Int = 5,
    key: SZKey? = nil,
    _ body: (inout SZContext) -> Void,
) {
    let theme = ctx.theme
    let titleHeight = theme.font.glyphHeight + 4
    // The panel is drawn before its content, so without a fixed height it
    // uses the height the content measured last frame.
    let id = ctx.makeKey(key)
    let measured = ctx.state(id: id.part("height"), height ?? titleHeight + padding * 2)
    let frameHeight = height ?? measured.value
    let frame = ctx.place(SZSize(0, frameHeight))
    ctx.fill(frame, color: theme.panel)
    ctx.stroke(frame, color: theme.line)
    ctx.fill(SZRect(frame.x + 1, frame.y + 1, frame.width - 2, titleHeight - 1), color: theme.background)
    ctx.fill(SZRect(frame.x, frame.y + titleHeight - 1, frame.width, 1), color: theme.line)
    ctx.fill(SZRect(frame.x + 1, frame.y + 1, 2, titleHeight - 2), color: theme.accentDim)
    ctx.text(title, at: SZPoint(frame.x + padding, frame.y + 2), font: theme.font, color: theme.textDim)
    ctx.accessibility(SZRect(frame.x, frame.y, frame.width, titleHeight), label: title, traits: .header, id: id.part("title"))
    let content = SZRect(frame.x + padding, frame.y + titleHeight + padding, frame.width - padding * 2, max(frameHeight - titleHeight - padding * 2, 0))
    let bodyRect = SZRect(content.x, content.y, content.width, height == nil ? Int(Int16.max) : content.height)
    let used = ctx.region(bodyRect, key: .id(id.part("body")), reserve: false) { inner -> Int in
        body(&inner)
        return inner.reach.y
    }
    if height == nil {
        let natural = titleHeight + padding * 2 + used
        if natural != measured.value {
            measured.value = natural
            ctx.requestFrame()
        }
    }
}

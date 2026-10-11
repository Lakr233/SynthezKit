//
//  SZKnob.swift
//  SynthezWidgets
//

import Foundation
import SynthezCore

// MARK: - Knob

/// A rotary control: drag up or down (90 px for the full range), wheel to
/// nudge, double-tap to reset. Returns the new value, or nil.
public func knob(
    _ ctx: inout SZContext,
    _ title: String,
    value: Double,
    bipolar: Bool = false,
    steps: Int? = nil,
    reset: Double? = nil,
    text: String? = nil,
    radius: Int = 9,
    hint: String? = nil,
    key: SZKey? = nil,
) -> Double? {
    let theme = ctx.theme
    let id = ctx.makeKey(key)
    let labelWidth = max(theme.font.measure(title), radius * 2 + 1)
    let frame = ctx.place(SZSize(labelWidth, radius * 2 + 1 + 3 + theme.font.glyphHeight * 2 + 3))
    let dial = SZRect(frame.x + (frame.width - (radius * 2 + 1)) / 2, frame.y, radius * 2 + 1, radius * 2 + 1)
    let it = ctx.interaction(frame, sense: [.click, .focus, .wheel, .drag], id: id)
    ctx.accessibility(frame, label: title, value: text ?? String(Int((value * 100).rounded())), traits: .adjustable, id: id)
    ctx.hint(hint, for: it, rect: frame)

    let start = ctx.state(id: id.part("start"), value)
    if it.pressed {
        start.value = value
    }
    var newValue: Double?
    if it.held {
        newValue = start.value - Double(it.dy) / 90
    }
    if it.wheelY != 0 {
        newValue = (newValue ?? value) - it.wheelY / 90
    }
    if it.doubleClicked {
        newValue = reset ?? (bipolar ? 0.5 : 0)
    }
    if var v = newValue {
        if let steps, steps > 1 {
            v = (v * Double(steps - 1)).rounded() / Double(steps - 1)
        }
        v = min(max(v, 0), 1)
        newValue = v == value ? nil : v
    }
    let shown = ctx.animatedValue(newValue ?? value, id: id.part("angle"), easing: it.held ? 0.7 : 0.3, snap: 0.002)

    // 270° sweep from bottom-left to bottom-right.
    let center = SZPoint(dial.x + radius, dial.y + radius)
    let ink = it.held ? theme.accentBright : it.isActive ? theme.paper : theme.accent
    ctx.circle(center: center, radius: radius, color: theme.background)
    ctx.circle(center: center, radius: radius, color: it.isActive ? theme.textDim : theme.lineStrong, filled: false)
    let from = bipolar ? 0.5 : 0
    let ticks = 28
    for i in 0 ... ticks {
        let t = Double(i) / Double(ticks)
        let lit = (t >= min(from, shown) - 0.001 && t <= max(from, shown) + 0.001)
        let angle = (0.75 + t * 1.5) * Double.pi
        let r = Double(radius) - 2
        let p = SZPoint(center.x + Int((cos(angle) * r).rounded()), center.y + Int((sin(angle) * r).rounded()))
        ctx.pixel(p, color: lit ? theme.accentDim : theme.line)
    }
    let angle = (0.75 + shown * 1.5) * Double.pi
    let tip = SZPoint(center.x + Int((cos(angle) * Double(radius - 2)).rounded()), center.y + Int((sin(angle) * Double(radius - 2)).rounded()))
    ctx.line(from: center, to: tip, color: ink)
    ctx.circle(center: center, radius: 1, color: ink)

    let titleWidth = theme.font.measure(title)
    ctx.text(title, at: SZPoint(frame.x + (frame.width - titleWidth) / 2, dial.maxY + 3), font: theme.font, color: theme.textDim)
    let valueText = text ?? String(Int(((newValue ?? value) * 100).rounded()))
    let valueWidth = theme.font.measure(valueText)
    ctx.text(valueText, at: SZPoint(frame.x + (frame.width - valueWidth) / 2, dial.maxY + 3 + theme.font.lineHeight + 1), font: theme.font, color: it.isActive ? theme.paper : theme.text)
    return newValue
}

// MARK: - Stepper

/// `‹ value ›`: returns -1 or +1 when an arrow is tapped, 0 otherwise.
public func stepper(
    _ ctx: inout SZContext,
    _ text: String,
    swatch: SZColor? = nil,
    width: Int = 70,
    previousDisabled: Bool = false,
    nextDisabled: Bool = false,
    hint: String? = nil,
    key: SZKey? = nil,
) -> Int {
    let theme = ctx.theme
    let id = ctx.makeKey(key)
    let height = 13
    let frame = ctx.place(SZSize(width, height))
    ctx.fill(frame, color: theme.background)
    ctx.stroke(frame, color: theme.lineStrong)
    var step = 0
    for (index, direction) in [-1, 1].enumerated() {
        let rect = direction < 0 ? SZRect(frame.x, frame.y, height, height) : SZRect(frame.maxX - height, frame.y, height, height)
        let disabled = direction < 0 ? previousDisabled : nextDisabled
        let partID = id.child(10, UInt32(index))
        var it = ctx.interaction(rect, sense: disabled ? [] : .button, id: partID)
        if disabled {
            it = SZInteraction(id: partID)
        }
        ctx.accessibility(rect, label: direction < 0 ? "PREVIOUS" : "NEXT", traits: disabled ? [.button, .notEnabled] : .button, id: partID)
        ctx.hint(hint, for: it, rect: frame)
        if it.clicked {
            step = direction
        }
        let tone = theme.tone(it, disabled: disabled)
        ctx.fill(rect.inset(by: 1), color: tone.fill)
        let icon = direction < 0 ? SZIcons.chevronLeft : SZIcons.chevronRight
        ctx.bitmap(icon, at: rect.centered(SZSize(icon.width, icon.height)).origin, color: tone.ink)
    }
    ctx.fill(SZRect(frame.x + height, frame.y + 2, 1, height - 4), color: theme.line)
    ctx.fill(SZRect(frame.maxX - height - 1, frame.y + 2, 1, height - 4), color: theme.line)
    // The value slides in from the side it came from.
    let shift = ctx.state(id: id.part("shift"), 0.0)
    if step != 0 {
        shift.value = Double(step) * 8
    }
    shift.value = SZEase.approach(shift.value, to: 0, dt: ctx.dt, easing: 0.3, snap: 0.5)
    if shift.value != 0 {
        ctx.requestFrame()
    }
    let middle = SZRect(frame.x + height + 1, frame.y, frame.width - height * 2 - 2, height)
    var textX = middle.x + (middle.width - theme.font.measure(text)) / 2 + Int(shift.value.rounded())
    if let swatch {
        textX += 4
        ctx.fill(SZRect(textX - 8, frame.y + 4, 5, 5), color: swatch)
    }
    ctx.clip(middle) { inner in
        inner.text(text, at: SZPoint(textX, frame.y + 3), font: theme.font, color: theme.paper)
    }
    ctx.accessibility(middle, label: text, traits: .staticText, id: id.part("value"))
    return step
}

// MARK: - Scrub value

public enum SZScrubLook: Sendable {
    case underline
    case outline
}

/// A number scrubbed by dragging sideways, `dragPixels` per step.
public func scrubValue(
    _ ctx: inout SZContext,
    value: Double,
    in range: ClosedRange<Double>,
    step: Double = 1,
    text: String? = nil,
    look: SZScrubLook = .underline,
    dragPixels: Int = 2,
    width: Int = 40,
    label: String = "VALUE",
    hint: String? = nil,
    key: SZKey? = nil,
) -> Double? {
    let theme = ctx.theme
    let id = ctx.makeKey(key)
    let frame = ctx.place(SZSize(width, 11))
    let it = ctx.interaction(frame, sense: [.click, .focus, .wheel, .drag], id: id)
    let display = text ?? (step >= 1 ? String(Int(value)) : String(format: "%.2f", value))
    ctx.accessibility(frame, label: label, value: display, traits: .adjustable, id: id)
    ctx.hint(hint, for: it, rect: frame)
    let start = ctx.state(id: id.part("start"), value)
    if it.pressed {
        start.value = value
    }
    var newValue: Double?
    if it.held {
        newValue = start.value + Double(it.dx / max(dragPixels, 1)) * step
    }
    if it.wheelY != 0 {
        newValue = (newValue ?? value) - (it.wheelY / 30).rounded() * step
    }
    if var v = newValue {
        v = min(max((v / step).rounded() * step, range.lowerBound), range.upperBound)
        newValue = v == value ? nil : v
    }
    let shownText = newValue.map { text == nil ? (step >= 1 ? String(Int($0)) : String(format: "%.2f", $0)) : display } ?? display
    let ink = it.held ? theme.accentBright : it.isActive ? theme.paper : theme.accent
    switch look {
    case .underline:
        ctx.fill(SZRect(frame.x, frame.maxY - 1, frame.width, 1), color: ink, pattern: it.isActive ? SZPatterns.solid : SZPatterns.half)
    case .outline:
        ctx.fill(frame, color: theme.background)
        ctx.stroke(frame, color: it.isActive ? theme.text : theme.lineStrong)
    }
    if it.held {
        // Arrows show the drag axis.
        ctx.bitmap(SZIcons.chevronLeft, at: SZPoint(frame.x + 1, frame.y + 2), color: theme.textDim)
        ctx.bitmap(SZIcons.chevronRight, at: SZPoint(frame.maxX - 5, frame.y + 2), color: theme.textDim)
    }
    let textWidth = theme.font.measure(shownText)
    ctx.text(shownText, at: SZPoint(frame.x + (frame.width - textWidth) / 2, frame.y + 2), font: theme.font, color: ink)
    return newValue
}

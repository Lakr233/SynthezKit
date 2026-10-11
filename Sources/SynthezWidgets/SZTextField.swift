//
//  SZTextField.swift
//  SynthezWidgets
//

import Foundation
import SynthezCore

public struct SZTextFieldResult: Sendable {
    /// What the field shows: the edit in progress while focused.
    public var text: String
    public var isEditing: Bool
    /// The edit changed this frame.
    public var changed: Bool
    /// Return was pressed or focus moved away: adopt ``text``.
    public var committed: Bool
    /// Escape was pressed: the edit was thrown away.
    public var cancelled: Bool
}

private final class EditState {
    var text: [Character] = []
    var original = ""
    var caret = 0
    var scroll = 0
    var wasFocused = false
    var blinkStart = 0.0
}

/// A single-line text field. Tap to focus and place the caret; the host's
/// keyboard types into it. Long text scrolls to keep the caret in view.
///
/// The field edits a copy while focused and reports it in the result: adopt
/// ``SZTextFieldResult/text`` on `committed` (or on every `changed`).
public func textField(
    _ ctx: inout SZContext,
    value: String,
    placeholder: String = "",
    maxLength: Int? = nil,
    allowed: ((Character) -> Bool)? = nil,
    numeric: Bool = false,
    scale: Int = 1,
    width: Int = 0,
    label: String = "TEXT FIELD",
    hint: String? = nil,
    key: SZKey? = nil,
    in rect: SZRect? = nil,
) -> SZTextFieldResult {
    let theme = ctx.theme
    let font = theme.font
    let id = ctx.makeKey(key)
    let height = font.glyphHeight * scale + 6
    let frame = rect ?? ctx.place(SZSize(width, height))
    let inner = frame.inset(top: 3, right: 3, bottom: 3, left: 3)
    let it = ctx.interaction(frame, sense: [.click, .focus], id: id)
    let state = ctx.state(id: id.part("edit"), EditState()).value
    ctx.hint(hint, for: it, rect: frame)

    var result = SZTextFieldResult(text: value, isEditing: it.focused, changed: false, committed: false, cancelled: false)

    func caretIndex(at x: Int) -> Int {
        var position = 0
        for (i, ch) in state.text.enumerated() {
            let w = font.measure(String(ch)) * scale
            if x < position + w / 2 {
                return i
            }
            position += w + font.spacing * scale
        }
        return state.text.count
    }

    func prefixWidth(_ count: Int) -> Int {
        count == 0 ? 0 : font.measure(String(state.text.prefix(count))) * scale + font.spacing * scale
    }

    if it.focused {
        if !state.wasFocused {
            state.text = Array(value)
            state.original = value
            state.caret = state.text.count
            state.blinkStart = ctx.time
            state.wasFocused = true
        }
        if it.pressed, let p = ctx.pointer {
            state.caret = caretIndex(at: p.x - inner.x + state.scroll)
            state.blinkStart = ctx.time
        }
        let caretRect = SZRect(inner.x + prefixWidth(state.caret) - state.scroll, inner.y, 1, inner.height)
        let before = state.text
        var finish: Bool?
        for event in ctx.textEvents(for: it, caret: caretRect, numeric: numeric) {
            switch event {
            case let .text(string):
                for ch in string {
                    if ch == "\n" || ch == "\r" {
                        finish = true; break
                    }
                    if let allowed, !allowed(ch) {
                        continue
                    }
                    if let maxLength, state.text.count >= maxLength {
                        break
                    }
                    state.text.insert(ch, at: state.caret)
                    state.caret += 1
                }
            case let .key(code, modifiers):
                switch code {
                case .backspace:
                    if state.caret > 0 {
                        state.text.remove(at: state.caret - 1)
                        state.caret -= 1
                    }
                case .deleteForward:
                    if state.caret < state.text.count {
                        state.text.remove(at: state.caret)
                    }
                case .left: state.caret = modifiers.contains(.command) ? 0 : max(state.caret - 1, 0)
                case .right: state.caret = modifiers.contains(.command) ? state.text.count : min(state.caret + 1, state.text.count)
                case .home, .up: state.caret = 0
                case .end, .down: state.caret = state.text.count
                case .enter: finish = true
                case .escape: finish = false
                default: break
                }
            default:
                break
            }
            state.blinkStart = ctx.time
        }
        if state.text != before {
            result.changed = true
        }
        if let commit = finish {
            if commit {
                result.committed = true
            } else {
                state.text = Array(state.original)
                result.cancelled = true
                result.changed = true
            }
            state.wasFocused = false
            ctx.focus(nil)
            result.isEditing = false
        }
        result.text = String(state.text)
    } else if state.wasFocused {
        // Focus moved elsewhere: keep what was typed.
        state.wasFocused = false
        result.committed = true
        result.text = String(state.text)
    }

    // Keep the caret in view.
    let textWidth = font.measure(result.text) * scale
    if result.isEditing {
        let caretX = prefixWidth(state.caret)
        if caretX - state.scroll > inner.width - 2 {
            state.scroll = caretX - inner.width + 2
        }
        if caretX - state.scroll < 0 {
            state.scroll = caretX
        }
        state.scroll = max(min(state.scroll, max(textWidth - inner.width + 2, 0)), 0)
    } else {
        state.scroll = 0
    }

    let focusGlow = ctx.animatedValue(result.isEditing ? 1 : 0, id: id.part("glow"), easing: 0.3, snap: 0.05)
    ctx.fill(frame, color: theme.background)
    ctx.stroke(frame, color: focusGlow > 0.5 ? theme.accent : it.isActive ? theme.text : theme.lineStrong)
    if focusGlow > 0 {
        ctx.fill(SZRect(frame.x, frame.maxY, frame.width, 1), color: theme.accentDim, pattern: SZPatterns.shade(focusGlow))
    }
    ctx.accessibility(frame, label: label, value: result.text.isEmpty ? placeholder : result.text, traits: .textField, id: id)
    ctx.clip(inner.inset(top: -1, right: 0, bottom: -1, left: 0)) { c in
        if result.text.isEmpty {
            c.text(placeholder, at: SZPoint(inner.x, inner.y), font: font, color: theme.textDim, scale: scale)
        } else {
            c.text(result.text, at: SZPoint(inner.x - state.scroll, inner.y), font: font, color: result.isEditing ? theme.paper : theme.text, scale: scale)
        }
        if result.isEditing {
            // Blink: solid right after typing, then 0.5 s on / 0.5 s off.
            let phase = (c.time - state.blinkStart).truncatingRemainder(dividingBy: 1.0)
            if phase < 0.5 {
                c.fill(SZRect(inner.x + prefixWidth(state.caret) - state.scroll - (state.caret > 0 ? 1 : 0), inner.y - 1, max(scale, 1), inner.height + 2), color: theme.accentBright)
            }
            c.requestFrame(at: c.time + (phase < 0.5 ? 0.5 - phase : 1.0 - phase))
        }
    }
    if result.isEditing, textWidth > inner.width {
        // Edge marks show there is more text.
        if state.scroll > 0 {
            ctx.fill(SZRect(frame.x + 1, inner.y, 1, inner.height), color: theme.accent)
        }
        if textWidth - state.scroll > inner.width {
            ctx.fill(SZRect(frame.maxX - 2, inner.y, 1, inner.height), color: theme.accent)
        }
    }
    return result
}

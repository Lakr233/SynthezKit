//
//  SZPanels.swift
//  SynthezWidgets
//

import Foundation
import SynthezCore

// MARK: - Tabs

/// A tab bar whose highlight slides and stretches to the selected tab.
/// Returns the tab tapped this frame.
public func tabs(
    _ ctx: inout SZContext,
    _ titles: [String],
    selected: Int,
    height: Int = 13,
    gap: Int = 2,
    key: SZKey? = nil,
    in rect: SZRect? = nil,
) -> Int? {
    let theme = ctx.theme
    let id = ctx.makeKey(key)
    let frame = rect ?? ctx.place(SZSize(0, height))
    // Spread the spare width evenly over the tabs.
    let natural = titles.map { theme.font.measure($0) + 8 }
    let spare = max(frame.width - natural.reduce(0, +) - gap * max(titles.count - 1, 0), 0)
    var x = frame.x
    var cells: [SZRect] = []
    for (i, width) in natural.enumerated() {
        let extra = spare / max(titles.count, 1) + (i < spare % max(titles.count, 1) ? 1 : 0)
        cells.append(SZRect(x, frame.y, width + extra, height))
        x += width + extra + gap
    }
    ctx.fill(SZRect(frame.x, frame.maxY - 1, frame.width, 1), color: theme.lineStrong)
    guard !cells.isEmpty else { return nil }
    let target = cells[min(max(selected, 0), cells.count - 1)]
    let lx = ctx.animatedValue(Double(target.x), id: id.part("x"), easing: 0.3, snap: 0.5)
    let lw = ctx.animatedValue(Double(target.width), id: id.part("w"), easing: 0.3, snap: 0.5)
    let light = SZRect(Int(lx.rounded()), frame.y, Int(lw.rounded()), height)
    ctx.fill(light, color: theme.accent)

    var tapped: Int?
    for (i, cell) in cells.enumerated() {
        let tabID = id.child(11, UInt32(i))
        let it = ctx.interaction(cell, id: tabID)
        ctx.accessibility(cell, label: titles[i], traits: i == selected ? [.tab, .button, .selected] : [.tab, .button], id: tabID)
        if it.clicked, i != selected {
            tapped = i
        }
        let covered = light.intersection(cell).width * 2 > cell.width
        if !covered, it.isActive {
            ctx.fill(SZRect(cell.x, cell.y, cell.width, cell.height - 1), color: theme.panel)
        }
        let ink = covered ? theme.background : it.isActive ? theme.paper : theme.textDim
        let size = SZSize(theme.font.measure(titles[i]), theme.font.glyphHeight)
        ctx.text(titles[i], at: cell.centered(size).origin, font: theme.font, color: ink)
    }
    return tapped
}

// MARK: - Sheet

public struct SZSheetResult: Sendable {
    /// Tapped outside or on the close button.
    public var dismissed: Bool
    /// 0 closed ... 1 fully open.
    public var shown: Double
}

/// A modal panel that rises from the bottom. The screen behind it
/// pixelates and darkens as it opens.
@discardableResult
public func sheet(
    _ ctx: inout SZContext,
    isPresented: Bool,
    title: String,
    height: Int = 160,
    key: SZKey? = nil,
    _ body: (inout SZContext) -> Void,
) -> SZSheetResult {
    let theme = ctx.theme
    let id = ctx.makeKey(key)
    let shown = ctx.animatedValue(isPresented ? 1 : 0, id: id.part("shown"), easing: 0.16, snap: 0.004)
    guard shown > 0 else { return SZSheetResult(dismissed: false, shown: 0) }
    var dismissed = false
    ctx.overlay(key: .id(id.part("overlay"))) { o in
        let screen = SZRect(0, 0, o.ui.screen.width, o.ui.screen.height).offsetBy(-o.origin.x, -o.origin.y)
        let mosaic = Int((shown * 4).rounded())
        if mosaic >= 2 {
            o.mosaic(screen, size: mosaic)
        }
        o.remap(screen, map: o.palette.mixMap(toward: theme.background, amount: shown * 0.8))
        if shown > 0.5 {
            o.markModal()
        }

        let backdrop = o.interaction(screen, sense: [.click, .wheel], id: id.part("backdrop"))
        if backdrop.clicked, isPresented {
            dismissed = true
        }

        // `shown` already eases out.
        let eased = shown
        let width = min(screen.width - 16, 420)
        let panel = SZRect(screen.x + (screen.width - width) / 2, screen.maxY - Int(Double(height + 8) * eased), width, height)
        _ = o.interaction(panel, sense: [.click, .wheel], id: id.part("panel"))
        o.fill(panel, color: theme.panel)
        o.stroke(panel, color: theme.textDim)
        o.fill(SZRect(panel.x + 1, panel.y + 1, panel.width - 2, 15), color: theme.background)
        o.fill(SZRect(panel.x, panel.y + 16, panel.width, 1), color: theme.line)
        o.text(title, at: SZPoint(panel.x + 6, panel.y + 5), font: theme.font, color: theme.paper)
        o.accessibility(SZRect(panel.x, panel.y, panel.width - 16, 16), label: title, traits: .header, id: id.part("title"))
        let close = SZRect(panel.maxX - 15, panel.y + 2, 13, 13)
        if iconButton(&o, SZIcons.close, label: "CLOSE", key: .id(id.part("close")), in: close).clicked {
            dismissed = true
        }
        o.region(SZRect(panel.x + 6, panel.y + 22, panel.width - 12, panel.height - 28), clip: true, key: .id(id.part("body"))) { b in
            body(&b)
        }
    }
    return SZSheetResult(dismissed: dismissed, shown: shown)
}

// MARK: - Menu

public struct SZMenuItem: Hashable, Sendable {
    public var label: String
    public var shortcut: String?
    public var disabled: Bool
    public var hint: String?

    public init(_ label: String, shortcut: String? = nil, disabled: Bool = false, hint: String? = nil) {
        self.label = label
        self.shortcut = shortcut
        self.disabled = disabled
        self.hint = hint
    }
}

public struct SZMenuResult: Sendable {
    public var picked: Int?
    public var dismissed: Bool
}

/// A popup list anchored to `anchor` (local). It unrolls downward when
/// opened and rolls back up when closed; tapping outside dismisses it.
@discardableResult
public func menu(
    _ ctx: inout SZContext,
    isPresented: Bool,
    items: [SZMenuItem],
    anchor: SZRect,
    selected: Int? = nil,
    width: Int? = nil,
    key: SZKey? = nil,
) -> SZMenuResult {
    let theme = ctx.theme
    let id = ctx.makeKey(key)
    let reveal = ctx.animatedValue(isPresented ? 1 : 0, id: id.part("reveal"), easing: 0.3, snap: 0.01)
    guard reveal > 0 else { return SZMenuResult(picked: nil, dismissed: false) }
    let rowHeight = 13
    let menuWidth = width ?? max(anchor.width, (items.map { theme.font.measure($0.label) + ($0.shortcut.map { theme.font.measure($0) + 12 } ?? 0) }.max() ?? 0) + 16)
    let fullHeight = items.count * rowHeight + 4
    var result = SZMenuResult(picked: nil, dismissed: false)
    ctx.overlay(key: .id(id.part("overlay"))) { o in
        let screen = SZRect(0, 0, o.ui.screen.width, o.ui.screen.height).offsetBy(-o.origin.x, -o.origin.y)
        let backdrop = o.interaction(screen, sense: [.click, .wheel], id: id.part("backdrop"))
        if backdrop.pressed, isPresented {
            result.dismissed = true
        }
        if isPresented, o.takeKey(.escape) {
            result.dismissed = true
        }

        // Below the anchor, or above when there is no room.
        let below = anchor.maxY + 1 + fullHeight <= screen.maxY
        let x = min(anchor.x, screen.maxX - menuWidth)
        let visibleHeight = Int((Double(fullHeight) * reveal).rounded())
        let full = SZRect(x, below ? anchor.maxY + 1 : anchor.y - 1 - fullHeight, menuWidth, fullHeight)
        let shown = below ? SZRect(full.x, full.y, full.width, visibleHeight) : SZRect(full.x, full.maxY - visibleHeight, full.width, visibleHeight)
        _ = o.interaction(shown, sense: [.click, .wheel], id: id.part("panel"))
        o.fill(SZRect(shown.x + 2, shown.y + 2, shown.width, shown.height), color: theme.background, pattern: SZPatterns.half)
        o.fill(shown, color: theme.panel)
        o.stroke(shown, color: theme.textDim)
        o.clip(shown.inset(by: 1)) { c in
            for (i, item) in items.enumerated() {
                let row = SZRect(full.x + 2, full.y + 2 + i * rowHeight, full.width - 4, rowHeight)
                let itemID = id.child(12, UInt32(i))
                var it = c.interaction(row, sense: item.disabled ? [] : .click, id: itemID)
                if item.disabled {
                    it = SZInteraction(id: itemID)
                }
                c.accessibility(row, label: item.label, traits: item.disabled ? [.button, .notEnabled] : (i == selected ? [.button, .selected] : .button), id: itemID)
                c.hint(item.hint, for: it, rect: row)
                if it.clicked, isPresented, reveal > 0.9 {
                    result.picked = i
                }
                let isSelected = i == selected
                if it.isActive {
                    c.fill(row, color: it.held ? theme.accentBright : theme.accent)
                } else if isSelected {
                    c.fill(SZRect(row.x, row.y + 2, 2, row.height - 4), color: theme.accent)
                }
                let ink = item.disabled ? theme.textDim : it.isActive ? theme.background : isSelected ? theme.paper : theme.text
                c.text(item.label, at: SZPoint(row.x + 6, row.y + 3), font: theme.font, color: ink)
                if let shortcut = item.shortcut {
                    c.text(shortcut, at: SZPoint(row.maxX - 4 - theme.font.measure(shortcut), row.y + 3), font: theme.font, color: it.isActive ? theme.background : theme.textDim)
                }
            }
        }
    }
    return result
}

// MARK: - Dropdown

/// A button showing the current option that opens a menu of the others.
/// Returns the option picked this frame.
public func dropdown(
    _ ctx: inout SZContext,
    _ options: [SZMenuItem],
    selected: Int?,
    placeholder: String = "SELECT",
    width: Int = 90,
    disabled: Bool = false,
    hint: String? = nil,
    key: SZKey? = nil,
) -> Int? {
    let theme = ctx.theme
    let id = ctx.makeKey(key)
    let frame = ctx.place(SZSize(width, 13))
    let open = ctx.state(id: id.part("open"), false)
    var it = ctx.interaction(frame, sense: disabled ? [] : .button, id: id)
    if disabled {
        it = SZInteraction(id: id)
    }
    let title = selected.flatMap { options.indices.contains($0) ? options[$0].label : nil } ?? placeholder
    ctx.accessibility(frame, label: title, value: open.value ? "OPEN" : nil, traits: disabled ? [.button, .notEnabled] : .button, id: id)
    ctx.hint(hint, for: it, rect: frame)
    if it.clicked {
        open.value.toggle()
    }
    let tone = theme.tone(it, on: open.value, disabled: disabled)
    ctx.fill(frame, color: tone.fill)
    ctx.stroke(frame, color: tone.border)
    ctx.text(title, at: SZPoint(frame.x + 4, frame.y + 3), font: theme.font, color: selected == nil ? theme.textDim : tone.ink)
    let chevron = open.value ? SZIcons.chevronUp : SZIcons.chevronDown
    ctx.bitmap(chevron, at: SZPoint(frame.maxX - 9, frame.y + 3), color: tone.ink)
    let result = menu(&ctx, isPresented: open.value, items: options, anchor: frame, selected: selected, width: width, key: .id(id.part("menu")))
    if result.dismissed {
        open.value = false
    }
    if let picked = result.picked {
        open.value = false
        return picked
    }
    return nil
}

// MARK: - Status line and tooltip

/// A one-line footer: shows the current hint, or `text`; a message slides
/// in from below and leaves after `duration`. Bump `serial` to post a new
/// message.
public func statusLine(
    _ ctx: inout SZContext,
    text: String,
    message: String? = nil,
    serial: Int = 0,
    duration: Double = 2.5,
    in rect: SZRect,
) {
    let theme = ctx.theme
    let id = ctx.makeKey()
    let posted = ctx.state(id: id.part("posted"), (serial: serial, time: -Double.infinity))
    if posted.value.serial != serial {
        posted.value = (serial, ctx.time)
    }
    let age = ctx.time - posted.value.time
    let showing = message != nil && age < duration
    if showing {
        ctx.requestFrame()
    }
    let slide = ctx.animatedValue(showing ? 1 : 0, id: id.part("slide"), easing: 0.3, snap: 0.02)

    ctx.fill(rect, color: theme.background)
    ctx.fill(SZRect(rect.x, rect.y, rect.width, 1), color: theme.line)
    ctx.clip(rect) { c in
        let base = rect.y + 3
        let idle = c.ui.hint ?? text
        c.text(idle, at: SZPoint(rect.x + 4, base - Int((slide * Double(rect.height)).rounded())), font: theme.font, color: c.ui.hint == nil ? theme.textDim : theme.paper)
        if let message, slide > 0 {
            let y = base + Int(((1 - slide) * Double(rect.height)).rounded())
            c.fill(SZRect(rect.x + 1, y - 2, 3, 9), color: theme.accent)
            c.text(message, at: SZPoint(rect.x + 8, y), font: theme.font, color: theme.accentBright)
        }
    }
    if let message, showing {
        ctx.accessibility(rect, label: message, traits: .staticText, id: id.part("message"))
    }
}

/// Shows the current hint in a box above what is touched, after `delay`
/// seconds of holding it.
public func tooltip(_ ctx: inout SZContext, delay: Double = 0.5) {
    let theme = ctx.theme
    guard let hint = ctx.ui.hint else { return }
    let age = ctx.ui.hintAge
    guard age >= delay else {
        ctx.requestFrame()
        return
    }
    let reveal = min((age - delay) / 0.12, 1)
    if reveal < 1 {
        ctx.requestFrame()
    }
    let anchor = ctx.ui.hintAnchor.offsetBy(-ctx.origin.x, -ctx.origin.y)
    let layout = ctx.layoutText(hint, font: theme.font, width: 160)
    let size = SZSize(layout.width + 8, layout.height + 5)
    let screen = SZRect(0, 0, ctx.ui.screen.width, ctx.ui.screen.height).offsetBy(-ctx.origin.x, -ctx.origin.y)
    var x = anchor.x + (anchor.width - size.width) / 2
    x = min(max(x, screen.x + 2), screen.maxX - size.width - 2)
    let above = anchor.y - size.height - 4 >= screen.y
    let y = above ? anchor.y - size.height - 4 : anchor.maxY + 4
    ctx.overlay(above: 40) { o in
        let box = SZRect(x, y, size.width, size.height)
        o.fill(box.offsetBy(2, 2), color: theme.background, pattern: SZPatterns.half)
        o.fill(box, color: theme.paper, pattern: reveal < 1 ? SZPatterns.shade(reveal) : SZPatterns.solid)
        if reveal >= 1 {
            o.text(layout, at: SZPoint(x + 4, y + 3), font: theme.font, color: theme.background)
        }
    }
}

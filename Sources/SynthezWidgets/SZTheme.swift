//
//  SZTheme.swift
//  SynthezWidgets
//

import SynthezCore

/// The palette indices and fonts widgets draw with.
public struct SZTheme {
    public var background: SZColor
    public var panel: SZColor
    public var line: SZColor
    public var lineStrong: SZColor
    public var textDim: SZColor
    public var text: SZColor
    public var paper: SZColor
    public var accentDim: SZColor
    public var accent: SZColor
    public var accentBright: SZColor
    public var font: SZBitmapFont

    public init(
        background: SZColor,
        panel: SZColor,
        line: SZColor,
        lineStrong: SZColor,
        textDim: SZColor,
        text: SZColor,
        paper: SZColor,
        accentDim: SZColor,
        accent: SZColor,
        accentBright: SZColor,
        font: SZBitmapFont,
    ) {
        self.background = background
        self.panel = panel
        self.line = line
        self.lineStrong = lineStrong
        self.textDim = textDim
        self.text = text
        self.paper = paper
        self.accentDim = accentDim
        self.accent = accent
        self.accentBright = accentBright
        self.font = font
    }

    /// Fourteen warm greys from black to paper, then four oranges, ordered
    /// by lightness so color maps always land on a real step.
    public static func synthPalette() -> SZPalette {
        SZPalette(colors: [
            0x0B0908, 0x14110F, 0x1C1815, 0x25201C, 0x2F2924, 0x3A332D, 0x4A4139,
            0x5C5148, 0x706359, 0x86786C, 0x9E9083, 0xB7A99B, 0xD0C3B5, 0xE8DDCF,
            0x5A2410, 0x9C3D14, 0xE3621E, 0xFF9A4D,
        ].map { SZRGBA(hex: $0) })
    }

    /// The theme for ``synthPalette()``.
    public static func synth() -> SZTheme {
        SZTheme(
            background: 1,
            panel: 2,
            line: 4,
            lineStrong: 6,
            textDim: 8,
            text: 11,
            paper: 13,
            accentDim: 15,
            accent: 16,
            accentBright: 17,
            font: .pixel5x7(),
        )
    }

    /// Ink, fill and border for a control at rest, hovered or held.
    public func tone(_ it: SZInteraction, on: Bool = false, disabled: Bool = false) -> (ink: SZColor, fill: SZColor, border: SZColor) {
        if disabled {
            return (textDim, background, line)
        }
        if on {
            return (background, it.held ? accentBright : accent, accent)
        }
        if it.held {
            return (background, text, text)
        }
        if it.hovered {
            return (paper, panel, textDim)
        }
        return (text, background, lineStrong)
    }
}

/// The theme widgets read from ``SZUI/environment(_:)``.
public enum SZThemeKey: SZEnvironmentKey {
    public static var defaultValue: SZTheme {
        fallback
    }

    private nonisolated(unsafe) static let fallback = SZTheme.synth()
}

public extension SZContext {
    var theme: SZTheme {
        ui.environment(SZThemeKey.self)
    }
}

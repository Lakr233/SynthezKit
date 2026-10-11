//
//  SZBitmapFont.swift
//  SynthezCore
//

/// A 1-bit font whose glyphs are ``SZBitmap``s.
///
/// Each glyph's bitmap width is its advance, so the same type covers
/// monospaced and proportional fonts. ASCII resolves through a flat table;
/// everything else through a dictionary.
///
/// - Important: Performance-sensitive. ``glyphIndex(for:)`` and
///   ``measure(_:)`` run for every character drawn every frame.
public final class SZBitmapFont {
    public let name: String
    public let glyphs: [SZBitmap]
    /// Pixels between glyphs.
    public let spacing: Int
    /// The height of one line, including the gap below it.
    public let lineHeight: Int
    /// The tallest glyph.
    public let glyphHeight: Int
    /// Maps lowercase to uppercase before lookup, for caps-only fonts.
    public let caps: Bool

    private var ascii: [Int16]
    private var others: [UInt32: Int16]
    private let fallback: Int16

    /// - Parameters:
    ///   - glyphs: The characters each bitmap draws.
    ///   - fallback: Drawn for characters the font lacks; it must be one of `glyphs`' keys.
    public init(
        name: String,
        glyphs: [(Character, SZBitmap)],
        spacing: Int = 1,
        lineHeight: Int? = nil,
        caps: Bool = false,
        fallback: Character = "?",
    ) {
        self.name = name
        self.spacing = spacing
        self.caps = caps
        var bitmaps: [SZBitmap] = []
        var ascii = [Int16](repeating: -1, count: 128)
        var others: [UInt32: Int16] = [:]
        var fallbackIndex: Int16 = -1
        for (character, bitmap) in glyphs {
            let index = Int16(bitmaps.count)
            bitmaps.append(bitmap)
            for scalar in character.unicodeScalars.prefix(1) {
                if scalar.value < 128 {
                    ascii[Int(scalar.value)] = index
                } else {
                    others[scalar.value] = index
                }
            }
            if character == fallback {
                fallbackIndex = index
            }
        }
        precondition(!bitmaps.isEmpty, "A font needs at least one glyph")
        self.glyphs = bitmaps
        self.ascii = ascii
        self.others = others
        self.fallback = max(fallbackIndex, 0)
        glyphHeight = bitmaps.map(\.height).max() ?? 0
        self.lineHeight = lineHeight ?? glyphHeight + 1
    }

    /// Adds `alias` as another name for the glyph of `character`.
    public func alias(_ alias: Character, to character: Character) {
        guard let source = character.unicodeScalars.first, let target = alias.unicodeScalars.first else { return }
        let index = glyphIndex(for: source.value)
        if target.value < 128 {
            ascii[Int(target.value)] = index
        } else {
            others[target.value] = index
        }
    }

    @inline(__always)
    public func glyphIndex(for scalar: UInt32) -> Int16 {
        var scalar = scalar
        if caps, scalar >= 0x61, scalar <= 0x7A {
            scalar -= 0x20
        }
        if scalar < 128 {
            let index = ascii[Int(scalar)]
            return index >= 0 ? index : fallback
        }
        return others[scalar] ?? fallback
    }

    /// The width of `text` on one line, without trailing spacing.
    public func measure(_ text: some StringProtocol) -> Int {
        var width = 0
        var count = 0
        for scalar in text.unicodeScalars {
            width += glyphs[Int(glyphIndex(for: scalar.value))].width
            count += 1
        }
        return count == 0 ? 0 : width + (count - 1) * spacing
    }
}

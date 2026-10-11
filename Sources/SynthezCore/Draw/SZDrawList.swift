//
//  SZDrawList.swift
//  SynthezCore
//

/// One drawing primitive. Coordinates are absolute virtual pixels.
public enum SZDrawOp: Equatable {
    case fill(SZRect, SZColor, SZPattern)
    /// A 1-pixel outline inside the rectangle.
    case stroke(SZRect, SZColor)
    /// Bresenham, both ends included.
    case line(SZPoint, SZPoint, SZColor)
    case circle(center: SZPoint, radius: Int, SZColor, filled: Bool)
    case pixel(SZPoint, SZColor)
    case bitmap(SZBitmap, SZPoint, SZColor, scale: Int)
    /// `glyphs` indexes ``SZDrawList/glyphs``; `font` indexes ``SZDrawList/fonts``.
    case text(font: UInt16, glyphs: Range<Int32>, SZPoint, SZColor, scale: Int)
    /// Maps pixels already drawn through `map` where `pattern` covers them.
    case remap(SZRect, SZColorMap, SZPattern)
    /// Pixelates: each `size`×`size` block takes the color at its center.
    case mosaic(SZRect, size: Int)
    /// Moves what is drawn toward a color by a strength field.
    case filter(SZRect, SZStrengthField, SZFilterMaps, SZFilterBlend)
}

extension SZColorMap: Equatable {
    public static func == (lhs: SZColorMap, rhs: SZColorMap) -> Bool {
        lhs === rhs
    }
}

public struct SZDrawCommand: Equatable {
    /// Index into ``SZDrawList/clips``.
    public var clip: UInt16
    public var op: SZDrawOp
}

/// The commands of one frame, bucketed by layer.
///
/// Overlays are drawn in the middle of their parents' content but must land
/// on top, so commands collect per layer and replay layer by layer. Every
/// command carries the index of its clip rectangle, so replay needs no
/// clip stack.
///
/// A list keeps its storage between frames, and ``isEqual(to:)`` lets the
/// host skip rasterizing a frame that came out the same as the last.
public final class SZDrawList {
    public private(set) var layers: [[SZDrawCommand]] = []
    public private(set) var clips: [SZRect] = []
    /// Glyph indices of every text command, back to back.
    public private(set) var glyphs: [Int16] = []
    public private(set) var fonts: [SZBitmapFont] = []
    public private(set) var background: SZColor = 0
    private var fontSlots: [ObjectIdentifier: UInt16] = [:]

    public init() {}

    public var commandCount: Int {
        layers.reduce(0) { $0 + $1.count }
    }

    /// Clears the list for a new frame; clip 0 becomes `screen`.
    public func begin(screen: SZRect, background: SZColor) {
        for i in layers.indices {
            layers[i].removeAll(keepingCapacity: true)
        }
        clips.removeAll(keepingCapacity: true)
        clips.append(screen)
        glyphs.removeAll(keepingCapacity: true)
        self.background = background
        // Fonts stay registered across frames; their slots are stable.
    }

    /// Registers a clip rectangle and returns its index.
    public func addClip(_ rect: SZRect) -> UInt16 {
        precondition(clips.count < Int(UInt16.max), "Too many clip rectangles in one frame")
        clips.append(rect)
        return UInt16(clips.count - 1)
    }

    @inline(__always)
    public func append(_ op: SZDrawOp, clip: UInt16, layer: Int) {
        if layer >= layers.count {
            layers.append(contentsOf: repeatElement([], count: layer + 1 - layers.count))
        }
        layers[layer].append(SZDrawCommand(clip: clip, op: op))
    }

    /// Resolves `text` to glyphs, records it, and returns its width.
    @discardableResult
    public func appendText(
        _ text: some StringProtocol,
        font: SZBitmapFont,
        at origin: SZPoint,
        color: SZColor,
        scale: Int,
        clip: UInt16,
        layer: Int,
    ) -> Int {
        let start = Int32(glyphs.count)
        var width = 0
        for scalar in text.unicodeScalars {
            let index = font.glyphIndex(for: scalar.value)
            glyphs.append(index)
            width += font.glyphs[Int(index)].width + font.spacing
        }
        let end = Int32(glyphs.count)
        guard end > start else { return 0 }
        append(.text(font: slot(for: font), glyphs: start ..< end, origin, color, scale: scale), clip: clip, layer: layer)
        return (width - font.spacing) * scale
    }

    private func slot(for font: SZBitmapFont) -> UInt16 {
        let id = ObjectIdentifier(font)
        if let slot = fontSlots[id] {
            return slot
        }
        let slot = UInt16(fonts.count)
        fonts.append(font)
        fontSlots[id] = slot
        return slot
    }

    /// Whether `other` draws exactly what this list draws.
    ///
    /// Empty trailing layers are ignored, so a frame that stopped using an
    /// overlay layer still compares equal to one that never had it.
    public func isEqual(to other: SZDrawList) -> Bool {
        guard background == other.background, clips == other.clips, glyphs == other.glyphs else { return false }
        let a = layers.lastIndex { !$0.isEmpty } ?? -1
        let b = other.layers.lastIndex { !$0.isEmpty } ?? -1
        guard a == b else { return false }
        guard a >= 0 else { return true }
        for i in 0 ... a {
            guard layers[i] == other.layers[i] else { return false }
        }
        // Font slots must name the same fonts for text to match.
        let usedFonts = min(fonts.count, other.fonts.count)
        for i in 0 ..< usedFonts where fonts[i] !== other.fonts[i] {
            return false
        }
        return true
    }
}

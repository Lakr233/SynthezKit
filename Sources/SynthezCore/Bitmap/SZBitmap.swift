//
//  SZBitmap.swift
//  SynthezCore
//

/// A 1-bit image up to 64 pixels wide: icons and glyphs.
///
/// Each row is one `UInt64`; bit `x` set means the pixel at column `x` is on.
public struct SZBitmap: Hashable, Sendable {
    public let width: Int
    public let height: Int
    public let rows: [UInt64]

    public init(width: Int, rows: [UInt64]) {
        precondition(width >= 0 && width <= 64, "SZBitmap is at most 64 pixels wide")
        self.width = width
        height = rows.count
        self.rows = rows
    }

    /// Parses rows such as `".##."` where `#` (or any character but `.` and
    /// space) is on. The widest row sets the width.
    public init(_ art: [String]) {
        var rows: [UInt64] = []
        rows.reserveCapacity(art.count)
        var width = 0
        for line in art {
            var bits: UInt64 = 0
            var x = 0
            for ch in line.utf8 {
                if ch != UInt8(ascii: "."), ch != UInt8(ascii: " ") {
                    bits |= 1 << UInt64(x)
                }
                x += 1
            }
            width = max(width, x)
            rows.append(bits)
        }
        self.init(width: width, rows: rows)
    }
}

/// A 4×4 ordered-dither mask anchored to screen coordinates, so neighbouring
/// fills with the same pattern line up. Bit `(y & 3) * 4 + (x & 3)` set means
/// the pixel is drawn.
public typealias SZPattern = UInt16

public enum SZPatterns {
    public static let solid: SZPattern = 0xFFFF
    public static let clear: SZPattern = 0

    /// The 4×4 Bayer threshold matrix.
    public static let bayer: [UInt8] = [
        0, 8, 2, 10,
        12, 4, 14, 6,
        3, 11, 1, 9,
        15, 7, 13, 5,
    ]

    /// The first `level` (0...16) cells of the Bayer order. Levels nest, so a
    /// fade that steps through them never flickers.
    public static func dither(_ level: Int) -> SZPattern {
        let level = min(max(level, 0), 16)
        var pattern: SZPattern = 0
        for i in 0 ..< 16 where Int(bayer[i]) < level {
            pattern |= 1 << SZPattern(i)
        }
        return pattern
    }

    /// `dither` by coverage, 0...1.
    public static func shade(_ amount: Double) -> SZPattern {
        dither(Int((min(max(amount, 0), 1) * 16).rounded()))
    }

    /// A 50% checkerboard.
    public static let half: SZPattern = dither(8)

    @inlinable public static func covers(_ pattern: SZPattern, _ x: Int, _ y: Int) -> Bool {
        pattern & (1 << SZPattern((y & 3) << 2 | (x & 3))) != 0
    }
}

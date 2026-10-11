//
//  SZPalette.swift
//  SynthezCore
//

import Foundation

/// An 8-bit sRGB color with alpha.
public struct SZRGBA: Hashable, Sendable {
    public var r: UInt8
    public var g: UInt8
    public var b: UInt8
    public var a: UInt8

    public init(_ r: UInt8, _ g: UInt8, _ b: UInt8, _ a: UInt8 = 255) {
        self.r = r
        self.g = g
        self.b = b
        self.a = a
    }

    /// `0xRRGGBB`.
    public init(hex: UInt32) {
        self.init(UInt8((hex >> 16) & 0xFF), UInt8((hex >> 8) & 0xFF), UInt8(hex & 0xFF))
    }
}

/// An index into a ``SZPalette``. Everything SynthezKit draws is a palette
/// index; the presenter turns indices into colors on the GPU.
public typealias SZColor = UInt8

/// Up to 256 colors, plus the color maps derived from them.
///
/// Fades, shadows and dimming never blend: they map every palette color to
/// the nearest palette color of the blended result, measured in OKLab, so
/// the screen keeps the palette's look. A palette whose colors form ramps
/// (dark to light) gives smooth fades.
public final class SZPalette {
    public let colors: [SZRGBA]
    /// Bumped whenever the colors change, so presenters upload only then.
    public let version: UInt64

    private let lab: [SIMD3<Float>]
    private var mixCache: [Int: SZColorMap] = [:]
    var filterCache: [SZColor: SZFilterMaps] = [:]
    private var nextMapID: UInt32 = 1

    private nonisolated(unsafe) static var versionCounter: UInt64 = 0

    public init(colors: [SZRGBA]) {
        precondition(!colors.isEmpty && colors.count <= 256, "A palette holds 1...256 colors")
        self.colors = colors
        lab = colors.map(Self.oklab)
        Self.versionCounter &+= 1
        version = Self.versionCounter
    }

    public var count: Int {
        colors.count
    }

    /// The palette color closest to `color`, in OKLab.
    public func nearest(to color: SIMD3<Float>) -> SZColor {
        var best = 0
        var bestDistance = Float.infinity
        for (i, candidate) in lab.enumerated() {
            let d = candidate - color
            let distance = (d * d).sum()
            if distance < bestDistance {
                bestDistance = distance
                best = i
            }
        }
        return SZColor(best)
    }

    /// The map that moves every color `t` (0...1) of the way toward `target`.
    ///
    /// `t` is quantized to 1/32 steps and each step is built once.
    public func mixMap(toward target: SZColor, amount t: Double) -> SZColorMap {
        let level = Int((min(max(t, 0), 1) * 32).rounded())
        let cacheKey = Int(target) << 8 | level
        if let map = mixCache[cacheKey] {
            return map
        }
        let goal = lab[Int(target)]
        let f = Float(level) / 32
        var table = [UInt8](repeating: 0, count: 256)
        for i in 0 ..< 256 {
            guard i < lab.count else { table[i] = UInt8(i); continue }
            table[i] = level == 0 ? UInt8(i) : nearest(to: lab[i] + (goal - lab[i]) * f)
        }
        let map = SZColorMap(id: nextMapID, table: table)
        nextMapID &+= 1
        mixCache[cacheKey] = map
        return map
    }

    // MARK: - OKLab

    private static func oklab(_ c: SZRGBA) -> SIMD3<Float> {
        func linear(_ v: UInt8) -> Float {
            let s = Float(v) / 255
            return s <= 0.04045 ? s / 12.92 : powf((s + 0.055) / 1.055, 2.4)
        }
        let r = linear(c.r), g = linear(c.g), b = linear(c.b)
        let l = cbrtf(0.4122214708 * r + 0.5363325363 * g + 0.0514459929 * b)
        let m = cbrtf(0.2119034982 * r + 0.6806995451 * g + 0.1073969566 * b)
        let s = cbrtf(0.0883024619 * r + 0.2817188376 * g + 0.6299787005 * b)
        return SIMD3(
            0.2104542553 * l + 0.7936177850 * m - 0.0040720468 * s,
            1.9779984951 * l - 2.4285922050 * m + 0.4505937099 * s,
            0.0259040371 * l + 0.7827717662 * m - 0.8086757660 * s,
        )
    }
}

/// A 256-entry index-to-index lookup, applied to pixels already drawn.
public final class SZColorMap {
    public let id: UInt32
    public let table: [UInt8]

    public init(id: UInt32, table: [UInt8]) {
        precondition(table.count == 256)
        self.id = id
        self.table = table
    }
}

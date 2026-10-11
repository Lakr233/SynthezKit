//
//  SZFilter.swift
//  SynthezCore
//

/// How strongly a filter applies at each pixel, 0...1, evaluated at pixel
/// centers in absolute virtual pixels.
public enum SZStrengthField: Equatable, Sendable {
    case constant(Double)
    /// `start` at `from`, `end` at `to`, clamped beyond.
    case linear(from: SZPoint, to: SZPoint, start: Double, end: Double)
    /// `start` within `inner` of `center`, `end` from `outer` on.
    case radial(center: SZPoint, inner: Double, outer: Double, start: Double, end: Double)

    @inline(__always)
    func strength(_ x: Int, _ y: Int) -> Double {
        switch self {
        case let .constant(s):
            return s
        case let .linear(from, to, start, end):
            let dx = Double(to.x - from.x), dy = Double(to.y - from.y)
            let length = dx * dx + dy * dy
            guard length > 0 else { return end }
            let t = ((Double(x) + 0.5 - Double(from.x)) * dx + (Double(y) + 0.5 - Double(from.y)) * dy) / length
            return start + (end - start) * min(max(t, 0), 1)
        case let .radial(center, inner, outer, start, end):
            let dx = Double(x) + 0.5 - Double(center.x), dy = Double(y) + 0.5 - Double(center.y)
            let d = (dx * dx + dy * dy).squareRoot()
            let t = outer > inner ? (d - inner) / (outer - inner) : (d >= outer ? 1 : 0)
            return start + (end - start) * min(max(t, 0), 1)
        }
    }

    func offsetBy(_ dx: Int, _ dy: Int) -> SZStrengthField {
        switch self {
        case .constant: self
        case let .linear(from, to, start, end):
            .linear(from: SZPoint(from.x + dx, from.y + dy), to: SZPoint(to.x + dx, to.y + dy), start: start, end: end)
        case let .radial(center, inner, outer, start, end):
            .radial(center: SZPoint(center.x + dx, center.y + dy), inner: inner, outer: outer, start: start, end: end)
        }
    }
}

/// How a filter turns strength into pixels.
public enum SZFilterBlend: Hashable, Sendable {
    /// Replaces a pixel outright where the Bayer threshold is below the
    /// strength: the area dissolves.
    case dither
    /// Maps every pixel part of the way along the palette toward the
    /// target, in quantized steps.
    case steps
}

/// The color maps a filter steps through, from untouched (first) to fully
/// the target (last).
public final class SZFilterMaps {
    public let maps: [SZColorMap]

    init(maps: [SZColorMap]) {
        self.maps = maps
    }
}

extension SZFilterMaps: Equatable {
    public static func == (lhs: SZFilterMaps, rhs: SZFilterMaps) -> Bool {
        lhs === rhs
    }
}

public extension SZPalette {
    /// Maps toward `target` in 32 steps, built once per target.
    func filterMaps(toward target: SZColor) -> SZFilterMaps {
        if let maps = filterCache[target] {
            return maps
        }
        let maps = SZFilterMaps(maps: (0 ... 32).map { mixMap(toward: target, amount: Double($0) / 32) })
        filterCache[target] = maps
        return maps
    }
}

//
//  SZGeometry.swift
//  SynthezCore
//

/// A point in virtual pixels.
public struct SZPoint: Hashable, Sendable {
    public var x: Int
    public var y: Int

    @inlinable public init(_ x: Int, _ y: Int) {
        self.x = x
        self.y = y
    }

    public static let zero = SZPoint(0, 0)

    @inlinable public static func + (lhs: SZPoint, rhs: SZPoint) -> SZPoint {
        SZPoint(lhs.x + rhs.x, lhs.y + rhs.y)
    }

    @inlinable public static func - (lhs: SZPoint, rhs: SZPoint) -> SZPoint {
        SZPoint(lhs.x - rhs.x, lhs.y - rhs.y)
    }
}

/// A size in virtual pixels.
public struct SZSize: Hashable, Sendable {
    public var width: Int
    public var height: Int

    @inlinable public init(_ width: Int, _ height: Int) {
        self.width = width
        self.height = height
    }

    public static let zero = SZSize(0, 0)
}

/// An axis-aligned rectangle in whole virtual pixels.
///
/// The right and bottom edges are exclusive: `SZRect(0, 0, 2, 2)` covers the
/// pixels (0,0), (1,0), (0,1) and (1,1). A rectangle with a non-positive width
/// or height is empty.
public struct SZRect: Hashable, Sendable {
    public var x: Int
    public var y: Int
    public var width: Int
    public var height: Int

    @inlinable public init(_ x: Int, _ y: Int, _ width: Int, _ height: Int) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }

    @inlinable public init(origin: SZPoint, size: SZSize) {
        self.init(origin.x, origin.y, size.width, size.height)
    }

    public static let zero = SZRect(0, 0, 0, 0)

    @inlinable public var minX: Int {
        x
    }

    @inlinable public var minY: Int {
        y
    }

    @inlinable public var maxX: Int {
        x + width
    }

    @inlinable public var maxY: Int {
        y + height
    }

    @inlinable public var origin: SZPoint {
        SZPoint(x, y)
    }

    @inlinable public var size: SZSize {
        SZSize(width, height)
    }

    @inlinable public var isEmpty: Bool {
        width <= 0 || height <= 0
    }

    @inlinable public func contains(_ p: SZPoint) -> Bool {
        p.x >= x && p.y >= y && p.x < maxX && p.y < maxY
    }

    @inlinable public func intersection(_ other: SZRect) -> SZRect {
        let x0 = Swift.max(x, other.x)
        let y0 = Swift.max(y, other.y)
        let x1 = Swift.min(maxX, other.maxX)
        let y1 = Swift.min(maxY, other.maxY)
        return SZRect(x0, y0, Swift.max(x1 - x0, 0), Swift.max(y1 - y0, 0))
    }

    @inlinable public func union(_ other: SZRect) -> SZRect {
        if isEmpty {
            return other
        }
        if other.isEmpty {
            return self
        }
        let x0 = Swift.min(x, other.x)
        let y0 = Swift.min(y, other.y)
        return SZRect(x0, y0, Swift.max(maxX, other.maxX) - x0, Swift.max(maxY, other.maxY) - y0)
    }

    @inlinable public func offsetBy(_ dx: Int, _ dy: Int) -> SZRect {
        SZRect(x + dx, y + dy, width, height)
    }

    /// Shrinks the rectangle in CSS order; negative values grow it.
    @inlinable public func inset(top: Int, right: Int, bottom: Int, left: Int) -> SZRect {
        SZRect(x + left, y + top, Swift.max(width - left - right, 0), Swift.max(height - top - bottom, 0))
    }

    @inlinable public func inset(by amount: Int) -> SZRect {
        inset(top: amount, right: amount, bottom: amount, left: amount)
    }

    /// The origin that centers `size` inside this rectangle, rounded down so
    /// it lands on a whole pixel.
    @inlinable public func centered(_ size: SZSize) -> SZRect {
        SZRect(x + (width - size.width) / 2, y + (height - size.height) / 2, size.width, size.height)
    }
}

public enum SZAxis: Sendable {
    case horizontal
    case vertical
}

/// Cross-axis alignment for ``SZContext/place(_:)``.
public enum SZAlignment: Sendable {
    case start
    case center
    case end
    case stretch
}

//
//  SZScreen.swift
//  SynthezCore
//

/// How virtual pixels map onto a view.
public enum SZResolution: Hashable, Sendable {
    /// A fixed virtual size, scaled to fit and letterboxed.
    case fixed(width: Int, height: Int)
    /// Each virtual pixel is `scale` device pixels; the virtual size follows
    /// the view.
    case pixelScale(Double)
    /// Each virtual pixel is `scale` view points, so pixels look the same
    /// size on 1×, 2× and 3× screens; the virtual size follows the view.
    case pointScale(Double)
}

/// The virtual screen for a view of a given device-pixel size.
public struct SZScreen: Hashable, Sendable {
    /// Virtual pixels.
    public var size: SZSize
    /// Device pixels per virtual pixel, possibly fractional.
    public var scale: Double
    /// Where the scaled screen lands, in device pixels.
    public var viewportX: Double
    public var viewportY: Double
    public var viewportWidth: Double
    public var viewportHeight: Double

    /// - Parameter deviceScale: Device pixels per view point, for
    ///   ``SZResolution/pointScale(_:)``.
    public init(resolution: SZResolution, deviceWidth: Double, deviceHeight: Double, deviceScale: Double = 1) {
        let deviceWidth = max(deviceWidth, 1), deviceHeight = max(deviceHeight, 1)
        let resolution: SZResolution = switch resolution {
        case let .pointScale(points): .pixelScale(points * max(deviceScale, 1))
        default: resolution
        }
        switch resolution {
        case let .fixed(width, height):
            let width = max(width, 1), height = max(height, 1)
            size = SZSize(width, height)
            scale = min(deviceWidth / Double(width), deviceHeight / Double(height))
        case let .pixelScale(s):
            let s = max(s, 1)
            size = SZSize(max(Int(deviceWidth / s), 1), max(Int(deviceHeight / s), 1))
            scale = s
        case .pointScale:
            preconditionFailure("Resolved to pixelScale above")
        }
        viewportWidth = Double(size.width) * scale
        viewportHeight = Double(size.height) * scale
        viewportX = ((deviceWidth - viewportWidth) / 2).rounded(.down)
        viewportY = ((deviceHeight - viewportHeight) / 2).rounded(.down)
    }

    /// The virtual pixel under a device-pixel point.
    public func virtualPoint(deviceX: Double, deviceY: Double) -> SZPoint {
        SZPoint(Int(((deviceX - viewportX) / scale).rounded(.down)), Int(((deviceY - viewportY) / scale).rounded(.down)))
    }
}

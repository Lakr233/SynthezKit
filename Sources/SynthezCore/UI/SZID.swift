//
//  SZID.swift
//  SynthezCore
//

/// Identifies state, interactions and animations across frames.
///
/// IDs are derived, never stored as strings: a region's children mix the
/// region's ID with a tag and a running counter, so the same calls in the
/// same order yield the same IDs every frame without allocating.
public struct SZID: Hashable, Sendable, CustomStringConvertible {
    public let raw: UInt64

    @inlinable public init(raw: UInt64) {
        self.raw = raw
    }

    /// A global ID from a string, independent of where it is used.
    public init(_ key: some StringProtocol) {
        // FNV-1a.
        var hash: UInt64 = 0xCBF2_9CE4_8422_2325
        for byte in key.utf8 {
            hash ^= UInt64(byte)
            hash &*= 0x0000_0100_0000_01B3
        }
        raw = Self.mix(hash)
    }

    /// A global ID from an integer, such as a row's model identifier.
    @inlinable public init(_ value: Int) {
        raw = Self.mix(UInt64(bitPattern: Int64(value)) ^ 0x9E37_79B9_7F4A_7C15)
    }

    public static let root = SZID(raw: 0x5359_4E54_4845_5A00)

    /// A child of this ID: `tag` names the kind, `index` the position.
    @inlinable public func child(_ tag: UInt8, _ index: UInt32) -> SZID {
        SZID(raw: Self.mix(raw &+ (UInt64(tag) << 32 | UInt64(index)) &* 0x9E37_79B9_7F4A_7C15))
    }

    /// A named part of this ID, such as a slider's thumb.
    public func part(_ name: some StringProtocol) -> SZID {
        SZID(raw: Self.mix(raw ^ SZID(name).raw))
    }

    /// SplitMix64's finalizer.
    @inlinable static func mix(_ value: UInt64) -> UInt64 {
        var z = value &+ 0x9E37_79B9_7F4A_7C15
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }

    public var description: String {
        "SZID(\(String(raw, radix: 16)))"
    }
}

/// An explicit key a caller passes to pin state to something other than
/// call position.
public enum SZKey: Hashable, Sendable {
    case string(String)
    case int(Int)
    case id(SZID)

    public var id: SZID {
        switch self {
        case let .string(value): SZID(value)
        case let .int(value): SZID(value)
        case let .id(value): value
        }
    }
}

extension SZKey: ExpressibleByStringLiteral, ExpressibleByIntegerLiteral {
    public init(stringLiteral value: String) {
        self = .string(value)
    }

    public init(integerLiteral value: Int) {
        self = .int(value)
    }
}

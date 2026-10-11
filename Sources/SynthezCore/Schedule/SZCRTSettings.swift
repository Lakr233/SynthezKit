//
//  SZCRTSettings.swift
//  SynthezCore
//

/// The shadow mask a CRT draws its pixels through.
public enum SZCRTMask: Int, Hashable, Sendable, CaseIterable {
    case none
    /// Vertical RGB stripes.
    case aperture
    /// Stripes broken every few rows, staggered between triads.
    case slot
    /// RGB dots offset on alternate rows.
    case shadow
}

/// Parameters for the CRT post-process. Everything is modeled in linear
/// light, so brighter content glows more without picking what glows.
public struct SZCRTSettings: Hashable, Sendable {
    public var isEnabled = false
    /// How dark the gaps between scanlines get, 0...1.
    public var scanlines = 0.65
    /// Beam width (in virtual rows) for dark and bright content: bright rows
    /// swell and fill the gaps.
    public var beamDim = 0.28
    public var beamBright = 0.52
    public var mask = SZCRTMask.aperture
    public var maskStrength = 0.3
    /// Glow around bright content.
    public var halation = 0.3
    /// How far the glow spreads, in halving steps (1...6).
    public var spread = 4
    public var vignette = 0.3
    /// Phosphor decay time in seconds for the red channel; green and blue
    /// fade faster.
    public var persistence = 0.04
    public var brightness = 1.2
    /// Light reflected off the glass.
    public var ambient = 0.002

    public init() {}

    /// How long after the last change frames must keep coming for the
    /// afterglow to fade below a thousandth.
    public var afterglow: Double {
        isEnabled ? persistence * 7 : 0
    }
}

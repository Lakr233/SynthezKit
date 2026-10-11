//
//  SZEase.swift
//  SynthezCore
//

import Foundation

public enum SZEase {
    /// Moves `current` toward `target`, covering `easing` of the remaining
    /// distance every 1/60 s whatever the frame rate, and snapping once
    /// within `snap`.
    @inlinable public static func approach(_ current: Double, to target: Double, dt: Double, easing: Double = 0.15, snap: Double = 0.5) -> Double {
        if abs(target - current) <= snap {
            return target
        }
        let k = 1 - pow(1 - min(max(easing, 0), 1), dt * 60)
        let next = current + (target - current) * k
        return abs(target - next) <= snap ? target : next
    }
}

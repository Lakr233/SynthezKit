//
//  SZFrameScheduler.swift
//  SynthezCore
//

/// Decides whether a display refresh needs a frame, so an idle canvas costs
/// nothing and its display link can pause.
public struct SZFrameScheduler: Sendable {
    public enum Mode: Sendable {
        /// Draw only when something changed, something moves, or input
        /// arrived.
        case auto
        /// Draw on every refresh.
        case always
    }

    public var mode: Mode
    /// Keep drawing this long after the last change, for effects that fade
    /// on their own such as CRT afterglow.
    public var settleDuration: Double

    private var isDirty = true
    private var settleUntil = -Double.infinity
    private var wakeAt: Double?

    public init(mode: Mode = .auto, settleDuration: Double = 0) {
        self.mode = mode
        self.settleDuration = settleDuration
    }

    /// A frame was asked for at a later time; keep the link ticking.
    public var hasPendingWake: Bool {
        wakeAt != nil
    }

    /// Something outside the UI changed (size, palette, app state).
    public mutating func invalidate() {
        isDirty = true
    }

    /// Whether the refresh at `time` should run a frame.
    public func isDue(at time: Double, hasInput: Bool) -> Bool {
        switch mode {
        case .always: true
        case .auto: isDirty || hasInput || time < settleUntil || wakeAt.map { time >= $0 } ?? false
        }
    }

    /// Records a frame; returns whether another refresh will be needed, so
    /// the host can pause its display link when it is not.
    public mutating func didDraw(at time: Double, result: SZFrameResult) -> Bool {
        isDirty = result.needsAnotherFrame
        wakeAt = result.wakeAt
        if result.changed {
            settleUntil = time + settleDuration
        }
        // A pending wake keeps the link ticking; refreshes before it are
        // skipped by isDue.
        return mode == .always || isDirty || time < settleUntil || wakeAt != nil
    }
}

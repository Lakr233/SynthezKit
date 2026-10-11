//
//  SZCanvasEngine.swift
//  SynthezKit
//

import DisplayLink
import QuartzCore
@_exported import SynthezCore

/// Everything a canvas does that does not depend on UIKit or AppKit: the
/// display link, the scheduler, the frame, rasterizing, presenting, and
/// mapping between view points and virtual pixels.
///
/// ``SZCanvasView`` owns one and forwards events to it.
@MainActor
public final class SZCanvasEngine: DisplayLinkDelegate {
    public let ui: SZUI

    /// Builds each frame.
    public var body: ((inout SZContext) -> Void)? {
        didSet { invalidate() }
    }

    public var resolution: SZResolution {
        didSet {
            if resolution != oldValue {
                relayout()
            }
        }
    }

    public var scheduler: SZFrameScheduler {
        get { frameScheduler }
        set {
            frameScheduler = newValue
            wake()
        }
    }

    /// The CRT post-process. While enabled, frames keep coming for the
    /// afterglow to fade after each change.
    public var crt = SZCRTSettings() {
        didSet {
            guard crt != oldValue else { return }
            frameScheduler.settleDuration = crt.afterglow
            needsPresent = true
            wake()
        }
    }

    /// The frame rate the canvas asks for while active.
    public var preferredFrameRateRange: DisplayLinkFrameRateRange = .default {
        didSet { displayLink?.preferredFrameRateRange = preferredFrameRateRange }
    }

    /// The virtual screen for the current size.
    public private(set) var screen: SZScreen

    /// Frames run and frames presented, for diagnostics.
    public private(set) var framesBuilt = 0
    public private(set) var framesRasterized = 0
    public private(set) var framesPresented = 0

    /// Called after each frame with the keyboard a text widget wants, or nil.
    var onTextInput: ((SZTextInputRequest?) -> Void)?

    private weak var view: SZPlatformView?
    private let metalLayer: CAMetalLayer
    private let presenter: SZMetalPresenter?
    private let surface = SZSurface(width: 0, height: 0)
    private var displayLink: DisplayLink?
    private var pendingEvents: [SZInputEvent] = []
    private var frameEvents: [SZInputEvent] = []
    private var needsPresent = true
    private var needsUpload = true
    private var lastPresentTime: Double?
    private var frameScheduler: SZFrameScheduler
    private var pointSize = CGSize.zero
    /// Device pixels per view point.
    private(set) var pointScale: Double = 1

    init(view: SZPlatformView, layer: CAMetalLayer, palette: SZPalette, background: SZColor, resolution: SZResolution, scheduler: SZFrameScheduler) {
        ui = SZUI(palette: palette, background: background)
        self.view = view
        metalLayer = layer
        self.resolution = resolution
        frameScheduler = scheduler
        presenter = SZMetalPresenter()
        screen = SZScreen(resolution: resolution, deviceWidth: 1, deviceHeight: 1)
        presenter?.configure(layer)
    }

    // MARK: - Frames

    /// Draws a new frame at the next refresh.
    public func invalidate() {
        frameScheduler.invalidate()
        wake()
    }

    /// Queues an event for the next frame.
    public func send(_ event: SZInputEvent) {
        pendingEvents.append(event)
        wake()
    }

    func wake() {
        guard let view, view.window != nil else { return }
        if let displayLink {
            displayLink.isPaused = false
        } else {
            let link = DisplayLink(context: .view(view), preferredFrameRateRange: preferredFrameRateRange)
            link.delegate = self
            displayLink = link
        }
    }

    /// Releases the display link while the view is out of a window.
    func detach() {
        displayLink = nil
    }

    public func displayLink(_: DisplayLink, didUpdate frame: DisplayLinkFrame) {
        step(at: frame.targetTimestamp)
    }

    /// Runs one refresh. Exposed for tests and for hosts that drive frames
    /// themselves.
    public func step(at time: Double) {
        guard let body, screen.size.width > 0, screen.size.height > 0 else {
            displayLink?.isPaused = true
            return
        }
        let hasInput = !pendingEvents.isEmpty
        guard frameScheduler.isDue(at: time, hasInput: hasInput) || needsPresent else {
            if !frameScheduler.hasPendingWake {
                displayLink?.isPaused = true
            }
            return
        }

        swap(&pendingEvents, &frameEvents)
        pendingEvents.removeAll(keepingCapacity: true)
        let result = ui.frame(time: time, size: screen.size, events: frameEvents, body)
        frameEvents.removeAll(keepingCapacity: true)
        framesBuilt += 1

        if result.changed {
            surface.render(ui.drawList)
            framesRasterized += 1
            needsPresent = true
            needsUpload = true
        }
        // Afterglow evolves even when the picture does not.
        if crt.isEnabled {
            needsPresent = true
        }
        if needsPresent, let presenter {
            let dt = lastPresentTime.map { min(max(time - $0, 0), 0.1) } ?? 1.0 / 60
            if presenter.present(surface, upload: needsUpload, palette: ui.palette, screen: screen, crt: crt, dt: dt, to: metalLayer) {
                needsPresent = false
                needsUpload = false
                lastPresentTime = time
                framesPresented += 1
            }
        }
        onTextInput?(result.textInput)
        let keepTicking = frameScheduler.didDraw(at: time, result: result) || needsPresent || !pendingEvents.isEmpty
        if !keepTicking {
            displayLink?.isPaused = true
        }
    }

    // MARK: - Geometry

    /// Sizes the drawable and the virtual screen for a view of `size`
    /// points at `scale` device pixels per point.
    func layout(size: CGSize, scale: Double) {
        pointSize = size
        pointScale = max(scale, 1)
        relayout()
    }

    private func relayout() {
        metalLayer.contentsScale = pointScale
        let deviceSize = CGSize(width: (pointSize.width * pointScale).rounded(), height: (pointSize.height * pointScale).rounded())
        if metalLayer.drawableSize != deviceSize, deviceSize.width > 0, deviceSize.height > 0 {
            metalLayer.drawableSize = deviceSize
        }
        let newScreen = SZScreen(resolution: resolution, deviceWidth: deviceSize.width, deviceHeight: deviceSize.height, deviceScale: pointScale)
        if newScreen != screen {
            screen = newScreen
            surface.resize(width: screen.size.width, height: screen.size.height)
            frameScheduler.invalidate()
        }
        needsPresent = true
        needsUpload = true
        wake()
    }

    /// The virtual pixel under a point in the view (top-left origin).
    public func virtualPoint(_ point: CGPoint) -> SZPoint {
        screen.virtualPoint(deviceX: point.x * pointScale, deviceY: point.y * pointScale)
    }

    /// The view rectangle (points, top-left origin) of a virtual rectangle.
    public func viewRect(for rect: SZRect) -> CGRect {
        CGRect(
            x: (screen.viewportX + Double(rect.x) * screen.scale) / pointScale,
            y: (screen.viewportY + Double(rect.y) * screen.scale) / pointScale,
            width: Double(rect.width) * screen.scale / pointScale,
            height: Double(rect.height) * screen.scale / pointScale,
        )
    }

    /// Wheel deltas in points, converted to virtual pixels.
    func wheel(at point: CGPoint, dx: Double, dy: Double) {
        let factor = pointScale / max(screen.scale, 1)
        send(.wheel(virtualPoint(point), dx: dx * factor, dy: dy * factor))
    }

    // MARK: - Accessibility

    /// What screen readers should see: everything at or above the modal
    /// layer of the last frame.
    var visibleAccessibilityItems: [SZAccessibilityItem] {
        let modal = ui.modalLayer
        return ui.accessibilityItems.filter { $0.layer >= modal }
    }

    /// Taps the center of `rect`, for accessibility activation.
    func tap(_ rect: SZRect) {
        let center = SZPoint(rect.x + rect.width / 2, rect.y + rect.height / 2)
        send(.pointerDown(center, kind: .touch))
        send(.pointerUp(center, kind: .touch))
    }

    /// Nudges an adjustable control with wheel steps.
    func adjust(_ rect: SZRect, by direction: Double) {
        let center = SZPoint(rect.x + rect.width / 2, rect.y + rect.height / 2)
        send(.wheel(center, dx: 6 * direction, dy: -6 * direction))
    }
}

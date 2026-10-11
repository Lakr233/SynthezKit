//
//  SZScroll.swift
//  SynthezWidgets
//

import Foundation
import SynthezCore

public struct SZScrollAxes: OptionSet, Hashable, Sendable {
    public let rawValue: UInt8
    public init(rawValue: UInt8) {
        self.rawValue = rawValue
    }

    public static let horizontal = SZScrollAxes(rawValue: 1)
    public static let vertical = SZScrollAxes(rawValue: 2)
    public static let both: SZScrollAxes = [.horizontal, .vertical]
}

/// What a scroll view's content sees.
public struct SZScroll: Sendable {
    /// The scroll position: content coordinates at the viewport's top-left.
    public var offset: SZPoint
    /// The visible part of the content, in content coordinates.
    public var visible: SZRect
    public var isDragging: Bool
    public var isMoving: Bool
}

/// Scroll state kept across frames.
private final class ScrollState {
    var x = 0.0, y = 0.0
    var vx = 0.0, vy = 0.0
    var content = SZSize.zero
    var dragging = false
    var startX = 0.0, startY = 0.0
    var target: (x: Double, y: Double)?
    var lastMotion = -Double.infinity
}

/// Rubber-band resistance past an edge: the further out, the harder.
private func rubberBand(_ overshoot: Double, dimension: Double) -> Double {
    let c = 0.55
    let sign = overshoot < 0 ? -1.0 : 1.0
    let x = abs(overshoot)
    return sign * (1 - 1 / (x * c / max(dimension, 1) + 1)) * dimension
}

/// Scrolls `body`'s content: drag with inertia and rubber-banding, wheel,
/// optional snapping, edge fades, and an indicator while moving.
///
/// The content's size is `content` if given, otherwise what the content
/// reached last frame. Content drawn outside the viewport is culled and
/// cannot be touched.
@discardableResult
public func scrollView<Result>(
    _ ctx: inout SZContext,
    axes: SZScrollAxes = .vertical,
    content: SZSize? = nil,
    snap: SZSize? = nil,
    fade: Int = 0,
    indicators: Bool = true,
    key: SZKey? = nil,
    in rect: SZRect? = nil,
    _ body: (inout SZContext, SZScroll) -> Result,
) -> Result {
    let theme = ctx.theme
    let id = ctx.makeKey(key)
    let frame = rect ?? ctx.place(SZSize(0, max(ctx.bounds.maxY - ctx.cursor.y, 0)))
    let state = ctx.state(id: id.part("scroll"), ScrollState()).value
    // Under the content, so controls inside take taps first.
    let it = ctx.interaction(frame, sense: [.wheel], id: id)

    let measured = content ?? state.content
    let maxX = axes.contains(.horizontal) ? Double(max(measured.width - frame.width, 0)) : 0
    let maxY = axes.contains(.vertical) ? Double(max(measured.height - frame.height, 0)) : 0
    let dt = ctx.dt
    let wasMoving = state.dragging || state.vx != 0 || state.vy != 0 || state.target != nil

    // Take the pointer once a drag inside us passes the slop along our axis.
    if !state.dragging, ctx.isPointerDown, ctx.canCapturePointer(id), let pointer = ctx.pointer {
        let origin = ctx.pressOrigin
        let inside = ctx.absolute(frame).intersection(ctx.clipRect).contains(ctx.absolute(origin))
        let dx = Double(pointer.x - origin.x), dy = Double(pointer.y - origin.y)
        let slop = 4.0
        let wantsX = axes.contains(.horizontal) && abs(dx) > slop && (axes.contains(.vertical) || abs(dx) > abs(dy))
        let wantsY = axes.contains(.vertical) && abs(dy) > slop && (axes.contains(.horizontal) || abs(dy) > abs(dx))
        // Like UIScrollView, a press during a fling only stops it: the
        // content under the finger moved, so it must not be tapped.
        let catchesFling = abs(state.vx) > 40 || abs(state.vy) > 40
        if inside, wantsX || wantsY || catchesFling {
            ctx.capturePointer(id)
            state.dragging = true
            state.startX = state.x
            state.startY = state.y
            state.vx = 0
            state.vy = 0
            state.target = nil
        }
    }

    // Read again without registering: capture may have happened just now,
    // and dx/dy then run from the capture point.
    let live = ctx.interaction(.zero, sense: [], id: id)
    if state.dragging, live.held {
        var nx = state.startX - Double(live.dx)
        var ny = state.startY - Double(live.dy)
        if nx < 0 {
            nx = rubberBand(nx, dimension: Double(frame.width))
        }
        if nx > maxX {
            nx = maxX + rubberBand(nx - maxX, dimension: Double(frame.width))
        }
        if ny < 0 {
            ny = rubberBand(ny, dimension: Double(frame.height))
        }
        if ny > maxY {
            ny = maxY + rubberBand(ny - maxY, dimension: Double(frame.height))
        }
        if axes.contains(.horizontal) {
            state.x = nx
        }
        if axes.contains(.vertical) {
            state.y = ny
        }
        state.lastMotion = ctx.time
    } else if state.dragging {
        // Released: fling.
        state.dragging = false
        let v = ctx.pointerVelocity
        state.vx = axes.contains(.horizontal) ? -v.x : 0
        state.vy = axes.contains(.vertical) ? -v.y : 0
        if let snap {
            // Land on the snap grid nearest to where the fling would stop.
            let tau = 0.325
            var tx = state.x + state.vx * tau
            var ty = state.y + state.vy * tau
            if snap.width > 0 {
                tx = (tx / Double(snap.width)).rounded() * Double(snap.width)
            }
            if snap.height > 0 {
                ty = (ty / Double(snap.height)).rounded() * Double(snap.height)
            }
            state.target = (min(max(tx, 0), maxX), min(max(ty, 0), maxY))
            state.vx = 0
            state.vy = 0
        }
        state.lastMotion = ctx.time
    } else {
        // Wheel.
        if it.wheelX != 0 || it.wheelY != 0 {
            let base = state.target ?? (state.x, state.y)
            var tx = min(max(base.0 + (axes.contains(.horizontal) ? it.wheelX : 0), 0), maxX)
            var ty = min(max(base.1 + (axes.contains(.vertical) ? it.wheelY : (axes == .horizontal ? it.wheelY : 0)), 0), maxY)
            if let snap, snap.width > 0 {
                tx = (tx / Double(snap.width)).rounded() * Double(snap.width)
            }
            if let snap, snap.height > 0 {
                ty = (ty / Double(snap.height)).rounded() * Double(snap.height)
            }
            state.target = (tx, ty)
            state.vx = 0
            state.vy = 0
        }
        // Inertia, then spring back inside the edges.
        if state.vx != 0 || state.vy != 0 {
            let decay = pow(0.998, dt * 1000)
            state.x += state.vx * dt
            state.y += state.vy * dt
            state.vx *= decay
            state.vy *= decay
            if state.x < 0 || state.x > maxX {
                state.vx *= pow(0.82, dt * 60)
            }
            if state.y < 0 || state.y > maxY {
                state.vy *= pow(0.82, dt * 60)
            }
            if abs(state.vx) < 8 {
                state.vx = 0
            }
            if abs(state.vy) < 8 {
                state.vy = 0
            }
            state.lastMotion = ctx.time
        }
        if state.vx == 0, state.vy == 0 {
            let goal = state.target ?? (min(max(state.x, 0), maxX), min(max(state.y, 0), maxY))
            let nx = SZEase.approach(state.x, to: goal.0, dt: dt, easing: 0.2, snap: 0.3)
            let ny = SZEase.approach(state.y, to: goal.1, dt: dt, easing: 0.2, snap: 0.3)
            if nx != state.x || ny != state.y {
                state.lastMotion = ctx.time
            }
            state.x = nx
            state.y = ny
            if let target = state.target, target.0 == nx, target.1 == ny {
                state.target = nil
            }
        }
    }
    let isMoving = state.dragging || state.vx != 0 || state.vy != 0 || state.target != nil
        || state.x < 0 || state.x > maxX || state.y < 0 || state.y > maxY
    if isMoving || wasMoving {
        ctx.requestFrame()
    }

    let ox = Int(state.x.rounded()), oy = Int(state.y.rounded())
    let contentWidth = axes.contains(.horizontal) ? max(measured.width, frame.width) : frame.width
    let contentHeight = axes.contains(.vertical) ? max(measured.height, frame.height) : frame.height
    let info = SZScroll(
        offset: SZPoint(ox, oy),
        visible: SZRect(ox, oy, frame.width, frame.height),
        isDragging: state.dragging,
        isMoving: isMoving,
    )

    var reached = SZSize.zero
    let result = ctx.region(frame, clip: true, key: .id(id.part("view"))) { view -> Result in
        let unbounded = Int(Int16.max)
        let inner = SZRect(-ox, -oy, axes.contains(.horizontal) && content == nil ? unbounded : contentWidth, axes.contains(.vertical) && content == nil ? unbounded : contentHeight)
        let result = view.region(inner, key: .id(id.part("content")), reserve: false) { c -> Result in
            if content == nil {
                // Lay out in the viewport's width (or height) on the fixed axis.
                if !axes.contains(.horizontal) {
                    c.bounds.width = frame.width
                }
                if !axes.contains(.vertical) {
                    c.bounds.height = frame.height
                }
            }
            let r = body(&c, info)
            reached = SZSize(c.reach.x, c.reach.y)
            return r
        }

        // Fade the edges by how much content lies beyond them.
        if fade > 0 {
            func edge(_ band: SZRect, _ side: SZEdge, _ beyond: Double) {
                let s = min(max(beyond / Double(fade), 0), 1)
                guard s > 0 else { return }
                view.filter(band, field: view.ramp(band, toward: side, strength: s), toward: theme.background)
            }
            if axes.contains(.vertical) {
                edge(SZRect(0, 0, frame.width, fade), .top, state.y)
                edge(SZRect(0, frame.height - fade, frame.width, fade), .bottom, maxY - state.y)
            }
            if axes.contains(.horizontal) {
                edge(SZRect(0, 0, fade, frame.height), .left, state.x)
                edge(SZRect(frame.width - fade, 0, fade, frame.height), .right, maxX - state.x)
            }
        }

        // Indicators show while moving and dissolve after.
        if indicators {
            let age = view.time - state.lastMotion
            let visibility = isMoving ? 1 : max(0, 1 - (age - 0.6) / 0.3)
            if visibility > 0 {
                if !isMoving {
                    view.requestFrame()
                }
                let pattern = SZPatterns.shade(visibility)
                if axes.contains(.vertical), maxY > 0 {
                    let length = max(frame.height * frame.height / max(contentHeight, 1), 8)
                    let travel = Double(frame.height - length - 2)
                    let pos = Int((min(max(state.y / maxY, 0), 1) * travel).rounded())
                    view.fill(SZRect(frame.width - 3, 1 + pos, 2, length), color: theme.textDim, pattern: pattern)
                }
                if axes.contains(.horizontal), maxX > 0 {
                    let length = max(frame.width * frame.width / max(contentWidth, 1), 8)
                    let travel = Double(frame.width - length - 2)
                    let pos = Int((min(max(state.x / maxX, 0), 1) * travel).rounded())
                    view.fill(SZRect(1 + pos, frame.height - 3, length, 2), color: theme.textDim, pattern: pattern)
                }
            }
        }
        return result
    }

    if content == nil, reached != state.content {
        state.content = reached
        ctx.requestFrame()
    }
    return result
}

// MARK: - List

/// What a list row is doing.
public struct SZListRow: Sendable {
    public var index: Int
    /// The row's rectangle, in the list content's coordinates.
    public var rect: SZRect
    public var selected: Bool
    public var interaction: SZInteraction
}

/// A virtual list: only visible rows are built, so 10,000 rows cost as much
/// as a screenful. Returns the index tapped this frame.
@discardableResult
public func list(
    _ ctx: inout SZContext,
    count: Int,
    rowHeight: Int,
    selected: Int?,
    separators: Bool = true,
    fade: Int = 12,
    key: SZKey? = nil,
    in rect: SZRect? = nil,
    row: (inout SZContext, SZListRow) -> Void,
) -> Int? {
    let theme = ctx.theme
    let id = ctx.makeKey(key)
    let frame = rect ?? ctx.place(SZSize(0, max(ctx.bounds.maxY - ctx.cursor.y, 0)))
    ctx.fill(frame, color: theme.background)
    ctx.stroke(frame, color: theme.line)
    let inner = frame.inset(by: 1)
    return scrollView(&ctx, axes: .vertical, content: SZSize(inner.width, count * rowHeight), fade: fade, key: .id(id.part("scroll")), in: inner) { c, scroll -> Int? in
        let first = max(scroll.visible.minY / rowHeight, 0)
        let last = min((scroll.visible.maxY + rowHeight - 1) / rowHeight, count)
        var tapped: Int?
        guard first < last else { return nil }
        for index in first ..< last {
            let r = SZRect(0, index * rowHeight, inner.width, rowHeight)
            let rowID = id.child(8, UInt32(truncatingIfNeeded: index))
            let it = c.interaction(r, id: rowID)
            if it.clicked {
                tapped = index
            }
            let isSelected = index == selected
            if isSelected {
                c.fill(r, color: theme.accentDim)
            } else if it.held {
                c.fill(r, color: theme.lineStrong)
            } else if it.hovered || c.containsPointer(r) && c.ui.pointerKind == .mouse {
                c.fill(r, color: theme.panel)
            }
            if separators, !isSelected {
                c.fill(SZRect(r.x + 4, r.maxY - 1, r.width - 8, 1), color: theme.line, pattern: SZPatterns.half)
            }
            c.region(r, key: .id(rowID.part("row"))) { cell in
                row(&cell, SZListRow(index: index, rect: SZRect(0, 0, r.width, r.height), selected: isSelected, interaction: it))
            }
            c.accessibility(r, label: "ROW \(index)", traits: isSelected ? [.button, .selected] : .button, id: rowID)
        }
        return tapped
    }
}

//
//  SZContext.swift
//  SynthezCore
//

/// A region of the screen during one frame: where to lay out, what to clip
/// to, which layer to draw on, and the identity its children derive from.
///
/// A context is a value passed `inout` to closures, so opening a row or a
/// clip costs no allocation. Coordinates are local: ``bounds`` starts at
/// (0, 0) for a fresh region and shrinks as edges are cut off.
///
/// ```swift
/// ui.frame(time: t, size: size, events: events) { ctx in
///     ctx.fill(ctx.bounds, color: 0)
///     ctx.inset(8)
///     ctx.row(height: 11, gap: 3) { row in
///         if button(&row, "-").clicked { count -= 1 }
///         label(&row, "\(count)")
///         if button(&row, "+").clicked { count += 1 }
///     }
/// }
/// ```
///
/// Identity follows call order within a region: the third ``interaction``
/// of a region gets the same ``SZID`` every frame. Pass an ``SZKey`` where
/// order can change, such as rows of a list.
public struct SZContext {
    // The UI and list outlive every frame's contexts; skipping the retain
    // keeps a copied context free.
    public unowned(unsafe) let ui: SZUI
    unowned(unsafe) let list: SZDrawList

    public let id: SZID
    /// The absolute position of local (0, 0).
    public let origin: SZPoint
    /// The space still free, in local coordinates.
    public var bounds: SZRect
    /// Where the next ``place(_:)`` goes, in local coordinates.
    public var cursor: SZPoint
    public var flow = SZAxis.vertical
    public var gap = 0
    public var align = SZAlignment.start
    /// The absolute clip rectangle.
    public let clipRect: SZRect
    let clipIndex: UInt16
    public let layer: Int
    /// The farthest point anything was placed or cut up to, in local
    /// coordinates: a region's natural size.
    public private(set) var reach = SZPoint.zero

    private var placedCount = 0
    private var regionCounter: UInt32 = 0
    private var interactionCounter: UInt32 = 0
    private var stateCounter: UInt32 = 0
    private var animationCounter: UInt32 = 0
    private var keyCounter: UInt32 = 0

    init(ui: SZUI, list: SZDrawList, id: SZID, origin: SZPoint, bounds: SZRect, clipRect: SZRect, clipIndex: UInt16, layer: Int) {
        self.ui = ui
        self.list = list
        self.id = id
        self.origin = origin
        self.bounds = bounds
        cursor = bounds.origin
        self.clipRect = clipRect
        self.clipIndex = clipIndex
        self.layer = layer
    }

    // MARK: - Frame info

    public var time: Double {
        ui.time
    }

    public var dt: Double {
        ui.dt
    }

    public var palette: SZPalette {
        ui.palette
    }

    public func requestFrame() {
        ui.requestFrame()
    }

    public func requestFrame(at time: Double) {
        ui.requestFrame(at: time)
    }

    @inline(__always)
    public func absolute(_ rect: SZRect) -> SZRect {
        rect.offsetBy(origin.x, origin.y)
    }

    @inline(__always)
    public func absolute(_ p: SZPoint) -> SZPoint {
        p + origin
    }

    // MARK: - Identity and state

    /// An ID for a widget: `key`'s if given, the next position otherwise.
    /// Widgets call this once and name their parts with ``SZID/part(_:)``.
    public mutating func makeKey(_ key: SZKey? = nil) -> SZID {
        if let key {
            return key.id
        }
        defer { keyCounter += 1 }
        return id.child(1, keyCounter)
    }

    /// State kept as long as this call happens every frame.
    public mutating func state<Value>(key: SZKey? = nil, _ initial: @autoclosure () -> Value) -> SZState<Value> {
        let stateID: SZID
        if let key {
            stateID = key.id
        } else {
            stateID = id.child(2, stateCounter); stateCounter += 1
        }
        return ui.state(stateID, initial)
    }

    public func state<Value>(id: SZID, _ initial: @autoclosure () -> Value) -> SZState<Value> {
        ui.state(id, initial)
    }

    /// `target`, reached smoothly: the value eases toward it frame by frame
    /// and the host keeps drawing until it arrives.
    public mutating func animatedValue(_ target: Double, key: SZKey? = nil, easing: Double = 0.15, snap: Double = 0.5, from: Double? = nil) -> Double {
        let animationID: SZID
        if let key {
            animationID = key.id
        } else {
            animationID = id.child(3, animationCounter); animationCounter += 1
        }
        return ui.animatedValue(animationID, target: target, easing: easing, snap: snap, from: from)
    }

    public func animatedValue(_ target: Double, id: SZID, easing: Double = 0.15, snap: Double = 0.5, from: Double? = nil) -> Double {
        ui.animatedValue(id, target: target, easing: easing, snap: snap, from: from)
    }

    // MARK: - Input

    /// Registers `rect` (local) for input and returns what happened to it.
    public mutating func interaction(_ rect: SZRect, sense: SZSense = .button, key: SZKey? = nil) -> SZInteraction {
        let interactionID: SZID
        if let key {
            interactionID = key.id
        } else {
            interactionID = id.child(4, interactionCounter); interactionCounter += 1
        }
        return interaction(rect, sense: sense, id: interactionID)
    }

    public func interaction(_ rect: SZRect, sense: SZSense = .button, id: SZID) -> SZInteraction {
        ui.interaction(for: id, rect: absolute(rect).intersection(clipRect), sense: sense, layer: layer)
    }

    /// Whether the pointer is inside `rect` (local) and no higher layer
    /// covers it, ignoring rectangles on this layer.
    public func containsPointer(_ rect: SZRect) -> Bool {
        guard let p = ui.pointer, absolute(rect).intersection(clipRect).contains(p) else { return false }
        return !ui.isCovered(p, above: layer)
    }

    // MARK: - Layout

    /// Takes `size` at the cursor along ``flow`` and advances past it.
    /// A zero cross-axis size, or ``SZAlignment/stretch``, spans the region.
    @discardableResult
    public mutating func place(_ size: SZSize) -> SZRect {
        let gap = placedCount > 0 ? gap : 0
        placedCount += 1
        let rect: SZRect
        switch flow {
        case .vertical:
            let width = size.width == 0 || align == .stretch ? bounds.width : size.width
            let y = cursor.y + gap
            let x = switch align {
            case .start, .stretch: bounds.x
            case .center: bounds.x + (bounds.width - width) / 2
            case .end: bounds.maxX - width
            }
            rect = SZRect(x, y, width, size.height)
            cursor.y = rect.maxY
        case .horizontal:
            let height = size.height == 0 || align == .stretch ? bounds.height : size.height
            let x = cursor.x + gap
            let y = switch align {
            case .start, .stretch: bounds.y
            case .center: bounds.y + (bounds.height - height) / 2
            case .end: bounds.maxY - height
            }
            rect = SZRect(x, y, size.width, height)
            cursor.x = rect.maxX
        }
        extend(to: rect)
        return rect
    }

    @discardableResult
    public mutating func place(width: Int, height: Int) -> SZRect {
        place(SZSize(width, height))
    }

    /// Leaves `amount` empty pixels along ``flow``.
    public mutating func space(_ amount: Int) {
        switch flow {
        case .vertical: cursor.y += amount
        case .horizontal: cursor.x += amount
        }
    }

    public mutating func inset(top: Int, right: Int, bottom: Int, left: Int) {
        bounds = bounds.inset(top: top, right: right, bottom: bottom, left: left)
        clampCursor()
    }

    public mutating func inset(_ amount: Int) {
        inset(top: amount, right: amount, bottom: amount, left: amount)
    }

    /// Cuts a strip `size` tall off the top of ``bounds`` and returns it.
    public mutating func cutTop(_ size: Int, gap: Int = 0) -> SZRect {
        let size = min(max(size, 0), bounds.height)
        let rect = SZRect(bounds.x, bounds.y, bounds.width, size)
        bounds = bounds.inset(top: min(size + gap, bounds.height), right: 0, bottom: 0, left: 0)
        clampCursor()
        extend(to: rect)
        return rect
    }

    public mutating func cutBottom(_ size: Int, gap: Int = 0) -> SZRect {
        let size = min(max(size, 0), bounds.height)
        let rect = SZRect(bounds.x, bounds.maxY - size, bounds.width, size)
        bounds = bounds.inset(top: 0, right: 0, bottom: min(size + gap, bounds.height), left: 0)
        extend(to: rect)
        return rect
    }

    public mutating func cutLeft(_ size: Int, gap: Int = 0) -> SZRect {
        let size = min(max(size, 0), bounds.width)
        let rect = SZRect(bounds.x, bounds.y, size, bounds.height)
        bounds = bounds.inset(top: 0, right: 0, bottom: 0, left: min(size + gap, bounds.width))
        clampCursor()
        extend(to: rect)
        return rect
    }

    public mutating func cutRight(_ size: Int, gap: Int = 0) -> SZRect {
        let size = min(max(size, 0), bounds.width)
        let rect = SZRect(bounds.maxX - size, bounds.y, size, bounds.height)
        bounds = bounds.inset(top: 0, right: min(size + gap, bounds.width), bottom: 0, left: 0)
        extend(to: rect)
        return rect
    }

    private mutating func clampCursor() {
        cursor.x = max(cursor.x, bounds.x)
        cursor.y = max(cursor.y, bounds.y)
    }

    private mutating func extend(to rect: SZRect) {
        reach.x = max(reach.x, rect.maxX)
        reach.y = max(reach.y, rect.maxY)
    }

    // MARK: - Regions

    /// Runs `body` in a child region covering `rect` (local). The child's
    /// coordinates start at (0, 0).
    ///
    /// - Parameter reserve: Whether `rect` counts toward this region's
    ///   ``reach``. Pass false for a region sized only to measure its content.
    @discardableResult
    public mutating func region<Result>(
        _ rect: SZRect,
        clip: Bool = false,
        key: SZKey? = nil,
        reserve: Bool = true,
        _ body: (inout SZContext) throws -> Result,
    ) rethrows -> Result {
        if reserve {
            extend(to: rect)
        }
        var child = makeChild(rect, clip: clip, key: key, layer: layer)
        return try body(&child)
    }

    /// Runs `body` on the layer above, over the whole screen's clip, in this
    /// region's coordinates: menus and sheets escape scroll views this way.
    ///
    /// - Parameter levels: How many layers up; tooltips go far above
    ///   everything else.
    @discardableResult
    public mutating func overlay<Result>(above levels: Int = 1, key: SZKey? = nil, _ body: (inout SZContext) throws -> Result) rethrows -> Result {
        let childID = key?.id ?? id.child(5, nextRegion())
        var child = SZContext(ui: ui, list: list, id: childID, origin: origin, bounds: bounds, clipRect: ui.screen, clipIndex: 0, layer: layer + max(levels, 1))
        child.cursor = cursor
        return try body(&child)
    }

    /// Clips `body`'s drawing and input to `rect` (local), in this region's
    /// coordinates.
    @discardableResult
    public mutating func clip<Result>(_ rect: SZRect, _ body: (inout SZContext) throws -> Result) rethrows -> Result {
        let clip = absolute(rect).intersection(clipRect)
        var child = SZContext(ui: ui, list: list, id: id.child(6, nextRegion()), origin: origin, bounds: rect, clipRect: clip, clipIndex: list.addClip(clip), layer: layer)
        let result = try body(&child)
        extend(to: rect)
        return result
    }

    /// A row from the cursor to the far edge: children flow left to right,
    /// and this region advances by what they used (or `width`/`height`).
    @discardableResult
    public mutating func row<Result>(
        width: Int? = nil,
        height: Int? = nil,
        gap: Int = 0,
        align: SZAlignment = .start,
        key: SZKey? = nil,
        _ body: (inout SZContext) throws -> Result,
    ) rethrows -> Result {
        try stack(.horizontal, width: width, height: height, gap: gap, align: align, key: key, body)
    }

    /// A column from the cursor to the far edge: children flow top to
    /// bottom, and this region advances by what they used.
    @discardableResult
    public mutating func column<Result>(
        width: Int? = nil,
        height: Int? = nil,
        gap: Int = 0,
        align: SZAlignment = .start,
        key: SZKey? = nil,
        _ body: (inout SZContext) throws -> Result,
    ) rethrows -> Result {
        try stack(.vertical, width: width, height: height, gap: gap, align: align, key: key, body)
    }

    private mutating func stack<Result>(
        _ axis: SZAxis,
        width: Int?,
        height: Int?,
        gap: Int,
        align: SZAlignment,
        key: SZKey?,
        _ body: (inout SZContext) throws -> Result,
    ) rethrows -> Result {
        let leading = placedCount > 0 ? self.gap : 0
        let available = switch flow {
        case .vertical:
            SZRect(bounds.x, cursor.y + leading, width ?? bounds.width, height ?? max(bounds.maxY - cursor.y - leading, 0))
        case .horizontal:
            SZRect(cursor.x + leading, bounds.y, width ?? max(bounds.maxX - cursor.x - leading, 0), height ?? bounds.height)
        }
        var child = makeChild(available, clip: false, key: key, layer: layer)
        child.flow = axis
        child.gap = gap
        child.align = align
        let result = try body(&child)
        let used = SZSize(width ?? child.reach.x, height ?? child.reach.y)
        // Advance as if the child had been placed at its natural size.
        placedCount += 1
        let rect = SZRect(available.x, available.y, used.width, used.height)
        switch flow {
        case .vertical: cursor.y = rect.maxY
        case .horizontal: cursor.x = rect.maxX
        }
        extend(to: rect)
        return result
    }

    private mutating func nextRegion() -> UInt32 {
        defer { regionCounter += 1 }
        return regionCounter
    }

    private mutating func makeChild(_ rect: SZRect, clip: Bool, key: SZKey?, layer: Int) -> SZContext {
        let childID = key?.id ?? id.child(0, nextRegion())
        let abs = absolute(rect)
        let childClip = clip ? abs.intersection(clipRect) : clipRect
        let index = clip ? list.addClip(childClip) : clipIndex
        return SZContext(ui: ui, list: list, id: childID, origin: abs.origin, bounds: SZRect(0, 0, rect.width, rect.height), clipRect: childClip, clipIndex: index, layer: layer)
    }

    // MARK: - Drawing

    @inline(__always)
    private func isVisible(_ abs: SZRect) -> Bool {
        abs.maxX > clipRect.minX && abs.minX < clipRect.maxX && abs.maxY > clipRect.minY && abs.minY < clipRect.maxY
    }

    public func fill(_ rect: SZRect, color: SZColor, pattern: SZPattern = SZPatterns.solid) {
        let abs = absolute(rect)
        guard !abs.isEmpty, pattern != 0, isVisible(abs) else { return }
        list.append(.fill(abs, color, pattern), clip: clipIndex, layer: layer)
    }

    public func stroke(_ rect: SZRect, color: SZColor) {
        let abs = absolute(rect)
        guard !abs.isEmpty, isVisible(abs) else { return }
        list.append(.stroke(abs, color), clip: clipIndex, layer: layer)
    }

    public func line(from a: SZPoint, to b: SZPoint, color: SZColor) {
        list.append(.line(absolute(a), absolute(b), color), clip: clipIndex, layer: layer)
    }

    public func pixel(_ p: SZPoint, color: SZColor) {
        let abs = absolute(p)
        guard clipRect.contains(abs) else { return }
        list.append(.pixel(abs, color), clip: clipIndex, layer: layer)
    }

    public func circle(center: SZPoint, radius: Int, color: SZColor, filled: Bool = true) {
        let c = absolute(center)
        guard isVisible(SZRect(c.x - radius, c.y - radius, radius * 2 + 1, radius * 2 + 1)) else { return }
        list.append(.circle(center: c, radius: radius, color, filled: filled), clip: clipIndex, layer: layer)
    }

    public func bitmap(_ bitmap: SZBitmap, at p: SZPoint, color: SZColor, scale: Int = 1) {
        let abs = absolute(p)
        guard isVisible(SZRect(abs.x, abs.y, bitmap.width * scale, bitmap.height * scale)) else { return }
        list.append(.bitmap(bitmap, abs, color, scale: scale), clip: clipIndex, layer: layer)
    }

    /// Draws one line of text with its top-left at `p` and returns its width.
    @discardableResult
    public func text(_ text: some StringProtocol, at p: SZPoint, font: SZBitmapFont, color: SZColor, scale: Int = 1) -> Int {
        let abs = absolute(p)
        let height = font.glyphHeight * scale
        guard abs.y < clipRect.maxY, abs.y + height > clipRect.minY, abs.x < clipRect.maxX else {
            return font.measure(text) * scale
        }
        return list.appendText(text, font: font, at: abs, color: color, scale: scale, clip: clipIndex, layer: layer)
    }

    /// Maps what is already drawn in `rect` through `map`.
    public func remap(_ rect: SZRect, map: SZColorMap, pattern: SZPattern = SZPatterns.solid) {
        let abs = absolute(rect)
        guard !abs.isEmpty, isVisible(abs) else { return }
        list.append(.remap(abs, map, pattern), clip: clipIndex, layer: layer)
    }

    public func mosaic(_ rect: SZRect, size: Int) {
        let abs = absolute(rect)
        guard size > 1, !abs.isEmpty, isVisible(abs) else { return }
        list.append(.mosaic(abs, size: size), clip: clipIndex, layer: layer)
    }
}

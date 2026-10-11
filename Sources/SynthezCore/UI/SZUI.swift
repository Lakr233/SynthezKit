//
//  SZUI.swift
//  SynthezCore
//

/// What one frame produced, for the host.
public struct SZFrameResult: Sendable {
    /// Something is moving or asked for another frame.
    public var needsAnotherFrame: Bool
    /// The draw list differs from the previous frame's, so the surface must
    /// be rasterized and presented again.
    public var changed: Bool
    /// A focused text widget wants the keyboard.
    public var textInput: SZTextInputRequest?
    /// Draw again at this time even if nothing else happens (caret blink).
    public var wakeAt: Double?

    public init(needsAnotherFrame: Bool, changed: Bool, textInput: SZTextInputRequest? = nil, wakeAt: Double? = nil) {
        self.needsAnotherFrame = needsAnotherFrame
        self.changed = changed
        self.textInput = textInput
        self.wakeAt = wakeAt
    }
}

/// A boxed piece of state that lives as long as the call that owns it keeps
/// being made. It is a class so a widget can mutate it in place.
public final class SZState<Value> {
    public var value: Value

    init(_ value: Value) {
        self.value = value
    }
}

/// A value read from ``SZUI/environment(_:)``.
public protocol SZEnvironmentKey {
    associatedtype Value
    static var defaultValue: Value { get }
}

/// Everything that lives across frames: time, pointer, focus, state and the
/// previous frame's interactive rectangles.
///
/// Call ``frame(time:size:events:_:)`` once per display refresh that needs
/// drawing. Widgets talk to the UI through the ``SZContext`` the body gets.
public final class SZUI {
    public private(set) var frameNumber: UInt64 = 0
    /// Seconds, on the clock the host passes in (`targetTimestamp`).
    public private(set) var time: Double = 0
    /// Seconds since the previous frame, at most 0.1.
    public private(set) var dt: Double = 1.0 / 60
    public private(set) var screen = SZRect.zero
    public var palette: SZPalette
    public var background: SZColor

    /// The list the current (or last finished) frame drew into.
    public private(set) var drawList = SZDrawList()
    private var previousList = SZDrawList()

    // Pointer.
    public private(set) var pointer: SZPoint?
    public private(set) var pointerKind = SZPointerKind.touch
    public private(set) var isPointerDown = false
    /// Where the current press started.
    public private(set) var pressOrigin = SZPoint.zero
    /// Pointer velocity in virtual pixels per second, measured over the last
    /// moments of the drag; kept after release for flings.
    public private(set) var pointerVelocity = (x: 0.0, y: 0.0)
    private var dragOrigin = SZPoint.zero
    private var pressTime = 0.0
    private var samples: [(time: Double, point: SZPoint)] = []
    var active: SZID?
    var activeSense: SZSense = []
    var focus: SZID?
    var hoverTarget: SZID?
    var pressedID: SZID?
    var releasedID: SZID?
    var clickedID: SZID?
    var pressCount = 0
    private var lastPressTime = -Double.infinity
    private var lastPressPoint = SZPoint.zero
    var wheelTargets: [(id: SZID, dx: Double, dy: Double)] = []

    /// Taps closer together than this, in seconds and virtual pixels, count up ``SZInteraction/presses``.
    public var multiPressInterval: Double = 0.4
    public var multiPressDistance = 8

    // Keyboard.
    private(set) var keyEvents: [(event: SZInputEvent, consumed: Bool)] = []
    var textInput: SZTextInputRequest?

    // Hints: what the pointer is on, for status lines and tooltips.
    public private(set) var hint: String?
    public private(set) var hintAnchor = SZRect.zero
    private var hintOwner: SZID?
    private var hintSince = 0.0
    private var pendingHint: (id: SZID, text: String, rect: SZRect)?

    // Accessibility.
    public private(set) var accessibilityItems: [SZAccessibilityItem] = []
    private var collectingAccessibility: [SZAccessibilityItem] = []
    /// The lowest layer screen readers see; modal overlays raise it.
    public private(set) var modalLayer = 0
    var pendingModalLayer = 0

    // Routing.
    var hits: [SZHit] = []
    private var previousHits: [SZHit] = []

    /// State.
    private struct StateEntry {
        var frame: UInt64
        let box: AnyObject
    }

    struct AnimationEntry {
        var frame: UInt64
        var value: Double
    }

    private var states: [SZID: StateEntry] = [:]
    var animations: [SZID: AnimationEntry] = [:]
    private var touchedStates = 0
    var touchedAnimations = 0
    private var environmentValues: [ObjectIdentifier: Any] = [:]
    /// Wrapped text, kept while it is drawn.
    public let textLayouts = SZTextLayoutCache()

    var wantsFrame = false
    /// The previous frame asked for another, so time since it is motion time.
    private var wasAnimating = false
    var wakeAt: Double?
    public private(set) var isInFrame = false

    public init(palette: SZPalette, background: SZColor = 0) {
        self.palette = palette
        self.background = background
    }

    // MARK: - Frame

    /// Runs `body` for one frame and records what it draws into ``drawList``.
    @discardableResult
    public func frame(time: Double, size: SZSize, events: [SZInputEvent], _ body: (inout SZContext) -> Void) -> SZFrameResult {
        precondition(!isInFrame, "SZUI.frame is not reentrant")
        isInFrame = true
        defer { isInFrame = false }

        frameNumber &+= 1
        // After an idle stretch the gap since the last frame is not motion
        // time: an animation starting now must begin from its first step.
        dt = frameNumber == 1 || !wasAnimating ? 1.0 / 60 : min(max(time - self.time, 0), 0.1)
        self.time = time
        screen = SZRect(0, 0, size.width, size.height)
        wantsFrame = false
        wakeAt = nil
        touchedStates = 0
        touchedAnimations = 0
        textInput = nil
        pendingHint = nil
        pendingModalLayer = 0
        collectingAccessibility.removeAll(keepingCapacity: true)

        swap(&hits, &previousHits)
        hits.removeAll(keepingCapacity: true)
        take(events)

        swap(&drawList, &previousList)
        drawList.begin(screen: screen, background: background)
        var root = SZContext(ui: self, list: drawList, id: .root, origin: .zero, bounds: screen, clipRect: screen, clipIndex: 0, layer: 0)
        body(&root)

        finish()
        wasAnimating = wantsFrame
        // Input handled this frame may have changed state the widgets drew
        // before reacting to it; one more frame shows the result.
        return SZFrameResult(
            needsAnotherFrame: wantsFrame || appliedEvents > 0 || !deferredEvents.isEmpty || isPointerDown && active != nil,
            changed: frameNumber == 1 || !drawList.isEqual(to: previousList),
            textInput: textInput,
            wakeAt: wakeAt,
        )
    }

    /// Asks the host for another frame after this one, for animations that
    /// do not go through ``SZContext/animatedValue(_:key:easing:snap:from:)``.
    public func requestFrame() {
        wantsFrame = true
    }

    /// Asks for a frame at `time`, without frames before it.
    public func requestFrame(at time: Double) {
        wakeAt = min(wakeAt ?? time, time)
    }

    private func finish() {
        if let id = active, !hits.contains(where: { $0.id == id }) {
            active = nil
        }
        if let id = focus, !hits.contains(where: { $0.id == id }) {
            focus = nil
        }
        if !isPointerDown, pointerKind == .touch {
            pointer = nil
        }
        pressedID = nil
        releasedID = nil
        clickedID = nil
        wheelTargets.removeAll(keepingCapacity: true)
        keyEvents.removeAll(keepingCapacity: true)

        if let pending = pendingHint {
            if hintOwner != pending.id {
                hintOwner = pending.id
                hintSince = time
            }
            hint = pending.text
            hintAnchor = pending.rect
        } else {
            hint = nil
            hintOwner = nil
        }
        modalLayer = pendingModalLayer
        swap(&accessibilityItems, &collectingAccessibility)

        // Sweep only when something was skipped this frame.
        if touchedStates < states.count {
            let frame = frameNumber
            states = states.filter { $0.value.frame == frame }
        }
        if touchedAnimations < animations.count {
            let frame = frameNumber
            animations = animations.filter { $0.value.frame == frame }
        }
        textLayouts.endFrame(frameNumber)
    }

    // MARK: - Input

    /// Events held back for the next frame.
    private var deferredEvents: [SZInputEvent] = []
    /// Events applied this frame, from the caller or from the deferred queue.
    private var appliedEvents = 0

    /// Takes this frame's events, trickling them like Dear ImGui: a press
    /// and its release never take effect in the same frame. A whole tap or
    /// flick can arrive between two frames (a hitch, or the first frame
    /// after the link wakes); without trickling, widgets would never see the
    /// pointer down, so buttons would skip their pressed look and scroll
    /// views could not take a drag over. The rest waits for the next frame.
    private func take(_ incoming: [SZInputEvent]) {
        appliedEvents = 0
        var events = deferredEvents
        deferredEvents.removeAll(keepingCapacity: true)
        events.append(contentsOf: incoming)
        var wentDown = false, wentUp = false
        for (index, event) in events.enumerated() {
            switch event {
            case .pointerDown:
                if wentDown || wentUp {
                    deferredEvents.append(contentsOf: events[index...]); break
                }
                wentDown = true
            case .pointerUp, .pointerCancel:
                if wentDown || wentUp {
                    deferredEvents.append(contentsOf: events[index...]); break
                }
                wentUp = true
            default:
                break
            }
            if !deferredEvents.isEmpty {
                break
            }
            apply(event)
            appliedEvents += 1
        }
        if isPointerDown {
            pointerVelocity = measureVelocity()
        }
        hoverTarget = pointer.flatMap { hitTest($0, sense: []) }
    }

    /// Whether events wait for the next frame.
    public var hasDeferredInput: Bool {
        !deferredEvents.isEmpty
    }

    private func apply(_ event: SZInputEvent) {
        switch event {
        case let .pointerDown(p, kind):
            pointer = p
            pointerKind = kind
            isPointerDown = true
            pressOrigin = p
            dragOrigin = p
            pressTime = time
            samples.removeAll(keepingCapacity: true)
            samples.append((time, p))
            pointerVelocity = (0, 0)
            let target = hitTest(p, sense: .click)
            active = target
            activeSense = target.flatMap { id in previousHits.last { $0.id == id }?.sense } ?? []
            pressedID = target
            if target != nil {
                let isRepeat = time - lastPressTime <= multiPressInterval
                    && abs(p.x - lastPressPoint.x) <= multiPressDistance
                    && abs(p.y - lastPressPoint.y) <= multiPressDistance
                pressCount = isRepeat ? pressCount + 1 : 1
                lastPressTime = time
                lastPressPoint = p
            }
            focus = hitTest(p, sense: .focus)
        case let .pointerMove(p, kind):
            pointer = p
            pointerKind = kind
            if isPointerDown {
                addSample(p)
            }
        case let .pointerUp(p, kind):
            pointer = p
            pointerKind = kind
            addSample(p)
            pointerVelocity = measureVelocity()
            isPointerDown = false
            if let id = active {
                releasedID = id
                if activeSense.contains(.drag) || hitTest(p, sense: .click) == id {
                    clickedID = id
                }
            }
            active = nil
        case .pointerCancel:
            isPointerDown = false
            if let id = active {
                releasedID = id
            }
            active = nil
            pointerVelocity = (0, 0)
            if pointerKind == .touch {
                pointer = nil
            }
        case .pointerExit:
            if !isPointerDown {
                pointer = nil
            }
        case let .wheel(p, dx, dy):
            pointer = p
            guard let id = hitTest(p, sense: .wheel) else { break }
            if let i = wheelTargets.firstIndex(where: { $0.id == id }) {
                wheelTargets[i].dx += dx
                wheelTargets[i].dy += dy
            } else {
                wheelTargets.append((id, dx, dy))
            }
        case .key, .text:
            keyEvents.append((event, false))
        }
    }

    private func addSample(_ p: SZPoint) {
        if samples.count >= 8 {
            samples.removeFirst()
        }
        samples.append((time, p))
    }

    /// Velocity over the samples of the last 0.1 s.
    private func measureVelocity() -> (x: Double, y: Double) {
        guard let last = samples.last else { return (0, 0) }
        guard let first = samples.first(where: { last.time - $0.time <= 0.1 }), last.time > first.time else {
            return time - last.time > 0.05 ? (0, 0) : pointerVelocity
        }
        // A finger that stopped before lifting should not fling.
        if time - last.time > 0.05 {
            return (0, 0)
        }
        let dt = last.time - first.time
        return (Double(last.point.x - first.point.x) / dt, Double(last.point.y - first.point.y) / dt)
    }

    /// The topmost rectangle of the previous frame under `p` that has
    /// `sense` (any rectangle if `sense` is empty).
    ///
    /// The highest layer with any rectangle under `p` wins outright, so an
    /// overlay blocks everything beneath where it registered input; within
    /// a layer, later rectangles are on top.
    func hitTest(_ p: SZPoint, sense: SZSense) -> SZID? {
        var topLayer = -1
        for hit in previousHits where hit.layer > topLayer && hit.rect.contains(p) {
            topLayer = hit.layer
        }
        guard topLayer >= 0 else { return nil }
        for hit in previousHits.reversed() where hit.layer == topLayer && hit.rect.contains(p) {
            if sense.isEmpty || !hit.sense.isDisjoint(with: sense) {
                return hit.id
            }
        }
        return nil
    }

    func interaction(for id: SZID, rect: SZRect, sense: SZSense, layer: Int) -> SZInteraction {
        if !rect.isEmpty {
            hits.append(SZHit(id: id, rect: rect, layer: layer, sense: sense))
        }
        var it = SZInteraction(id: id)
        let isActive = active == id
        it.held = isActive && isPointerDown
        it.hovered = hoverTarget == id && (active == nil || isActive)
        if pointerKind == .touch, !it.held {
            it.hovered = false
        }
        if it.held, pointerKind == .touch, let pointer {
            it.hovered = rect.contains(pointer)
        }
        it.pressed = pressedID == id
        it.released = releasedID == id
        it.clicked = clickedID == id
        it.presses = it.pressed || it.released ? pressCount : 0
        it.focused = focus == id
        if it.held, let pointer {
            it.dx = pointer.x - dragOrigin.x
            it.dy = pointer.y - dragOrigin.y
            it.heldDuration = time - pressTime
        }
        if !wheelTargets.isEmpty, let wheel = wheelTargets.first(where: { $0.id == id }) {
            it.wheelX = wheel.dx
            it.wheelY = wheel.dy
        }
        return it
    }

    /// Whether any rectangle above `layer` covers `p`, from the previous frame.
    func isCovered(_ p: SZPoint, above layer: Int) -> Bool {
        previousHits.contains { $0.layer > layer && $0.rect.contains(p) }
    }

    /// Whether `id` may take the pointer over: nothing holds it, or what
    /// holds it does not keep its drags.
    func canCapture(_ id: SZID) -> Bool {
        isPointerDown && active != id && !activeSense.contains(.drag)
    }

    /// Makes `id` the holder of the pointer from here on; the control that
    /// was pressed will not click. Movement restarts from the current point.
    func capture(_ id: SZID) {
        guard isPointerDown else { return }
        active = id
        activeSense = [.drag]
        if let pointer {
            dragOrigin = pointer
        }
    }

    /// Moves focus to `id`, or clears it.
    func setFocus(_ id: SZID?) {
        focus = id
    }

    // MARK: - Keyboard

    /// Takes the first unconsumed press of `key`.
    func takeKey(_ key: SZKeyCode, modifiers: SZModifiers) -> Bool {
        for i in keyEvents.indices where !keyEvents[i].consumed {
            if case let .key(code, mods) = keyEvents[i].event, code == key, mods == modifiers {
                keyEvents[i].consumed = true
                return true
            }
        }
        return false
    }

    /// Takes every unconsumed key and text event, in order.
    func takeTextEvents(caret: SZRect, numeric: Bool) -> [SZInputEvent] {
        textInput = SZTextInputRequest(caret: caret, numeric: numeric)
        var taken: [SZInputEvent] = []
        for i in keyEvents.indices where !keyEvents[i].consumed {
            keyEvents[i].consumed = true
            taken.append(keyEvents[i].event)
        }
        return taken
    }

    // MARK: - Hints and accessibility

    func setHint(_ text: String, owner: SZID, rect: SZRect) {
        pendingHint = (owner, text, rect)
    }

    /// Seconds the current hint has been showing.
    public var hintAge: Double {
        hint == nil ? 0 : time - hintSince
    }

    func addAccessibility(_ item: SZAccessibilityItem) {
        collectingAccessibility.append(item)
    }

    func raiseModalLayer(_ layer: Int) {
        pendingModalLayer = max(pendingModalLayer, layer)
    }

    // MARK: - State

    func state<Value>(_ id: SZID, _ initial: () -> Value) -> SZState<Value> {
        if var entry = states[id], let box = entry.box as? SZState<Value> {
            if entry.frame != frameNumber {
                entry.frame = frameNumber
                states[id] = entry
                touchedStates += 1
            }
            return box
        }
        let box = SZState(initial())
        states[id] = StateEntry(frame: frameNumber, box: box)
        touchedStates += 1
        return box
    }

    func animatedValue(_ id: SZID, target: Double, easing: Double, snap: Double, from: Double?) -> Double {
        guard var entry = animations[id] else {
            let start = from ?? target
            animations[id] = AnimationEntry(frame: frameNumber, value: start)
            touchedAnimations += 1
            if start != target {
                wantsFrame = true
            }
            return start
        }
        // A second read in the same frame must not advance it again.
        guard entry.frame != frameNumber else { return entry.value }
        entry.frame = frameNumber
        entry.value = SZEase.approach(entry.value, to: target, dt: dt, easing: easing, snap: snap)
        animations[id] = entry
        touchedAnimations += 1
        if entry.value != target {
            wantsFrame = true
        }
        return entry.value
    }

    // MARK: - Environment

    public func environment<Key: SZEnvironmentKey>(_ key: Key.Type) -> Key.Value {
        environmentValues[ObjectIdentifier(key)] as? Key.Value ?? Key.defaultValue
    }

    public func setEnvironment<Key: SZEnvironmentKey>(_ key: Key.Type, _ value: Key.Value) {
        environmentValues[ObjectIdentifier(key)] = value
    }
}

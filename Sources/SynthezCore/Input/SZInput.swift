//
//  SZInput.swift
//  SynthezCore
//

/// What produced pointer events. Touches have no hover: a touch pointer only
/// exists while a finger is down.
public enum SZPointerKind: Sendable {
    case touch
    case mouse
}

/// Keys widgets react to. Printable characters arrive as
/// ``SZInputEvent/text(_:)`` instead.
public enum SZKeyCode: Hashable, Sendable {
    case backspace
    case deleteForward
    case enter
    case escape
    case tab
    case left
    case right
    case up
    case down
    case home
    case end
    /// A character pressed with a command modifier, lowercased: Cmd+Z.
    case character(Character)
}

public struct SZModifiers: OptionSet, Hashable, Sendable {
    public let rawValue: UInt8
    public init(rawValue: UInt8) {
        self.rawValue = rawValue
    }

    public static let shift = SZModifiers(rawValue: 1 << 0)
    public static let control = SZModifiers(rawValue: 1 << 1)
    public static let option = SZModifiers(rawValue: 1 << 2)
    public static let command = SZModifiers(rawValue: 1 << 3)
}

/// One input event, in virtual pixels.
public enum SZInputEvent: Equatable, Sendable {
    case pointerDown(SZPoint, kind: SZPointerKind)
    case pointerMove(SZPoint, kind: SZPointerKind)
    case pointerUp(SZPoint, kind: SZPointerKind)
    /// The system took the touch away (a gesture, an alert): no click.
    case pointerCancel
    /// The pointer left the canvas (mouse or trackpad hover).
    case pointerExit
    /// Scroll-wheel or trackpad deltas in virtual pixels, positive is right/down.
    case wheel(SZPoint, dx: Double, dy: Double)
    case key(SZKeyCode, modifiers: SZModifiers)
    /// Text typed or pasted, delivered to the focused text widget.
    case text(String)
}

/// The senses an interactive rectangle answers to.
public struct SZSense: OptionSet, Hashable, Sendable {
    public let rawValue: UInt8
    public init(rawValue: UInt8) {
        self.rawValue = rawValue
    }

    public static let click = SZSense(rawValue: 1 << 0)
    public static let wheel = SZSense(rawValue: 1 << 1)
    public static let focus = SZSense(rawValue: 1 << 2)
    /// Hover only: the rectangle blocks hover beneath it but takes nothing.
    public static let hover = SZSense(rawValue: 1 << 3)
    /// Keeps its drags: a scroll view underneath will not take the pointer
    /// over once it moves. Sliders and knobs use it.
    public static let drag = SZSense(rawValue: 1 << 4)

    public static let button: SZSense = [.click, .focus]
}

/// What happened to one interactive rectangle this frame.
///
/// Routing uses the previous frame's rectangles, so a control learns about
/// its input in the same call that draws it.
public struct SZInteraction: Equatable, Sendable {
    public var id: SZID
    /// The pointer is over it and nothing above takes it. With touches, true
    /// only while the finger that pressed it stays inside.
    public var hovered = false
    /// Went down on it this frame.
    public var pressed = false
    /// Is being held: it was pressed and has not been released.
    public var held = false
    /// Was let go this frame, inside or not.
    public var released = false
    /// Was let go inside this frame after a press on it.
    public var clicked = false
    /// Presses in quick succession, counting this one: 2 is a double tap.
    public var presses = 0
    public var focused = false
    /// Pointer movement since the press (or since it captured the pointer),
    /// while held.
    public var dx = 0
    public var dy = 0
    public var wheelX: Double = 0
    public var wheelY: Double = 0
    /// Seconds it has been held.
    public var heldDuration: Double = 0

    public init(id: SZID) {
        self.id = id
    }

    public var doubleClicked: Bool {
        pressed && presses == 2
    }

    public var isActive: Bool {
        held || hovered
    }
}

/// A rectangle registered for input, kept to route the next frame.
struct SZHit {
    var id: SZID
    /// Absolute, already clipped.
    var rect: SZRect
    var layer: Int
    var sense: SZSense
}

/// Where a focused text widget wants the host's keyboard.
public struct SZTextInputRequest: Equatable, Sendable {
    /// The caret, absolute virtual pixels, for placing IME candidates.
    public var caret: SZRect
    public var numeric: Bool
}

/// Traits of an accessibility item.
public struct SZAccessibilityTraits: OptionSet, Hashable, Sendable {
    public let rawValue: UInt16
    public init(rawValue: UInt16) {
        self.rawValue = rawValue
    }

    public static let button = SZAccessibilityTraits(rawValue: 1 << 0)
    public static let selected = SZAccessibilityTraits(rawValue: 1 << 1)
    public static let adjustable = SZAccessibilityTraits(rawValue: 1 << 2)
    public static let staticText = SZAccessibilityTraits(rawValue: 1 << 3)
    public static let notEnabled = SZAccessibilityTraits(rawValue: 1 << 4)
    public static let header = SZAccessibilityTraits(rawValue: 1 << 5)
    public static let textField = SZAccessibilityTraits(rawValue: 1 << 6)
    public static let tab = SZAccessibilityTraits(rawValue: 1 << 7)
}

/// One element a screen reader or UI test can find, collected each frame.
public struct SZAccessibilityItem: Equatable, Sendable {
    public var id: SZID
    /// Absolute virtual pixels, clipped.
    public var rect: SZRect
    public var layer: Int
    public var label: String
    public var value: String?
    public var traits: SZAccessibilityTraits
}

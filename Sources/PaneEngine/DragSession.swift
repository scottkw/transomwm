import PaneModel

/// Modifier keys read from each pointer and flagsChanged event (D-05). Only ⇧ (bypass) and ⌘ (swap) change a drop;
/// ⌥ (Sequoia's tiling modifier) and ⌃ (right-click) are carried and ignored.
public struct Modifiers: OptionSet, Hashable, Sendable {
    public let rawValue: Int
    public init(rawValue: Int) { self.rawValue = rawValue }

    public static let shift = Modifiers(rawValue: 1 << 0)
    public static let command = Modifiers(rawValue: 1 << 1)
    public static let option = Modifiers(rawValue: 1 << 2)
    public static let control = Modifiers(rawValue: 1 << 3)
}

/// One left-button or modifier event from the event tap, in global top-left points. `pressWindow` is resolved by the
/// shell on `down` only (RESEARCH Pattern 4).
public struct PointerEvent: Equatable, Sendable {
    public enum Kind: Equatable, Sendable { case down, dragged, up, flagsChanged }

    public var kind: Kind
    public var location: Point
    public var modifiers: Modifiers
    public var pressWindow: WindowRef?

    public init(kind: Kind, location: Point, modifiers: Modifiers = [], pressWindow: WindowRef? = nil) {
        self.kind = kind
        self.location = location
        self.modifiers = modifiers
        self.pressWindow = pressWindow
    }
}

/// What the drop preview shows (UI-SPEC Surface 2), in global top-left points.
public enum PreviewState: Equatable, Sendable {
    /// The exact frame the window gets on release.
    case dock(Rect)
    /// The frame the window would get if minimum sizes were ignored; the drop is refused.
    case blocked(Rect)
    /// ⌘ over another docked tile: that tile, and the dragged window's own tile dashed.
    case swap(target: Rect, origin: Rect)
    /// The tile a docked window goes back to, with an optional label.
    case snapBack(Rect, label: String?)
    /// Where a floating window lands, clamped inside the Desktop tile.
    case clamp(Rect)
}

/// What a release does once a hover has been held for the dwell.
enum DropAction: Equatable, Sendable {
    case dock(DeskKey, DropTarget)
    case swap(WindowRef)
    /// ⇧ on a docked window: it floats at its release frame, clamped inside the Desktop tile if it crosses a tile.
    case undock
    /// The miss rules: a docked window snaps back, a floating one stays where released (clamped if it crosses a tile).
    case miss
    /// Announce `text`, then the miss rules.
    case refuse(String)
}

/// What the pointer is over, reduced to what decides the drop. The dwell restarts only when this changes.
struct Hover: Equatable, Sendable {
    var displayUUID: String?
    var target: DropTarget?
    var swapWith: WindowRef?
    /// The modifiers that apply: ⇧, and ⌘ for a docked window.
    var modifiers: Modifiers = []
    /// A floating (or ⇧-undocking) window's frame crosses a docked tile.
    var crossesTiles = false
}

/// The dry run's verdict for one hover (UI-SPEC Surface 2 state matrix).
struct Decision: Equatable, Sendable {
    var preview: PreviewState?
    var action: DropAction
    /// The display the preview is drawn on.
    var display: String?
    /// When set, the preview is a clamp ghost that follows the window: its frame clamped into this Desktop rect.
    var clampInto: Rect?
}

/// One left-button press on a tracked window, from mouse-down to mouse-up. Pure: the Arranger feeds it pointer samples,
/// frames and hovers, and decides what they mean.
public struct DragSession: Equatable, Sendable {
    /// Below this travel, a frame change is never a drag (a title-bar double-click zooms with none; Pitfall 6).
    public static let minimumTravel = 3.0
    /// A frame within this of Pane's last read-back is its own write coming back (the echo rule).
    public static let echoTolerance = 2.0
    /// How long a hover must hold before its preview shows (CONTEXT A).
    public static let dwell: Duration = .milliseconds(150)

    public enum Kind: Equatable, Sendable {
        /// The origin moved with the size unchanged: a title-bar drag.
        case move
        /// The size changed: an edge resize (plan 13).
        case resize
    }

    public let window: WindowRef
    public let start: Point
    public let startFrame: Rect
    public internal(set) var pointer: Point
    public internal(set) var modifiers: Modifiers
    /// nil until the press is classified; the first verdict sticks.
    public internal(set) var kind: Kind?
    /// The 60 Hz frame poll was asked for.
    public internal(set) var polling = false
    /// How many dry runs this session has run (one per held hover).
    public internal(set) var dryRuns = 0
    /// The preview on screen, and its display.
    public internal(set) var shown: PreviewState?
    var shownOn: String?
    var hover: Hover?
    var hoverSince: ContinuousClock.Instant?
    var decision: Decision?

    public init(window: WindowRef, start: Point, startFrame: Rect, modifiers: Modifiers) {
        self.window = window
        self.start = start
        self.startFrame = startFrame
        pointer = start
        self.modifiers = modifiers
    }

    /// The pointer has travelled at least `minimumTravel` from the press.
    public var travelled: Bool { false }

    /// Classifies a frame report of the press window (RESEARCH Pattern 1).
    public mutating func observe(_ frame: Rect, lastApplied: Rect?) {}

    /// Feeds the current hover; true when it changed, which restarts the dwell and drops the decision.
    mutating func update(hover: Hover, at now: ContinuousClock.Instant) -> Bool { false }

    /// When the held hover's dry run is due; nil once decided or with no hover.
    var dwellEnds: ContinuousClock.Instant? { nil }

    /// Runs `dryRun` once for the held hover after the dwell; returns the new decision, or nil if none was due.
    mutating func settle(at now: ContinuousClock.Instant, dryRun: (Hover) -> Decision) -> Decision? { nil }
}

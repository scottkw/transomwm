import TransomModel

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

/// How a title-bar drag docks (D-07): automatically, or only with ⌥ held.
public enum DragToDockMode: String, CaseIterable, Sendable {
    case automatic, holdOption
}

/// What the event tap does with ⌥ on the events it passes on, so macOS's own ⌥ tiling stays away (D-07a).
public enum DragOptionStrip: Equatable, Sendable {
    case off
    /// A Hold ⌥ move: ⌥ always goes.
    case always
    /// An Automatically move: ⌥ goes only with ⌃, the fourths chord (UI-SPEC rows 2-3).
    case withControl
}

/// One left-button or modifier event from the event tap, in global top-left points. `pressWindow` is resolved by the
/// shell on `down` only (RESEARCH Pattern 4); a press on a strip tab carries `pressTab` instead, never `pressWindow`
/// (Pattern 7, Pitfall 4).
public struct PointerEvent: Equatable, Sendable {
    public enum Kind: Equatable, Sendable { case down, dragged, up, flagsChanged }

    public var kind: Kind
    public var location: Point
    public var modifiers: Modifiers
    public var pressWindow: WindowRef?
    public var pressTab: WindowRef?

    public init(kind: Kind, location: Point, modifiers: Modifiers = [], pressWindow: WindowRef? = nil, pressTab: WindowRef? = nil) {
        self.kind = kind
        self.location = location
        self.modifiers = modifiers
        self.pressWindow = pressWindow
        self.pressTab = pressTab
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
    /// Zoom on: the drop is accepted and windows collapse (ZOOM-13). The frame the window would get if minimum sizes
    /// were ignored, labelled with who collapses (`CollapseCopy`).
    case collapsed(Rect, label: String)
    /// A centre held for the group dwell: the group frame, its strip band, and the label (`GroupCopy`), hidden by the
    /// clearance rule in a small content rect.
    case group(frame: Rect, strip: Rect, label: String?)
}

/// UI-SPEC Surface 1: the Group preview's labels.
public enum GroupCopy {
    public static let newGroup = "Group as tabs"
    public static let addTab = "Add as a tab"
}

/// UI-SPEC Surface 7: the Collapsed preview's labels and the announcements of an accepted drop or keyboard dock.
public enum CollapseCopy {
    public static let draggedLabel = "Collapsed until you zoom in"

    public static func othersLabel(_ count: Int) -> String {
        count == 1 ? "1 window collapses" : "\(count) windows collapse"
    }

    public static func dockedAnnouncement(dragged: Bool, others: Int) -> String {
        if dragged { return "Docked. Zoom in to see it." }
        return others == 1 ? "Docked. 1 window collapsed." : "Docked. \(others) windows collapsed."
    }
}

/// UI-SPEC Surface 2: the announcement of a pulled-out window in Hold ⌥ mode.
public enum FourthCopy {
    public static let floating = "Floating"
}

/// What a centre drop groups with (D-02): a docked leaf, a panel or an existing group; or on the Desktop tile a plain
/// floating window (the middle 50% of its frame) or a floating group (the middle 50% of its content rect).
enum GroupTarget: Equatable, Sendable {
    case tile(DeskKey, NodeID)
    case floating(DeskKey, WindowRef)
    case floatingGroup(DeskKey, NodeID)
}

/// What a release does once a hover has been held for the dwell.
enum DropAction: Equatable, Sendable {
    case dock(DeskKey, DropTarget)
    /// The window joins the target as its selected tab (D-03).
    case group(DeskKey, GroupTarget)
    case swap(WindowRef)
    /// ⇧ on a docked window: it floats at its release frame, clamped inside the Desktop tile if it crosses a tile.
    case undock
    /// The miss rules: a docked window snaps back, a floating one stays where released (clamped if it crosses a tile).
    case miss
    /// A torn-off tab with no dock or group target: it floats at its landing frame on this desk (D-10).
    case tearOffFloat(DeskKey)
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
    /// The centre under the pointer that groups after `DragSession.groupDwell`; `target` is nil meanwhile.
    var groupTarget: GroupTarget?
    /// A tear-off's pointer is back over its source strip: no preview, and a release cancels (D-10).
    var overStrip = false
    /// Hold ⌥'s plain drag: the result never depends on the dwell, so it is decided at mouse-up (UI-SPEC Surface 2).
    var plain = false
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
    /// A frame within this of Transom's last read-back is its own write coming back (the echo rule).
    public static let echoTolerance = 2.0
    /// How long a hover must hold before its preview shows (CONTEXT A).
    public static let dwell: Duration = .milliseconds(150)
    /// How long the pointer must rest in a centre before it groups (D-01); the Phase 3 dwell runs inside it.
    public static let groupDwell: Duration = .milliseconds(400)
    /// How far the pointer may wander from where the group dwell started before it restarts there (D-01).
    public static let groupRest = 16.0
    /// Hold ⌥: a plain drag of a docked window pulls it out only from this far from the press, so a nudge can't float it (D-08a).
    public static let pullOutTravel = 16.0

    /// What the press grabbed: a window's title bar, or a tab torn out of its strip (D-10), whose window does not move
    /// until release and lands at `landingSize` under the pointer.
    public enum Origin: Equatable, Sendable {
        case window
        case tearOff(GroupKey, stripRect: Rect, landingSize: Size)
    }

    public enum Kind: Equatable, Sendable {
        /// The origin moved with the size unchanged: a title-bar drag.
        case move
        /// The size changed: an edge resize, which moves a docked window's split boundaries (D-07).
        case resize
    }

    public let window: WindowRef
    public let start: Point
    public let startFrame: Rect
    public internal(set) var origin: Origin = .window
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
    /// Where and when the group dwell started, and its verdict once it completed.
    var groupAnchor: Point?
    var groupSince: ContinuousClock.Instant?
    var groupDecision: Decision?

    /// The decision a release applies: the group dwell's once it completed, else the Phase 3 one.
    var current: Decision? { groupDecision ?? decision }

    public init(window: WindowRef, start: Point, startFrame: Rect, modifiers: Modifiers) {
        self.window = window
        self.start = start
        self.startFrame = startFrame
        pointer = start
        self.modifiers = modifiers
    }

    /// The group a tear-off leaves; nil for a window drag.
    public var tearOffGroup: GroupKey? {
        if case .tearOff(let group, _, _) = origin { group } else { nil }
    }

    /// Where a torn-off tab would land with the pointer at `pointer` (UI-SPEC Surface 4): its landing size centred on
    /// the pointer, top edge 12 pt above it so the title bar is under it. A window drag's start frame.
    public func landingFrame(at pointer: Point) -> Rect {
        guard case .tearOff(_, _, let size) = origin else { return startFrame }
        return Rect(x: pointer.x - size.width / 2, y: pointer.y - 12, width: size.width, height: size.height)
    }

    /// The drop the held hover decided, for the shell's drag log (WR-03); "none" until a dwell has passed.
    public var decisionSummary: String { current.map { "\($0.action)" } ?? "none" }

    /// The pointer has travelled at least `minimumTravel` from the press.
    public var travelled: Bool {
        let dx = pointer.x - start.x, dy = pointer.y - start.y
        return (dx * dx + dy * dy).squareRoot() >= Self.minimumTravel
    }

    /// The pointer is at least `pullOutTravel` from the press now, so coming back inside it counts as not travelled.
    public var travelledToPullOut: Bool {
        let dx = pointer.x - start.x, dy = pointer.y - start.y
        return (dx * dx + dy * dy).squareRoot() >= Self.pullOutTravel
    }

    /// Classifies a frame report of the press window (RESEARCH Pattern 1): within 2 pt of Transom's last read-back it is an
    /// echo; after 3 pt of travel a changed size is an edge resize and a changed origin with the same size a move.
    public mutating func observe(_ frame: Rect, lastApplied: Rect?) {
        guard kind == nil, travelled else { return }
        if let lastApplied, Self.near(lastApplied, frame, within: Self.echoTolerance) { return }
        if abs(frame.width - startFrame.width) > 1 || abs(frame.height - startFrame.height) > 1 {
            kind = .resize
        } else if frame.x != startFrame.x || frame.y != startFrame.y {
            kind = .move
        }
    }

    /// Feeds the current hover; true when it changed, which restarts the dwell and drops the decision. The group dwell
    /// restarts only when the centre or the modifiers change; moving inside the same centre never restarts the Phase 3 one.
    mutating func update(hover: Hover, at now: ContinuousClock.Instant) -> Bool {
        // Wandering more than `groupRest` before the Group preview shows restarts the group dwell from here (D-01).
        if groupDecision == nil, let anchor = groupAnchor, hover.groupTarget == self.hover?.groupTarget,
            ((pointer.x - anchor.x) * (pointer.x - anchor.x) + (pointer.y - anchor.y) * (pointer.y - anchor.y)).squareRoot() > Self.groupRest
        {
            groupAnchor = pointer
            groupSince = now
        }
        guard hover != self.hover else { return false }
        if hover.groupTarget != self.hover?.groupTarget || hover.modifiers != self.hover?.modifiers {
            groupAnchor = hover.groupTarget == nil ? nil : pointer
            groupSince = hover.groupTarget == nil ? nil : now
            groupDecision = nil
        }
        self.hover = hover
        hoverSince = now
        decision = nil
        return true
    }

    /// When the held hover's dry run is due; nil once decided or with no hover.
    var dwellEnds: ContinuousClock.Instant? {
        decision == nil ? hoverSince.map { $0 + Self.dwell } : nil
    }

    /// When the held centre's group dry run is due; nil once decided or with no centre.
    var groupDwellEnds: ContinuousClock.Instant? {
        groupDecision == nil ? groupSince.map { $0 + Self.groupDwell } : nil
    }

    /// Runs `dryRun` once for the held centre after the group dwell; returns the new decision, or nil if none was due.
    mutating func settleGroup(at now: ContinuousClock.Instant, dryRun: (Hover) -> Decision) -> Decision? {
        guard let hover, let due = groupDwellEnds, now >= due else { return nil }
        let decided = dryRun(hover)
        groupDecision = decided
        dryRuns += 1
        return decided
    }

    /// Runs `dryRun` once for the held hover after the dwell; returns the new decision, or nil if none was due.
    mutating func settle(at now: ContinuousClock.Instant, dryRun: (Hover) -> Decision) -> Decision? {
        guard let hover, let due = dwellEnds, now >= due else { return nil }
        let decided = dryRun(hover)
        decision = decided
        dryRuns += 1
        return decided
    }

    static func near(_ a: Rect, _ b: Rect, within tolerance: Double) -> Bool {
        abs(a.x - b.x) <= tolerance && abs(a.y - b.y) <= tolerance && abs(a.width - b.width) <= tolerance
            && abs(a.height - b.height) <= tolerance
    }
}

import Foundation
import TransomModel

/// Everything the Arranger reacts to. `requeried` carries the real states of windows an undo revived (D-11).
public enum ArrangerInput: Sendable {
    case inventory(WindowInventory)
    case event(WindowEvent)
    case command(Command, focused: WindowRef?)
    case requeried(RevivedWindows, [(WindowRef, WindowState)])
    /// The instant a `wake` asked for has come.
    case tick
    /// The layout saved by the last session (layout.json). It is re-attached by identity at the first complete inventory.
    /// `arrangement` and `layoutSets` are the saved display arrangement and the other arrangements' layouts (D-09).
    /// `views` are the saved views (D-14). `bootChanged`: the saved boot session differs from this one, so no saved
    /// identity is kept (`LayoutRestore.retire`, RESEARCH Pitfall 5).
    case restore(
        World, homeFrames: [WindowIdentity: Rect], wantedFrames: [WindowIdentity: Rect] = [:], arrangement: ArrangementID = ArrangementID([]),
        layoutSets: [LayoutSet] = [], views: [SavedView] = [], bootChanged: Bool = false)
    /// Displays began reconfiguring (OVER-05): until `.displaysSettled` no window is re-homed by display and no frame is
    /// written, so macOS moving windows off a vanishing display cannot destroy the tiles a re-plug needs (Pitfall 4).
    case displaysSettling
    /// Displays are quiet again: the new arrangement, each display's name captured before it left (for N12), and the
    /// inventory read after the change (D-10, D-11, OVER-06).
    case displaysSettled(ArrangementID, names: [String: String], inventory: WindowInventory)
    /// Sets or clears one pause reason; Stage Manager (plan 16) and the crash loop (plan 14) arrive this way.
    case setPaused(PauseReason, Bool)
    /// The gap between tiles (D-27), already validated by the shell's allow-list.
    case gap(Double)
    /// How a title-bar drag docks (D-07), from the shell's stored preference.
    case dragToDock(DragToDockMode)
    /// What a new window does (D-01), from the shell's stored preference.
    case newWindows(NewWindowsMode)
    /// A left-button or modifier event from the event tap (TILE-01).
    case pointer(PointerEvent)
    /// The pressed window's CG bounds from the 60 Hz drag poll.
    case dragFrame(WindowIdentity, Rect)
    /// A press on this window's green button, which the tap swallowed (TILE-06).
    case greenButton(WindowRef)
    /// A gap handle dragged `delta` points along its axis from where the drag began; `ended` on mouse-up (TILE-05).
    case gapDrag(GapHandle, delta: Double, ended: Bool)
    /// How this launch treats the saved layout (D-17, D-18); fed before `.restore`.
    case launch(LaunchMode)
    /// Zoom on or off (D-D); off by default, which is exactly Phase 3.
    case zoomEnabled(Bool)
    /// Move that display's camera to `ViewTarget` (D-A): answered with one `.cameraMove`, no writes. `focus` is focused
    /// right after the settle's writes (a click on a window, ZOOM-06).
    case zoomTo(ViewTarget, displayUUID: String, focus: WindowRef? = nil)
    /// The stage finished move `moveID` on that display: the view is committed and written now.
    case cameraSettle(displayUUID: String, moveID: UInt64)
    /// A camera command on that display (the pointer's), with the focused window and the pointer Step In reads.
    case camera(CameraCommand, displayUUID: String, focused: WindowRef?, pointer: Point?)
    /// A tab action (a strip click, D-08 selection); `ready` is whether Accessibility access works.
    case tab(TabAction, ready: Bool)
    /// The answer to `.checkClosePrompt`: whether the window shows a sheet (a save prompt) now.
    case closePrompt(WindowRef, showing: Bool)
    /// Menu ▸ Arrange ▸ Clear Waiting Tiles (D-24). Not a `Command`: no chord, URL or CLI route.
    case clearWaitingTiles
}

/// Why arranging is paused (D-23). Arranging runs only while no reason is set. A lower raw value is a higher priority,
/// which picks the menu's pause line.
public enum PauseReason: Int, Comparable, Hashable, Sendable {
    case stageManager = 0, crashLoop = 1, user = 2

    public static func < (lhs: Self, rhs: Self) -> Bool { lhs.rawValue < rhs.rawValue }
}

/// One split boundary an edge resize or a gap drag moves (D-07): `points` along the split's axis, positive growing
/// child `first` at the expense of child `second`.
struct BoundaryMove: Equatable, Sendable {
    var split: NodeID
    var first: Int
    var second: Int
    var points: Double
}

extension BoundaryMove {
    init(_ handle: GapHandle, _ points: Double) {
        self.init(split: handle.split, first: handle.first, second: handle.second, points: points)
    }
}

/// How soon the shell writes layout.json: about 0.5 s after the latest request, or at once (before a park, plan 08).
public enum SaveUrgency: Equatable, Sendable {
    case debounced, now
}

/// What the shell runs, in order. `fault` names window identities only (never titles); the shell logs it.
public enum ArrangerEffect: Equatable, Sendable {
    case perform([WindowCommand])
    case requery(RevivedWindows)
    case beep
    case announce(String)
    case fault(String)
    /// Worth one info-level log line (the shell logs it with the arrange category).
    case info(String)
    /// A toast for the user (the shell queues it).
    case notice(Notice)
    /// Feed `.tick` at this instant. A newer wake replaces an older one.
    case wake(at: ContinuousClock.Instant)
    /// The World changed: write layout.json.
    case save(SaveUrgency)
    /// Open a new Finder window by pressing Finder's own ⌘N menu item (RESEARCH Pattern 14).
    case openFinderWindow
    /// Show this drop preview on that display, or withdraw it (nil).
    case preview(PreviewState?, displayUUID: String?)
    /// Poll this window's CG bounds at 60 Hz and feed `.dragFrame`; nil stops the poll.
    case pollDragFrame(WindowRef?)
    /// Flash the blocked preview at this frame for 600 ms (a refused keyboard Dock, UI-SPEC keyboard parity).
    case flashBlocked(Rect, displayUUID: String)
    /// The gap handles to show on that display; empty hides them (UI-SPEC Surface 3).
    case gapHandles([GapHandle], displayUUID: String)
    /// The fourth zone guides to show on that display; empty hides them (08.1 UI-SPEC Surface 3).
    case fourthGuides([Rect], displayUUID: String)
    /// Animate this camera move, then feed `.cameraSettle` with its ID (RESEARCH Pattern 4).
    case cameraMove(CameraMove)
    /// The collapsed blocks to show on that display; empty hides them (UI-SPEC Surface 3, ZOOM-13).
    case collapsedBlocks([CollapsedBlock], displayUUID: String)
    /// Speak this tab-group change (the shell formats it with `TabCopy`).
    case tabAnnouncement(TabAnnouncement)
    /// The tab strips to show on that display; empty hides them (UI-SPEC Surface 2).
    case tabStrips([TabStrip], displayUUID: String)
    /// The tiles held for absent windows on that display's shown desk; empty hides them (08 UI-SPEC Surface 2).
    case placeholders([PlaceholderTile], displayUUID: String)
    /// Order this group's strip front: one of its members was just selected (UI-SPEC Surface 2 ordering).
    case raiseStrip(GroupKey)
    /// Show or move the tear-off ghost at this pointer; nil hides it (UI-SPEC Surface 4).
    case tearOffGhost(TearOffGhost?)
    /// A newly selected tab is in place (its read-back matched): with zoom on the shell captures it once in the
    /// background (UI-SPEC Surface 6, Snapshots).
    case tabRevealed(WindowRef)
    /// Close Group's member is still open past its deadline: read whether it shows a sheet (read-only AX) and answer
    /// with `.closePrompt` (D-06, 2026-11-02).
    case checkClosePrompt(WindowRef)
}

/// The pure layout owner (RESEARCH Pattern 1): window-system inputs and user commands in, commands and effects out.
/// It never sleeps and never touches the OS; `ArrangeController` (TransomMac) and the tests drive it the same way.
/// OS facts change the World through `LifecycleSync` and `World.reflow`, user commands through `World.edit`.
public struct Arranger: Sendable {
    public static let noRoom = "Not enough room to dock here"
    /// Announced when a ⌘-drop swaps two windows (UI-SPEC Accessibility).
    public static let swapped = "Swapped"
    /// The bypass with the Desktop tile hidden: the snap-back ghost's label and the announcement (UI-SPEC Surface 2).
    public static let showDesktopToFloat = "Show the Desktop Tile to float windows"
    public static let finderBundleID = "com.apple.finder"
    /// How long ⌃⌥⌘N waits for Finder's new window (D-14).
    public static let finderWait: Duration = .seconds(2)

    // internal(set): the command handlers in Arranger+Commands.swift edit them.
    public internal(set) var world = World()
    public internal(set) var history = UndoHistory()
    /// The latest info per tracked window, docked or not.
    public private(set) var windows: [WindowIdentity: WindowInfo] = [:]
    public private(set) var displays: [DisplayInfo] = []
    /// Where each parked window goes back to (plan 08); restored from layout.json.
    public internal(set) var homeFrames: [WindowIdentity: Rect] = [:]
    /// The frame each window goes back to when it floats (G-03-11). Only user actions and the frames a window takes
    /// on its own write it; it is kept while the window is docked, so it is the pre-dock frame (G-03-4). Undo (except
    /// to give back `undockedWanted`), echoes of Transom's own writes, parks and rescues leave it alone. Dock's centre and
    /// the overlap tests read the recorded frame, never this one. internal(set): the command handlers in Arranger+Commands.swift write it.
    public internal(set) var wantedFrames: [WindowIdentity: Rect] = [:]
    /// The wanted frame Float All or a ⇧-undock replaced, per window. Wanted frames are not in the desk snapshots, so an
    /// Undo that docks the window again gives this one back, and Float still goes to the pre-dock frame (WR-02).
    /// shortcut: one level per window, so an Undo across two undocks of one window gives back the later one's; snapshot
    /// wanted frames per undo step if that matters.
    var undockedWanted: [WindowIdentity: Rect] = [:]
    public var gap: Double
    public internal(set) var dragToDock: DragToDockMode
    /// Whether a window opened while Transom runs floats or docks (D-01).
    public internal(set) var newWindows: NewWindowsMode
    /// While any reason is set, facts still change the World but no window command is sent (TILE-08).
    public private(set) var pauseReasons: Set<PauseReason> = []
    /// The last frame requested for each window that is still planned; a frame within 0.5 pt of it is not written
    /// again, so an app echoing frames cannot cause a write storm (T-03-08).
    var lastRequested: [WindowIdentity: Rect] = [:]
    /// Locked or asleep: nothing is written until the session resumes, then every visible desk is re-planned.
    public internal(set) var sessionPaused = false
    /// The Spaces-off fallback (A7) is reported once per session.
    private var reportedSpacesOff = false
    /// Each window's last read-back (`frameApplied`): a move or resize within 2 pt of it is Transom's own write coming
    /// back, never a move to answer (the echo rule).
    private var lastApplied: [WindowIdentity: Rect] = [:]
    /// When each docked window was last put back in its tile, and the ones waiting for that second to pass (T-03-13).
    private var lastCorrection: [WindowIdentity: ContinuousClock.Instant] = [:]
    private var pendingCorrections: Set<WindowIdentity> = []
    private static let correctionInterval: Duration = .seconds(1)
    /// The tile each docked window refused and was sent once more (G-03-6); a new tile, or docking again, allows one new retry.
    private var refusalRetried: [WindowIdentity: Rect] = [:]
    /// The layout saved by the last session, waiting for the first complete inventory (SAFE-06).
    private var pendingRestore: (world: World, homeFrames: [WindowIdentity: Rect], wantedFrames: [WindowIdentity: Rect])?
    /// A saved layout that could not be re-attached: still what is saved, with the arrangement it was saved under, so
    /// this session cannot overwrite or relabel it (WR-04, CR-01).
    private var unattached: (world: World, homeFrames: [WindowIdentity: Rect], wantedFrames: [WindowIdentity: Rect], arrangement: ArrangementID)?
    /// The next re-attach throws this. Real data cannot build a World whose re-attach throws (closing a window always
    /// leaves a valid one), so outside a failed `retire` this is for tests, standing in for the failure CR-01 guards against.
    var reattachFault: LayoutError?
    /// How this launch treats the saved layout (D-17, D-18): read once, at the re-attach.
    private var launch: LaunchMode = .normal
    /// Windows a `park` was sent for and that are still parked, so each is parked once, not on every re-plan.
    var parkRequested: Set<WindowIdentity> = []
    /// The size each sized park (a hidden tab) was sent at: a content size that changes parks the window again (Pitfall 1).
    private var parkedSize: [WindowIdentity: Size] = [:]
    /// Whether a park was sent for `window` and it is still parked (the overview's camera-move pick, 06-09).
    public func isParked(_ window: WindowRef) -> Bool { parkRequested.contains(window.identity) }
    /// The left-button press in progress, if any (TILE-01).
    public internal(set) var drag: DragSession?
    /// A title-bar drag is under way (plan 16 defers alerts while it is).
    public var isDragging: Bool { drag?.kind == .move }
    /// What the tap should do with ⌥ now (D-07a).
    public var dragOptionStrip: DragOptionStrip {
        guard drag?.kind == .move else { return .off }
        return dragToDock == .holdOption ? .always : .withControl
    }
    /// Desk plans a drag hit-tests against, computed once per drag (and again after the World changes).
    private var dragPlans: [DragPlanKey: FramePlan] = [:]
    /// The gap handles last sent per display, so only a change is sent again.
    private var shownHandles: [String: [GapHandle]] = [:]
    /// The gap being dragged and its points since the press, applied by every replan until mouse-up (G-03-3 H2).
    private var liveGap: (handle: GapHandle, delta: Double)?
    /// A press or gap drag is under way. A window joining a desk now could show a hidden Desktop or resize it for the
    /// floater, moving tiles under the drag and changing what it commits, so `admit` waits for the end (WR-01).
    var gestureLive: Bool { drag != nil || liveGap != nil }
    /// The windows `admit` held back during the gesture.
    private var heldAdmits: Set<WindowIdentity> = []
    /// Auto-tiled windows with no known minimum that have not yet taken a tile (`settleAutoTile`, WR-05).
    var awaitingFit: Set<WindowIdentity> = []
    /// The zoom camera (Arranger+Camera.swift).
    var camera = CameraState()
    /// Tab strips shown and the selection waiting for its read-back (Arranger+Tabs.swift).
    var tabs = TabGroupState()
    /// Windows waiting to come back and their deadlines (Arranger+Placeholders.swift).
    var placeholders = PlaceholderState()
    /// Displays are reconfiguring (`.displaysSettling`): no display-based re-homing, no frames.
    public private(set) var settling = false
    /// The World when settling began: stored as the old arrangement's layout set at the settle.
    private var preChangeWorld: World?
    /// The current display arrangement (D-09); unknown until a restore or the first inventory says.
    public private(set) var arrangement = ArrangementID([])
    /// The other arrangements' layouts (OVER-06).
    public private(set) var layoutSets = LayoutSets()
    /// Windows an undoable user edit placed since the last arrangement switch: they keep their placement when a stored
    /// set is applied (user action wins, RESEARCH Open Question 3).
    private var userPlacedSinceSwitch: Set<WindowIdentity> = []

    private enum DragPlanKey: Hashable {
        case desk(DeskKey)
        /// The pressed docked window's desk with it floating at its press frame: where a ⇧-drop would put it.
        case undock
    }
    /// Window identities, the most recently focused first: focus ties go to the earliest (D-11).
    public private(set) var focusOrder: [WindowIdentity] = []
    /// The split ⌃⌥⌘N asked for, waiting for Finder's new window; a newer one replaces it.
    var finderExpectation: FinderExpectation?

    struct FinderExpectation: Sendable {
        let key: DeskKey
        /// The tile to split; nil docks at the layout edge, the root on an empty desk.
        let target: NodeID?
        let edge: Edge
        /// Finder windows already tracked at the press: a change to one of them is never the new window.
        let known: Set<WindowIdentity>
        let deadline: ContinuousClock.Instant

        /// This is the window the press is waiting for.
        func matches(_ info: WindowInfo, now: ContinuousClock.Instant) -> Bool {
            info.window.bundleID == Arranger.finderBundleID && !known.contains(info.window.identity) && now < deadline
        }
    }

    public init(gap: Double = 8, dragToDock: DragToDockMode = .automatic, newWindows: NewWindowsMode = .float) {
        self.gap = gap
        self.dragToDock = dragToDock
        self.newWindows = newWindows
    }

    /// Every input that changes the World ends with `.save(.debounced)`, so layout.json follows it (D-16).
    public mutating func handle(_ input: ArrangerInput, now: ContinuousClock.Instant) -> [ArrangerEffect] {
        let before = world, beforeHistory = history, earliest = earliestPlaceholderDeadline, shownBefore = displays
        var effects = process(input, now: now)
        if !heldAdmits.isEmpty, !gestureLive { effects += admitHeld() }
        if displays != shownBefore { extendPlaceholdersShown(since: shownBefore, now: now) }
        if earliestPlaceholderDeadline != earliest, let wake = nextWake { effects.append(.wake(at: wake)) }
        // Home frames are only for parked windows; on a shown Desktop they are spent, even when no re-plan runs (WR-06).
        if !homeFrames.isEmpty {
            for desk in world.desks.values where desk.tree.isDesktopHidden != true {
                for floating in desk.desktop.windows { homeFrames[floating.window.identity] = nil }
            }
        }
        if let dragged = drag, dragged.kind != nil { placeholders.fresh.remove(dragged.window.identity) }  // the user's now
        guard world != before else { return effects }
        placeholders.prune(world)
        dragPlans = [:]  // the plans a drag caches are of the World before
        // A window that left its floating group (a dissolve, an undo, a drag out) wanted the group's content rect: from
        // now on it wants its stored frame, the whole group frame for a survivor (the band returns to it).
        // The input's own re-plan ran before this, so plan again.
        // One that left docked (Dock Group) keeps it as its pre-dock frame, as Dock Window keeps a floater's.
        let floating = Set(world.desks.values.flatMap { $0.desktop.windows.map(\.window.identity) })
        let left = Self.floatingGroupMembers(before).subtracting(Self.floatingGroupMembers(world)).intersection(floating)
        if !left.isEmpty {
            for id in left { wantedFrames[id] = nil }
            effects += replan()
        }
        // An undo step means a user edit: every window it gave a new desk or tile was placed by the user (OVER-06).
        if history != beforeHistory, Self.isUserEdit(input) { userPlacedSinceSwitch.formUnion(Self.placementChanges(from: before, to: world)) }
        return effects.contains(.save(.debounced)) ? effects : effects + [.save(.debounced)]
    }

    private mutating func process(_ input: ArrangerInput, now: ContinuousClock.Instant) -> [ArrangerEffect] {
        switch input {
        case .inventory(var inventory):
            let dormant = Set(dormantWindows.map(\.identity)).union(placeholders.table.keys)
            adopt(inventory)
            if arrangement.isUnknown, !settling, !displays.isEmpty { arrangement = ArrangementID(displays.map(\.uuid)) }
            guard let restore = pendingRestore else {
                // A dormant window this inventory tracks before its windowCreated is handled wakes here (WR-01).
                var faults: [ArrangerEffect] = []
                for info in inventory.windows where dormant.contains(info.window.identity) {
                    placeholders.table[info.window.identity] = nil  // the very window came back
                    do throws(LayoutError) { try wakeDormant(info) } catch {
                        faults.append(.fault("kept the saved state and frame of \(info.window): \(error)"))
                    }
                }
                // A dormant window whose ID left the CG list closed (G-03-8), or its app is quitting (D-12b): a docked one
                // waits to see which. A paused, unknown or empty list decides nothing.
                guard !inventory.sessionPaused, let live = inventory.liveWindows, !live.isEmpty else { return faults + place(inventory) }
                let left = dormantWindows.filter { !LayoutRestore.isAlive($0.identity, in: live) }
                holdLeftCGList(left, now: now)
                return faults + closeDormant { left.contains($0) } + place(inventory)
            }
            // The saved layout waits for every app's first answer, so no saved window is dropped as untracked, and for an
            // unlocked session with a non-empty CG list: a blank one can't tell a closed window from one on a hidden Space
            // (T-03-63, CR-03). The shell feeds every inventory meanwhile (`awaitsRestore`). An unknown (nil) list never
            // waits, since it may never come: it decides nothing, so every saved window is kept.
            guard inventory.initialRefreshComplete, !inventory.sessionPaused, inventory.liveWindows?.isEmpty != true else { return [] }
            pendingRestore = nil
            // Home frames are kept only for windows tracked under a real ID (synthetic IDs are session-only, 02-11), or
            // kept dormant because the CG list still has them (G-03-8).
            let real = Set(inventory.windows.filter { $0.idSource != .synthetic }.map(\.window.identity))
            // Only a window on a known Space that is not shown is a hidden-Space window. One AX does not list on a shown
            // Space is a hidden tab of a group now tracked under another member (CR-01) or an AX read that failed: it
            // waits like any unattached window (`isAlive` drops one on no Space). Unknown Spaces keep the G-03-8 rule.
            let shown = Set(displays.compactMap(\.currentSpaceID))
            let live = inventory.liveWindows?.filter { $0.spaces?.isDisjoint(with: shown) ?? true }
            homeFrames = restore.homeFrames.filter { home in real.contains(home.key) || live.map { LayoutRestore.isAlive(home.key, in: $0) } ?? true }
            // After a crash, stranded windows come on screen first, before any layout work (D-17).
            let rescued = launch == .normal ? [] : rescueStranded(desks: restore.world)
            inventory.windows = inventory.windows.map { windows[$0.window.identity] ?? $0 }
            let restored: (effects: [ArrangerEffect], unplaced: Int)
            var broughtBack: [WindowCommand] = []
            do throws(LayoutError) {
                restored = try reattach(restore, tracked: inventory.windows, live: live, holdingFrom: now)
                broughtBack = bringBackParked()
            } catch {
                unattached = (restore.world, restore.homeFrames, restore.wantedFrames, arrangement)
                restored = ([.fault("could not re-attach the saved layout; starting empty, keeping layout.json as it is: \(error)")], 0)
            }
            var effects: [ArrangerEffect] = (rescued.isEmpty ? [] : [.perform(rescued)]) + restored.effects
                + (broughtBack.isEmpty ? [] : [.perform(broughtBack)]) + regroupedLog(saved: restore.world)
            // Re-planned quietly: a window that lost its room still floats, but with no toast; only N2 says anything.
            effects += place(inventory).filter { if case .notice = $0 { false } else { true } }
            switch launch {
            case .normal: return effects
            case .recovery: return effects + [.notice(.crashRecovered(unplaced: restored.unplaced))]
            case .crashLoop: return effects + [.notice(.crashLoop)]
            case .unreadable: return effects
            }
        case .event(let event):
            // Until the saved layout is re-attached, the next complete inventory says everything an event would.
            guard pendingRestore == nil else { return [] }
            return handle(event, now: now)
        case .command(let command, let focused):
            // Never guess a display (T-04-12): camera commands arrive as `.camera`.
            if case .camera = command { return [.fault("camera command without a display")] }
            // Tab commands refuse with an announcement, not a bare beep (07 UI-SPEC Surface 7).
            if case .tabs(let tab) = command { return tabCommand(tab, focused: focused, via: .hotkey, ready: true, now: now) }
            guard isAvailable(command, focused: focused) else { return [.beep] }
            do throws(LayoutError) {
                switch (command, focused) {
                case (.dock, let window?): return try dock(window)
                case (.float, let window?): return try float(window)
                case (.undo, _): return try undo(focused)
                case (.focus(let edge), let window?): return try focusNeighbour(of: window, toward: edge)
                case (.finderSplit, _): return try finderSplit(focused, now: now)
                case (.moveOrSnap(let edge), let window?): return try moveOrSnap(window, toward: edge)
                case (.dockFourth(let slot, let axis), let window?): return try dockFourth(window, slot: slot, axis: axis)
                case (.swapPrevious, let window?): return try swapPrevious(window)
                case (.growTile, let window?): return try resize(window, by: Self.resizeStep)
                case (.shrinkTile, let window?): return try resize(window, by: -Self.resizeStep)
                case (.balanceSplit, let window?): return try editSplit(of: window) { tree, split throws(LayoutError) in try tree.balance(split: split) }
                case (.rotateSplit, let window?): return try editSplit(of: window) { tree, split throws(LayoutError) in try tree.rotate(split: split) }
                case (.flipSplit, let window?): return try editSplit(of: window) { tree, split throws(LayoutError) in try tree.flip(split: split) }
                case (.snap(let target), let window?): return try snap(window, to: target)
                case (.arrangeAll, _): return try arrangeAll(focused)
                case (.floatAll, _): return try floatAll(focused)
                case (.togglePause, _): return togglePause()
                case (.restoreAll, _): return try restoreAll()
                case (.toggleExcludeFrontmost, _): return [.fault("toggleExcludeFrontmost reached the Arranger; the shell handles it")]
                case (.camera, _): return [.fault("camera command without a display")]  // answered above
                case (.tabs, _): return [.fault("tab command reached the command switch")]  // answered above
                case (.dock, nil), (.float, nil), (.focus, nil), (.moveOrSnap, nil), (.dockFourth, nil), (.swapPrevious, nil), (.growTile, nil),
                    (.shrinkTile, nil), (.balanceSplit, nil), (.rotateSplit, nil), (.flipSplit, nil), (.snap, nil):
                    return [.beep]
                }
            } catch {
                return [.beep, .fault("\(command) of \(focused?.description ?? "no window") failed: \(error)")]
            }
        case .requeried(let revived, let states):
            do throws(LayoutError) {
                try LifecycleSync.applyRequeried(states, on: revived.key, world: &world, history: &history)
            } catch {
                return [.fault("could not apply re-queried states on \(revived.key): \(error)")] + replan()
            }
            return replan()
        case .tick:
            return tick(now: now)
        case .restore(var world, var homeFrames, var wantedFrames, let arrangement, var sets, var views, let bootChanged):
            var effects: [ArrangerEffect] = []
            if bootChanged {
                do throws(LayoutError) {
                    (world, homeFrames, wantedFrames, sets, views) = try LayoutRestore.retire(
                        world, homeFrames: homeFrames, wantedFrames: wantedFrames, sets: sets, views: views)
                    effects.append(.info("boot session changed: matching every saved window by hints"))
                } catch {
                    reattachFault = error  // never for a decoded World, but no old identity may re-attach: start empty, keep the file
                }
            }
            pendingRestore = (world, homeFrames, wantedFrames)
            camera.savedViews = SavedViews(views)
            self.arrangement = arrangement
            layoutSets = LayoutSets(sets)
            return effects
        case .displaysSettling:
            guard !settling else { return [] }
            preChangeWorld = world
            settling = true
            return hideHandles()
        case .displaysSettled(let id, let names, let inventory):
            return displaysSettled(id, names: names, inventory: inventory, now: now)
        case .setPaused(let reason, let on):
            let wasPaused = !pauseReasons.isEmpty
            if on { pauseReasons.insert(reason) } else { pauseReasons.remove(reason) }
            return on ? hideHandles() : wasPaused && pauseReasons.isEmpty ? resume() : []
        case .gap(let value):
            gap = value
            return replan()
        case .clearWaitingTiles:
            return clearWaitingTiles()
        case .dragToDock(let mode):
            dragToDock = mode
            return []
        case .newWindows(let mode):
            newWindows = mode
            return []
        case .pointer(let event):
            return pointer(event, now: now)
        case .dragFrame(let id, let frame):
            guard drag?.window.identity == id else { return [] }
            windows[id]?.frame = frame
            drag?.observe(frame, lastApplied: lastApplied[id])
            return follow(now: now)
        case .greenButton(let window):
            // The shell publishes no button for these, but a stale press must not act either (T-03-34).
            guard pauseReasons.isEmpty, let info = windows[window.identity], info.kind == .dockable, !info.isExcluded,
                deskKey(of: info.window) != nil
            else { return [] }
            return process(.command(isFloating(info.window) ? .dock : .float, focused: info.window), now: now)
        case .gapDrag(let handle, let delta, let ended):
            return gapDrag(handle, delta: delta, ended: ended)
        case .launch(let mode):
            launch = mode
            // No saved layout, but the first complete inventory still runs the restore path, so stranded windows are rescued.
            if mode == .unreadable { pendingRestore = (World(), [:], [:]) }
            // D-18: a crash loop starts paused; Resume clears it. Stranded windows still come on screen (UI-SPEC N3).
            guard mode == .crashLoop else { return [] }
            pauseReasons.insert(.crashLoop)
            return hideHandles()
        case .zoomEnabled(let on):
            return setZoomEnabled(on)
        case .zoomTo(let target, let uuid, let focus):
            return zoomTo(target, displayUUID: uuid, focus: focus)
        case .cameraSettle(let uuid, let moveID):
            return cameraSettle(displayUUID: uuid, moveID: moveID)
        case .camera(let command, let uuid, let focused, let pointer):
            return camera(command, displayUUID: uuid, focused: focused, pointer: pointer)
        case .tab(let action, let ready):
            return tab(action, ready: ready, now: now)
        case .closePrompt(let window, let showing):
            return closePrompt(window, showing: showing, now: now)
        }
    }

    /// What layout.json should hold now: while a restore waits, or after it failed, the saved layout itself, so a write
    /// then loses nothing.
    /// While displays settle, the World from before the change. Every tracked window's ref carries its current title
    /// (re-matching reads it, RESEARCH Pitfall 2); an untracked one keeps the title it was loaded with.
    public var snapshot: (
        world: World, homeFrames: [WindowIdentity: Rect], wantedFrames: [WindowIdentity: Rect], arrangement: ArrangementID, layoutSets: [LayoutSet],
        views: [SavedView]
    ) {
        let titles = windows.mapValues(\.window.titleHint)
        let sets = layoutSets.all.map { set in
            var set = set
            set.world = set.world.refreshingTitles(titles)
            return set
        }
        if let unattached {
            let views = heldViews(in: [unattached.world] + sets.map(\.world))
            return (unattached.world.refreshingTitles(titles), unattached.homeFrames, unattached.wantedFrames, unattached.arrangement, sets, views)
        }
        let saved = pendingRestore ?? (settling ? preChangeWorld ?? world : world, homeFrames, wantedFrames)
        return (saved.world.refreshingTitles(titles), saved.homeFrames, saved.wantedFrames, arrangement, sets, heldViews(in: [saved.world] + sets.map(\.world)))
    }

    /// Takes the displays, session state and windows of `inventory`. A Space lookup that answers 0 or switches off
    /// mid-session keeps each display's last shown Space, so the desks keyed by it are not stranded and no Space-less
    /// phantom desk appears (WR-01).
    private mutating func adopt(_ inventory: WindowInventory) {
        let previous = displays
        displays = inventory.displays.map { display in
            var display = display
            if display.currentSpaceID == nil { display.currentSpaceID = previous.first { $0.uuid == display.uuid }?.currentSpaceID }
            return display
        }
        forgetMoves(onDisplaysOtherThan: Set(displays.map(\.uuid)))
        sessionPaused = inventory.sessionPaused
        windows = Dictionary(inventory.windows.map { ($0.window.identity, $0) }, uniquingKeysWith: { $1 })
    }

    /// Ends settling (Pattern 7). The pre-change World is stored as the old arrangement's set unless nothing changed;
    /// a known arrangement's set goes through the launch re-attach; a new one keeps the World, so a vanished display's
    /// desks stay, dormant, and its windows float where macOS put them. No desk of an absent display is deleted.
    private mutating func displaysSettled(
        _ id: ArrangementID, names: [String: String], inventory: WindowInventory, now: ContinuousClock.Instant
    ) -> [ArrangerEffect] {
        let before = preChangeWorld ?? world
        let old = arrangement
        settling = false
        preChangeWorld = nil
        defer { userPlacedSinceSwitch = [] }
        // WR-09: the launch re-attach has not run yet. It runs first, under the saved arrangement, against these displays;
        // once it has, this settles from the saved arrangement to `id` (storing the saved layout, applying a known set).
        guard pendingRestore == nil else {
            let effects = process(.inventory(inventory), now: now)
            return pendingRestore == nil ? effects + displaysSettled(id, names: names, inventory: inventory, now: now) : effects
        }
        arrangement = id
        let uuids = inventory.displays.map(\.uuid)
        var effects: [ArrangerEffect] = []
        // CR-01: while the saved layout is unattached, layout.json still holds it and its sets: none is stored or taken.
        var decision = ArrangementSwitch.decide(from: old, to: id, sets: unattached == nil ? layoutSets : LayoutSets())
        if Set(uuids).count != uuids.count {
            // Identical monitors may share a UUID (Pitfall 13): never apply a stored set to an ambiguous arrangement.
            effects.append(.info("duplicate display UUID in \(uuids.sorted()); treated as a new arrangement"))
            decision = .new
        }
        if decision != .same, unattached == nil, !old.isUnknown, old != id { layoutSets.store(before, for: old, at: .now) }
        adopt(inventory)
        // Where each window on a desk of a display that is not connected now was: its display, for the float and N12.
        let present = Set(displays.map(\.uuid))
        var away: [WindowIdentity: String] = [:]
        for (key, desk) in world.desks where !present.contains(key.displayUUID) {
            for window in desk.tree.windows + desk.desktop.windows.map(\.window) { away[window.identity] = key.displayUUID }
        }
        switch decision {
        case .same:
            effects.append(.info("arrangement \(id.shortHash): \(uuids.count) displays, same"))
        case .new:
            effects.append(.info("arrangement \(id.shortHash): \(uuids.count) displays, new"))
        case .known(let set):
            effects.append(.info("arrangement \(id.shortHash): \(uuids.count) displays, known"))
            _ = layoutSets.take(id)
            let shown = Set(displays.compactMap(\.currentSpaceID))
            let live = inventory.liveWindows?.filter { $0.spaces?.isDisjoint(with: shown) ?? true }
            do throws(LayoutError) {
                let merged = try Self.merged(set.world, current: world, keeping: userPlacedSinceSwitch)
                effects += try reattach((merged, homeFrames, wantedFrames), tracked: inventory.windows, live: live, holdingFrom: now, closingShown: true).effects
            } catch {
                layoutSets.store(set.world, for: id, at: set.lastUsed)
                effects.append(.fault("could not apply the layout set for arrangement \(id.shortHash); keeping the current layout: \(error)"))
            }
        }
        var claimed = inventory
        claimed.windows = inventory.windows.map(claim)
        for info in claimed.windows { windows[info.window.identity] = info }
        effects += place(claimed)
        if decision == .new { effects += cascadeFloated(from: away, names: names) }
        return effects + [.save(.debounced)]
    }

    /// D-10: the windows of a vanished display that now float on a connected one are cascaded from the top-left of
    /// that display's visible frame, at their own sizes, clamped on screen (a frame transform, no undo step), then N12
    /// says so, once, when at least one floated.
    private mutating func cascadeFloated(from away: [WindowIdentity: String], names: [String: String]) -> [ArrangerEffect] {
        var floated: [DeskKey: [WindowRef]] = [:]
        for id in away.keys {
            guard let info = windows[id], !info.isExcluded, let key = deskKey(of: info.window), world[key]?.desktop.contains(info.window) == true,
                displays.contains(where: { $0.uuid == key.displayUUID })
            else { continue }
            floated[key, default: []].append(info.window)
        }
        guard !floated.isEmpty else { return [] }
        var faults: [ArrangerEffect] = []
        for (key, refs) in floated.sorted(by: { $0.key < $1.key }) {
            guard let display = display(for: key) ?? displays.first(where: { $0.uuid == key.displayUUID }), let desk = world[key] else { continue }
            let refs = refs.sorted { $0.identity < $1.identity }
            let area = display.visibleFrame
            let frames = ArrangementSwitch.cascade(
                frames: refs.map { desk.desktop.frame(of: $0) ?? area }, from: Point(x: area.minX, y: area.minY), in: area)
            do throws(LayoutError) {
                try world.reflow(key) { desk, _ throws(LayoutError) in
                    for (window, frame) in zip(refs, frames) { try desk.desktop.setFrame(frame, for: window) }
                }
                for (window, frame) in zip(refs, frames) { wantedFrames[window.identity] = frame }
            } catch {
                faults.append(.fault("could not cascade the windows floated on \(key): \(error)"))
            }
        }
        let gone = Set(floated.values.joined().compactMap { away[$0.identity] }).sorted()
        let count = floated.values.map(\.count).reduce(0, +)
        return faults + replan() + [
            .info("displays \(gone) gone: \(dormantDeskCount) desks dormant, \(count) windows floated"),
            .notice(.displaysDisconnected(names: gone.map { names[$0] ?? $0 }, windows: count)),
        ]
    }

    /// Desks whose display is not connected (UI-SPEC Debug S4).
    public var dormantDeskCount: Int { world.desks.keys.filter { key in !displays.contains { $0.uuid == key.displayUUID } }.count }
    /// The distinct displays those dormant desks belong to.
    public var awayDisplayCount: Int { Set(world.desks.keys.map(\.displayUUID)).subtracting(displays.map(\.uuid)).count }

    /// User action wins (OVER-06): each desk of `current` holding a window in `placed` is kept, less its other windows
    /// that `stored` puts on another desk; every other desk is `stored`'s, less the windows the kept desks hold. Windows
    /// leave through the close path, so trees normalise. The ID source is the larger one, so no NodeID is minted twice.
    static func merged(_ stored: World, current: World, keeping placed: Set<WindowIdentity>) throws(LayoutError) -> World {
        func held(_ desk: Desk) -> [WindowRef] { desk.tree.windows + desk.desktop.windows.map(\.window) }
        let kept = Set(current.desks.filter { held($0.value).contains { placed.contains($0.identity) } }.keys)
        var stored = stored, current = current, throwaway = UndoHistory()
        let nowhere = DeskKey(displayUUID: "", spaceID: nil)
        for key in kept.sorted() {
            for window in current[key].map(held) ?? [] where !placed.contains(window.identity) {
                if let home = stored.desks.first(where: { $0.value.contains(window) })?.key, home != key {
                    try current.apply(.closed, for: window, on: nowhere, history: &throwaway)
                }
            }
            for window in current[key].map(held) ?? [] {
                if let home = stored.desks.first(where: { $0.value.contains(window) })?.key, !kept.contains(home) {
                    try stored.apply(.closed, for: window, on: nowhere, history: &throwaway)
                }
            }
        }
        var desks = stored.desks
        for key in kept { desks[key] = current[key] }
        return try World(ids: IDSource(next: max(stored.ids.next, current.ids.next)), desks: desks)
    }

    private static func floatingGroupMembers(_ world: World) -> Set<WindowIdentity> {
        Set(world.desks.values.flatMap { $0.desktop.groups.flatMap { $0.members.map(\.identity) } })
    }

    private static func isUserEdit(_ input: ArrangerInput) -> Bool {
        switch input {
        case .command, .pointer, .greenButton: true
        default: false
        }
    }

    /// Windows whose desk or tile differs between two Worlds: a dock, float, move, snap, swap or drop placed them.
    private static func placementChanges(from old: World, to new: World) -> Set<WindowIdentity> {
        func slots(_ world: World) -> [WindowIdentity: Slot] {
            var slots: [WindowIdentity: Slot] = [:]
            for (key, desk) in world.desks {
                for window in desk.tree.windows { slots[window.identity] = Slot(desk: key, leaf: desk.tree.leaf(containing: window)) }
                for floating in desk.desktop.windows { slots[floating.window.identity] = Slot(desk: key, leaf: nil) }
            }
            return slots
        }
        let before = slots(old)
        return Set(slots(new).filter { before[$0.key] != $0.value }.keys)
    }

    private struct Slot: Equatable {
        let desk: DeskKey
        /// nil on the Desktop layer.
        let leaf: NodeID?
    }

    /// The layout wins over where macOS left a window during a display change: a window a desk on a connected display
    /// holds is reported on that display, so `rehome` keeps it there and the plan writes its tile (D-10).
    private func claim(_ info: WindowInfo) -> WindowInfo {
        guard let key = deskKey(of: info.window), key.displayUUID != info.displayUUID, displays.contains(where: { $0.uuid == key.displayUUID })
        else { return info }
        var info = info
        info.displayUUID = key.displayUUID
        return info
    }

    /// A saved layout is waiting for a usable inventory: the shell feeds it every inventory until then.
    public var awaitsRestore: Bool { pendingRestore != nil }

    /// Adds every window of `inventory` no desk holds, after re-homing the ones whose display or Space changed.
    private mutating func place(_ inventory: WindowInventory) -> [ArrangerEffect] {
        var faults: [ArrangerEffect] = []
        if !reportedSpacesOff, !displays.isEmpty, displays.allSatisfy({ $0.currentSpaceID == nil }) {
            reportedSpacesOff = true
            faults.append(.info("Spaces lookup off: one layout per display"))
        }
        // A display change arrives as a new inventory: windows whose display or Space changed are re-homed first.
        for info in inventory.windows {
            do throws(LayoutError) {
                try release(info)
                // The pressed window may be crossing displays; where it lands is decided at mouse-up (WR-04).
                if drag?.window != info.window { try rehome(info) }
                try admit(info)
            } catch { faults.append(.fault("could not add \(info.window): \(error)")) }
        }
        return faults + replan()
    }

    /// Replaces the World with the saved one re-attached by identity (SAFE-06), with each window's real state and, for
    /// a present floating window, its real frame. Each docked window's current frame counts as already requested, so
    /// only tiles more than 0.5 pt off are written. Undo history starts empty (session-only). A window whose real state
    /// or frame cannot be applied keeps its saved one. Throws, changing nothing but the history, if the saved layout cannot
    /// be re-attached at all. `unplaced` counts the tracked windows the saved layout did not hold. Unmatched saved windows
    /// wait as placeholders from `now` (D-12). With `closingShown` (a stored arrangement, not a launch), only those on a desk
    /// not showing do, as AX can't list them there (D-12b); the rest close unless they already wait.
    private mutating func reattach(
        _ restore: (world: World, homeFrames: [WindowIdentity: Rect], wantedFrames: [WindowIdentity: Rect]), tracked: [WindowInfo], live: [CGWindowEntry]?,
        holdingFrom now: ContinuousClock.Instant, closingShown: Bool = false
    ) throws(LayoutError) -> (effects: [ArrangerEffect], unplaced: Int) {
        if let fault = reattachFault {
            reattachFault = nil
            throw fault
        }
        history = UndoHistory()
        let reattached = try LayoutRestore.reattach(
            restore.world, tracked: tracked, live: live, savedFrames: savedFrames(restore.world), shownDesks: shownDesks)
        var candidate = reattached.world
        for match in reattached.matches {
            let display = tracked.first { $0.window == match.window }?.displayUUID
            if let desk = candidate.desks.first(where: { $0.value.contains(match.window) })?.key, display != desk.displayUUID {
                placeholders.arriving.insert(match.window.identity)
            }
        }
        var holding = reattached.waiting
        if closingShown {
            let new = reattached.waiting.filter { placeholders.table[$0.identity] == nil }
            holding = new.filter { window in candidate.desks.contains { !shownDesks.contains($0.key) && $0.value.contains(window) } }
            for window in new where !holding.contains(window) {
                try candidate.apply(.closed, for: window, on: DeskKey(displayUUID: "", spaceID: nil), history: &history)
            }
        }
        var seeded: [WindowIdentity: Rect] = [:]
        var faults = Self.matchLog(reattached, saved: restore.world)
        // Through a throwaway identity first, as LayoutRestore does: a returning window can carry another saved one's ID.
        let parked = reattached.matches.indices.map { WindowIdentity(windowID: UInt32($0), pid: -1, bundleID: "") }
        for (match, temp) in zip(reattached.matches, parked) { remapViews(from: match.saved.identity, to: temp) }
        for (match, temp) in zip(reattached.matches, parked) { remapViews(from: temp, to: match.window.identity) }
        // Saved wanted frames come back for the windows the World still holds; a stranded one is dropped (T-03-74). A
        // match's follow it, as a rekey's do (WR-10). All in one pass, as a returning window can carry another saved one's ID.
        let matchedSaved = Set(reattached.matches.map(\.saved.identity))
        var wanted = restore.wantedFrames.filter { id, frame in
            !matchedSaved.contains(id) && candidate.desks.values.contains { $0.contains(WindowRef(identity: id)) } && !Recovery.isStranded(frame, displays: displays)
        }
        homeFrames = homeFrames.filter { !matchedSaved.contains($0.key) }
        for id in matchedSaved { wantedFrames[id] = nil }
        for match in reattached.matches {
            if let frame = restore.wantedFrames[match.saved.identity], !Recovery.isStranded(frame, displays: displays) { wanted[match.window.identity] = frame }
            if let frame = restore.homeFrames[match.saved.identity] { homeFrames[match.window.identity] = frame }
        }
        for info in tracked where info.state != .closed {
            guard let key = candidate.desks.first(where: { $0.value.contains(info.window) })?.key, let desk = candidate[key] else {
                continue
            }
            do throws(LayoutError) {
                if desk.state(of: info.window) != info.state { try candidate.apply(info.state, for: info.window, on: key, history: &history) }
                if !desk.desktop.contains(info.window) {
                    seeded[info.window.identity] = info.frame
                } else if info.state == .present {
                    if movedWhileOff(info, saved: desk) { wanted[info.window.identity] = info.frame }
                    try candidate.recordFloatingFrame(info.frame, for: info.window)
                }
            } catch {
                faults.append(.fault("kept the saved state and frame of \(info.window): \(error)"))  // WR-04
            }
        }
        world = candidate
        lastRequested = seeded
        wantedFrames.merge(wanted) { $1 }
        for desk in world.desks.values {
            for floating in desk.desktop.windows where wantedFrames[floating.window.identity] == nil {
                wantedFrames[floating.window.identity] = floating.frame
            }
        }
        if !holding.isEmpty { faults += holdAtLaunch(holding, tracked: tracked, unplaced: reattached.unplaced, ties: reattached.ties, now: now) }
        return (faults, reattached.unplaced.count)
    }

    /// Each saved window's frame for the matcher: a docked one's home-view tile on its desk's display (the frame a clean
    /// quit left it at; a parked frame means nothing, RESEARCH Pitfall 9), a floating one's saved frame.
    func savedFrames(_ saved: World) -> [WindowIdentity: Rect] {
        var frames: [WindowIdentity: Rect] = [:]
        for (key, desk) in saved.desks {
            // No display or no plan: no frame hint, which only means frame scores nothing.
            if let area = displays.first(where: { $0.uuid == key.displayUUID })?.visibleFrame,
                let plan = try? Planner.plan(desk: desk, area: area, gap: gap, mins: minimums)
            {
                for (window, frame) in plan.frames { frames[window.identity] = frame }
            }
            for floating in desk.desktop.windows { frames[floating.window.identity] = floating.frame }
        }
        return frames
    }

    /// One info line per hint match, per tie and per bundle with saved windows left unmatched; identities only, never
    /// titles (D-10).
    private static func matchLog(
        _ result: (world: World, waiting: [WindowRef], removed: [WindowRef], unplaced: [WindowInfo], matches: [HintMatcher.Match], ties: [HintMatcher.Tie]),
        saved: World
    ) -> [ArrangerEffect] {
        func tile(_ window: WindowRef) -> String {
            saved.desks.values.lazy.compactMap { $0.tree.leaf(containing: window) }.first.map { "\($0)" } ?? "Desktop"
        }
        let tied = Set(result.ties.flatMap(\.saved))
        let unmatched = Dictionary(grouping: (result.waiting + result.removed).filter { !tied.contains($0) }, by: \.bundleID)
        return result.matches.map { .info("match \($0.window.bundleID): window \($0.window.windowID) -> tile \(tile($0.saved)), score \($0.score)") }
            + result.ties.map { tie in
                let windows = tie.candidates.map { "\($0.windowID)" }.joined(separator: " and ")
                let tiles = tie.saved.map(tile).joined(separator: ", ")
                return .info("match \(tie.saved[0].bundleID): tie at \(tie.score) between windows \(windows); tile \(tiles) waits, windows float")
            }
            + unmatched.sorted { $0.key < $1.key }.map { .info("match \($0.key): \($0.value.count) unmatched, below threshold") }
    }

    /// Moves every stranded window Transom may move (tracked, dockable, present, not excluded) back on screen: its home
    /// frame clamped on screen, else centred on its display, shrunk to fit (`Recovery.destination`). Its display is the
    /// one its desk in `desks` is on, else the one it is nearest. Runs while paused (UI-SPEC N3, SAFE-03). Returns the
    /// moves in identity order; the caller sends them before any layout work. `spared` windows stay where they are.
    mutating func rescueStranded(desks: World, sparing spared: Set<WindowIdentity> = []) -> [WindowCommand] {
        var moves: [WindowCommand] = []
        for info in windows.values.sorted(by: { $0.window.identity < $1.window.identity })
        where info.kind == .dockable && !info.isExcluded && info.state == .present && !spared.contains(info.window.identity)
            && Recovery.isStranded(info.frame, displays: displays)
        {
            let id = info.window.identity
            let uuid = desks.desks.first { $0.value.contains(info.window) }?.key.displayUUID ?? info.displayUUID
            guard let display = displays.first(where: { $0.uuid == uuid }) ?? displays.first else { continue }
            let frame = Recovery.destination(for: info.frame, home: homeFrames[id], display: display)
            windows[id]?.frame = frame
            windows[id]?.displayUUID = display.uuid
            lastRequested[id] = nil  // a docked one goes back to its tile at the next plan
            // A stranded wanted frame would pull the window back off screen at the next plan (T-03-72).
            if let wanted = wantedFrames[id], Recovery.isStranded(wanted, displays: displays) { wantedFrames[id] = frame }
            parkRequested.remove(id)
            moves.append(.setFrame(info.window, frame))
        }
        return moves
    }

    /// The one-shot return of floating windows a hidden Desktop tile parked in a layout.json of schema 3 or older (8.1.1
    /// D-02): each one still at its park rect, with a home frame, goes to that frame clamped onto its desk's display. An OS
    /// fact, so no undo step. One-shot because `handle` clears floater home frames on every desk with no hidden Desktop.
    mutating func bringBackParked() -> [WindowCommand] {
        var moves: [WindowCommand] = []
        for info in windows.values.sorted(by: { $0.window.identity < $1.window.identity })
        where info.kind == .dockable && info.state == .present && !info.isExcluded && isFloating(info.window) && !isHiddenTab(info.window)
            && Recovery.isStranded(info.frame, displays: displays)
        {
            let id = info.window.identity
            // shortcut: a still-hidden Desktop keeps its parks until 08.1.1-13 removes hiding.
            guard let home = homeFrames[id], let key = deskKey(of: info.window), world[key]?.tree.isDesktopHidden != true,
                let display = displays.first(where: { $0.uuid == key.displayUUID })
            else { continue }
            let frame = Recovery.destination(for: info.frame, home: home, display: display)
            guard (try? world.recordFloatingFrame(frame, for: info.window)) != nil else { continue }
            windows[id]?.frame = frame
            wantedFrames[id] = frame
            homeFrames[id] = nil
            moves.append(.setFrame(info.window, frame))
        }
        return moves
    }

    /// The desk holding `window`, docked or floating.
    public func deskKey(of window: WindowRef) -> DeskKey? {
        world.desks.first { $0.value.contains(window) }?.key
    }

    /// `availability` with access granted: the Arranger only runs once tracking has started.
    public func isAvailable(_ command: Command, focused: WindowRef?) -> Bool {
        availability(command, context: CommandContext(focused: focused, ready: true))
    }

    /// Whether `command` can act now (UI-SPEC Surface 1 disabled-state rules): the one rule that greys menu items and
    /// makes a refused hotkey beep. Window-scoped commands need a focused, trackable, dockable window of an app that
    /// is not excluded; nothing in the Arrange section acts without Accessibility access.
    public func availability(_ command: Command, context: CommandContext) -> Bool {
        // Exclusions stay enabled while paused or without access (UI-SPEC); the shell checks the frontmost app.
        if command == .toggleExcludeFrontmost { return true }
        guard context.ready else { return false }
        // Paused, only Resume acts; Stage Manager's pause ends through its conflict item, not Resume.
        if command == .togglePause { return pauseReasons != [.stageManager] }
        if command == .restoreAll { return true }  // the way back, so it works while paused (UI-SPEC Surface 1 row 21)
        // The overview moves no window and needs no pointer display, so it works while paused (06 UI-SPEC Surface 1).
        if command == .camera(.overview) { return camera.enabled }
        guard pauseReasons.isEmpty else { return false }
        let focused = context.focused
        let trackable = focused.flatMap { windows[$0.identity] }.map { $0.kind == .dockable && !$0.isExcluded } ?? false
        switch command {
        case .dock:
            guard trackable, let focused, windows[focused.identity]?.state == .present else { return false }
            return world.desks.values.contains { $0.desktop.contains(focused) && $0.state(of: focused) == .present }
        case .float:
            guard trackable, let focused else { return false }
            return world.desks.values.contains { $0.tree.state(of: focused) != nil }
        case .undo:
            return targetKey(focused).map { history.depth(for: $0) > 0 } ?? false
        case .focus:
            return trackable && focused.flatMap(deskKey(of:)) != nil
        case .moveOrSnap, .dockFourth:
            // Docked or floating alike; the menu shows the pair's matching item (`isFloating`).
            guard trackable, let focused, let key = deskKey(of: focused) else { return false }
            return world[key]?.state(of: focused) == .present
        case .swapPrevious:
            return trackable && focused.flatMap(previousDocked(before:)) != nil
        case .growTile, .shrinkTile, .balanceSplit, .rotateSplit, .flipSplit:
            return trackable && focused.flatMap(parentSplit(of:)) != nil
        case .arrangeAll, .floatAll:
            return targetKey(focused) != nil  // enabled with no focused window (UI-SPEC disabled-state rules)
        case .snap:
            guard trackable, let focused, let key = deskKey(of: focused), let desk = world[key] else { return false }
            return desk.desktop.contains(focused) && desk.state(of: focused) == .present && desk.tree.isDesktopHidden != true
        case .finderSplit:
            return targetKey(focused).flatMap(display(for:)) != nil
        case .togglePause, .toggleExcludeFrontmost, .restoreAll:
            return true  // answered above
        case .camera(let command):
            return cameraAvailable(command, context: context)
        case .tabs:
            return !sessionPaused && focused.flatMap(tabGroup(holding:)) != nil
        }
    }

    /// Whether `window` floats on a desk's Desktop layer: which of Move Window or Snap Floating Window the menu enables.
    public func isFloating(_ window: WindowRef?) -> Bool {
        window.map { window in world.desks.values.contains { $0.desktop.contains(window) } } ?? false
    }

    /// The focused window's desk or, with none focused (or one on no desk), the main display's visible desk.
    func targetKey(_ focused: WindowRef?) -> DeskKey? {
        focused.flatMap(deskKey(of:)) ?? displays.first.map(Self.key)
    }

    // MARK: Events

    private mutating func handle(_ event: WindowEvent, now: ContinuousClock.Instant) -> [ArrangerEffect] {
        var subject: WindowIdentity?
        var hidden: [ArrangerEffect] = []
        var faults: [ArrangerEffect] = []
        var selected: [ArrangerEffect] = []
        var dissolved: [ArrangerEffect] = []
        var filled = false
        do throws(LayoutError) {
            switch event {
            case .windowCreated(let info), .windowChanged(let info):
                if case .windowCreated = event, windows[info.window.identity] == nil, deskKey(of: info.window) != nil {
                    placeholders.table[info.window.identity] = nil  // the very window came back
                    do throws(LayoutError) { try wakeDormant(info) } catch {
                        faults.append(.fault("kept the saved state and frame of \(info.window): \(error)"))
                    }
                }
                // A title decides matches and is no World change, so it saves itself, and `world` keeps the latest real one (WR-07).
                let title = info.window.titleHint
                if !title.isEmpty, title != windows[info.window.identity]?.window.titleHint, deskKey(of: info.window) != nil {
                    world = world.refreshingTitles([info.window.identity: title])
                    faults.append(.save(.debounced))
                }
                windows[info.window.identity] = info
                subject = info.window.identity
                if case .windowCreated = event { noteCreated(info, now: now) }
                // Before `admit`, so a returning window never shows a hidden Desktop on its way to its tile (D-31).
                if placeholders.fresh.contains(info.window.identity) {
                    faults += fillPlaceholders(of: info.window.bundleID)
                    filled = !placeholders.fresh.contains(info.window.identity)
                }
            case .windowRekeyed(let from, let to):
                windows[from.identity] = nil
                windows[to.window.identity] = to
                lastRequested[to.window.identity] = lastRequested.removeValue(forKey: from.identity)
                lastApplied[to.window.identity] = lastApplied.removeValue(forKey: from.identity)
                lastCorrection[to.window.identity] = lastCorrection.removeValue(forKey: from.identity)
                if pendingCorrections.remove(from.identity) != nil { pendingCorrections.insert(to.window.identity) }
                refusalRetried[to.window.identity] = refusalRetried.removeValue(forKey: from.identity)
                if parkRequested.remove(from.identity) != nil { parkRequested.insert(to.window.identity) }
                if let home = homeFrames.removeValue(forKey: from.identity) { homeFrames[to.window.identity] = home }
                if let wanted = wantedFrames.removeValue(forKey: from.identity) { wantedFrames[to.window.identity] = wanted }
                if let wanted = undockedWanted.removeValue(forKey: from.identity) { undockedWanted[to.window.identity] = wanted }
                if tabs.pendingReveal?.revealed == from { tabs.pendingReveal?.revealed = to.window }
                if tabs.pendingReveal?.previous == from { tabs.pendingReveal?.previous = to.window }
                if heldAdmits.remove(from.identity) != nil { heldAdmits.insert(to.window.identity) }
                if awaitingFit.remove(from.identity) != nil { awaitingFit.insert(to.window.identity) }
                focusOrder = focusOrder.map { $0 == from.identity ? to.window.identity : $0 }
                remapViews(from: from.identity, to: to.window.identity)
                if placeholders.arriving.remove(from.identity) != nil { placeholders.arriving.insert(to.window.identity) }
                subject = to.window.identity
            case .windowMoved(let window, let frame), .windowResized(let window, let frame):
                windows[window.identity]?.frame = frame
                return try moved(window, to: frame, now: now)
            case .frameApplied(let window, let requested, let actual):
                lastApplied[window.identity] = actual
                placeholders.arriving.remove(window.identity)
                let t = MinimumSizeLearner.tolerance
                if actual.width <= requested.width + t, actual.height <= requested.height + t { awaitingFit.remove(window.identity) }
                if let shown = revealed(window, actual: actual, now: now) { return shown }
                return retryRefusal(window, requested: requested, actual: actual, now: now)
            case .windowStateChanged(let window, let state):
                if state == .closed || state == .absent { suppressFocus(ofGroupHolding: window, now: now) }
                if state == .absent { try selectNeighbour(ofAbsent: window) } else { tabs.minimizing.remove(window.identity) }
                if state == .closed { forget(window) } else { windows[window.identity]?.state = state }
                subject = window.identity
            case .windowDestroyed(let window):
                suppressFocus(ofGroupHolding: window, now: now)
                if let held = try holdForQuit(window) {
                    let collapsible = camera.collapsible.contains(window.identity)
                    let wanted = wantedFrames[window.identity], home = homeFrames[window.identity]
                    forget(window)
                    if collapsible { camera.collapsible.insert(window.identity) }  // its block keeps its share, as its minimum does
                    // For the window that fills its tile (WR-10).
                    wantedFrames[window.identity] = wanted
                    homeFrames[window.identity] = home
                    return faults + held + replan()
                }
                forget(window)
            case .sessionPaused(let paused):
                sessionPaused = paused
                // The switch loses the mouse-up, and the strip would stay on until the next press (WR-04).
                if paused { hidden += abandonDrag() }
            case .spaceChanged(let uuid, let spaceID):
                // Only the shown Space's desk is planned; the one left keeps its layout untouched (D-25).
                if let i = displays.firstIndex(where: { $0.uuid == uuid }), let spaceID { displays[i].currentSpaceID = spaceID }  // WR-01
                // The old Space's handles go first; the re-plan below shows the new Space's (UI-SPEC Surface 3).
                if shownHandles[uuid]?.isEmpty == false {
                    shownHandles[uuid] = []
                    hidden = [.gapHandles([], displayUUID: uuid)]
                }
            case .windowFocused(let window):
                focusOrder.removeAll { $0 == window.identity }
                focusOrder.insert(window.identity, at: 0)
                // D-08: a hidden member is selected before the widen below, which then sees the group's leaf.
                selected = activated(window, now: now)
                if selected.isEmpty { selected = raisedStrip(of: window) }
            case .appTerminated(let pid):
                // Its tracked windows are still in `windows` here; on their own windowDestroyed the docked ones wait (D-12a).
                // Dormant windows get no windowDestroyed, so the docked ones wait now, and a floater closes (D-12b).
                let dormant = dormantWindows.filter { $0.pid == pid } + placeholders.table.values.filter { $0.origin == .leftCGList && $0.ref.pid == pid }.map(\.ref)
                if let bundle = windows.values.first(where: { $0.window.pid == pid })?.window.bundleID ?? dormant.first?.bundleID {
                    placeholders.quitting[pid] = (bundle, now)
                }
                for window in dormant { faults += try holdForQuit(window) ?? [] }
                faults += closeDormant { $0.pid == pid }
            case .liveWindowsChanged:
                return []  // the inventory the shell feeds next prunes
            case .appLaunched(_, let bundleID):
                placeholders.restartLaunchWait(of: bundleID, now: now)
            case .appResponsiveness, .displaysChanged:
                break
            }
            let leaving: (group: TabGroupRef, window: WindowRef)? = switch event {
            case .windowDestroyed(let window), .windowStateChanged(let window, .closed): tabGroup(holding: window).map { ($0, window) }
            default: nil
            }
            _ = try LifecycleSync.handle(event, world: &world, history: &history)
            if let leaving { dissolved = self.dissolved(leaving.group, losing: leaving.window) }
            if case .windowChanged(let info) = event {
                faults += try settleAutoTile(info)
                try release(info)
                // The pressed window may be crossing displays; where it lands is decided at mouse-up.
                if drag?.window != info.window { try rehome(info) }
            }
            // A window that just became dockable, present or known floats on its display's Desktop (D-24). A new one may
            // dock first, after re-matching and before `admit` can show a hidden Desktop (D-05, D-31).
            if let subject, let info = windows[subject] {
                if case .windowCreated = event, !filled { faults += autoTile(info, now: now) }
                try admit(info)
            }
        } catch {
            return [.fault("ignored an event: \(error)")]
        }
        // CONTEXT E: focus outside the view widens the camera.
        let widened = if case .windowFocused(let window) = event { widen(toShow: window, new: false) } else { [ArrangerEffect]() }
        guard case .windowCreated(let info) = event, !filled else {
            return faults + hidden + selected + dissolved + widened + replan() + closeProgress(now: now)
        }
        do throws(LayoutError) {
            let taken = try takeFinderWindow(info, now: now)
            return faults + taken + widen(toShow: info.window, new: true) + replan()
        } catch {
            return faults + [.fault("could not dock the new Finder window: \(error)")] + replan()
        }
    }

    /// Re-attaches a saved window the restore kept dormant (its Space was not shown, G-03-8) as the restore does for a
    /// tracked one: its real state, then its real frame counted as already requested if docked, or recorded if
    /// floating, then re-homed. The `admit` and re-plan that follow do the rest, so only a changed tile is written.
    private mutating func wakeDormant(_ info: WindowInfo) throws(LayoutError) {
        guard let key = deskKey(of: info.window), let desk = world[key] else { return }
        if desk.state(of: info.window) != info.state { try world.apply(info.state, for: info.window, on: key, history: &history) }
        if !desk.desktop.contains(info.window) {
            lastRequested[info.window.identity] = info.frame
        } else if info.state == .present, !Recovery.isStranded(info.frame, displays: displays) {
            // A parked or stranded frame never replaces the desk's: the re-plan moves the window back there (CR-02).
            try world.recordFloatingFrame(info.frame, for: info.window)
            if movedWhileOff(info, saved: desk) { wantedFrames[info.window.identity] = info.frame }
        }
        try release(info)  // its app was excluded while it was dormant (WR-02, D-29)
        try rehome(info)
    }

    /// A present floater whose real frame is on screen and more than 2 pt off its saved floating frame: the user moved
    /// it while Transom was not running, so its real frame is what it wants (T-03-74).
    private func movedWhileOff(_ info: WindowInfo, saved desk: Desk) -> Bool {
        guard info.state == .present, !Recovery.isStranded(info.frame, displays: displays),
            let saved = desk.desktop.frame(of: info.window)
        else { return false }
        return !Self.near(info.frame, saved, within: 2)
    }

    /// Saved windows a desk holds that the window system does not track: kept at the restore because the CG list still
    /// had them (G-03-8), until their first windowCreated.
    public var hasDormantWindows: Bool { !dormantWindows.isEmpty }

    private var dormantWindows: [WindowRef] {
        world.desks.values.flatMap { $0.tree.windows + $0.desktop.windows.map(\.window) }
            .filter { windows[$0.identity] == nil && placeholders.table[$0.identity] == nil }.sorted { $0.identity < $1.identity }
    }

    /// Closes the dormant windows `predicate` picks, in identity order, through the OS-fact close path any closed window
    /// takes: no undo step, purged from the snapshots. Returns a fault per window that could not be closed.
    private mutating func closeDormant(where predicate: (WindowRef) -> Bool) -> [ArrangerEffect] {
        var faults: [ArrangerEffect] = []
        for window in dormantWindows where predicate(window) {
            forget(window)
            do throws(LayoutError) {
                _ = try LifecycleSync.handle(.windowDestroyed(window), world: &world, history: &history)
            } catch {
                faults.append(.fault("could not prune the closed window \(window): \(error)"))
            }
        }
        return faults
    }

    mutating func forget(_ window: WindowRef) {
        windows[window.identity] = nil
        lastRequested[window.identity] = nil
        lastApplied[window.identity] = nil
        lastCorrection[window.identity] = nil
        pendingCorrections.remove(window.identity)
        refusalRetried[window.identity] = nil
        parkRequested.remove(window.identity)
        homeFrames[window.identity] = nil
        wantedFrames[window.identity] = nil
        awaitingFit.remove(window.identity)
        undockedWanted[window.identity] = nil
        camera.collapsible.remove(window.identity)
        camera.unparkedNew.remove(window.identity)
        placeholders.arriving.remove(window.identity)
        focusOrder.removeAll { $0 == window.identity }
        tabs.minimizing.remove(window.identity)
        // The model picks the group's selection when a member goes; nothing is left to wait for.
        if tabs.pendingReveal?.revealed == window || tabs.pendingReveal?.previous == window { tabs.pendingReveal = nil }
    }

    // MARK: Moves

    /// A window moved or resized. Within 2 pt of Transom's last read-back (or, for a floating window, of its last request
    /// or at any point of a boundary drag: an app that applies it late) it is Transom's own write coming back: a floating window's frame is still recorded as
    /// a fact, and nothing is answered. Otherwise a floating window's frame is recorded (TILE-07, no undo step) and
    /// becomes its wanted frame, even while paused, and is never moved (D-05); a docked
    /// window goes back to its tile, at most once per second (T-03-13). There is no pointer state yet, so every move
    /// counts as finished; plan 10 adds drag sessions so a user dragging a docked window is never fought.
    private mutating func moved(_ window: WindowRef, to frame: Rect, now: ContinuousClock.Instant) throws(LayoutError) -> [ArrangerEffect] {
        // The pressed window is never answered while the button is down; mouse-up decides (D-01).
        if drag?.window == window {
            drag?.observe(frame, lastApplied: lastApplied[window.identity])
            return follow(now: now)
        }
        guard let key = deskKey(of: window), let desk = world[key] else { return [] }
        // A parked sliver is off its tile on purpose: neither recorded nor corrected (RESEARCH Pitfall 1).
        guard !parkRequested.contains(window.identity) else { return [] }
        let floating = desk.desktop.contains(window)
        // A floating group's hidden member is parked or about to be: its reports never move the group (Pitfall 5).
        if floating, let group = desk.desktop.group(containing: window), group.members[group.selected] != window { return [] }
        if floating { try world.recordFloatingFrame(frame, for: window) }
        // A floater's frame during a boundary drag is Transom's clamp or the app's late answer to it: the mouse holds the drag.
        let own = [lastApplied[window.identity], floating ? lastRequested[window.identity] : nil]
            .contains { $0.map { Self.near($0, frame, within: 2) } ?? false } || (floating && (liveGap != nil || drag?.kind == .resize))
        if floating, !own {
            wantedFrames[window.identity] = frame
            // Once the window has been elsewhere, Transom's last read-back is history: a move back onto it is not Transom's (CR-01).
            lastApplied[window.identity] = nil
        }
        guard pauseReasons.isEmpty, !settling else { return [] }  // paused or settling: the fact is recorded, nothing is answered (D-23)
        guard windows[window.identity]?.isExcluded != true else { return [] }  // never clamped or corrected (D-29)
        if own { return [] }
        if floating { return replan() }
        guard desk.tree.state(of: window) == .present else { return [] }
        if let tile = lastRequested[window.identity], Self.near(tile, frame, within: 2) { return [] }
        if let last = lastCorrection[window.identity], now < last + Self.correctionInterval {
            pendingCorrections.insert(window.identity)
            return nextWake.map { [.wake(at: $0)] } ?? []
        }
        return correct([window.identity], now: now)
    }

    /// A docked window that refused its current tile by more than the learner's margin gets that tile once more after
    /// `correctionInterval`, through the correction path: a window already at its minimum is learned only from such a
    /// repeat (G-03-6). Overflow within the margin is tolerated (MinimumSizeLearner).
    private mutating func retryRefusal(_ window: WindowRef, requested: Rect, actual: Rect, now: ContinuousClock.Instant) -> [ArrangerEffect] {
        let id = window.identity, margin = MinimumSizeLearner.refusalMargin
        guard pauseReasons.isEmpty, !sessionPaused, drag?.window != window, windows[id]?.isExcluded == false,
            let key = deskKey(of: window), display(for: key) != nil, world[key]?.tree.state(of: window) == .present,
            let tile = lastRequested[id], Self.near(tile, requested), refusalRetried[id] != requested,
            actual.width > requested.width + margin || actual.height > requested.height + margin
        else { return [] }
        refusalRetried[id] = requested
        lastCorrection[id] = now
        pendingCorrections.insert(id)
        return nextWake.map { [.wake(at: $0)] } ?? []
    }

    /// Corrects the docked windows whose second has passed and that are still off their tile.
    private mutating func tick(now: ContinuousClock.Instant) -> [ArrangerEffect] {
        // D-14: no new Finder window by the deadline. The layout was never touched, so only N9 is shown.
        var missed: [ArrangerEffect] = []
        if let expected = finderExpectation, now >= expected.deadline {
            finderExpectation = nil
            missed = [.notice(.finderNoWindow)]
        }
        let due = pendingCorrections.filter { id in lastCorrection[id].map { now >= $0 + Self.correctionInterval } ?? true }
        pendingCorrections.subtract(due)
        let off = due.filter { id in
            guard let info = windows[id], let tile = lastRequested[id] else { return false }
            return world.desks.values.contains { $0.tree.state(of: info.window) == .present } && !Self.near(info.frame, tile, within: 2)
        }
        let effects = off.isEmpty ? [] : correct(off, now: now)
        let expired = expirePlaceholders(now: now)
        return missed + expired + revealTimedOut(now: now) + effects + closeProgress(now: now) + settleDrag(now: now) + (nextWake.map { [.wake(at: $0)] } ?? [])
    }

    /// Forgets the tile last sent, so the re-plan writes it again.
    private mutating func correct(_ ids: Set<WindowIdentity>, now: ContinuousClock.Instant) -> [ArrangerEffect] {
        for id in ids where !parkRequested.contains(id) {
            lastCorrection[id] = now
            lastRequested[id] = nil
        }
        return replan()
    }

    /// The earliest instant a waiting correction, the Finder deadline, a drag's dwell or a placeholder is due: the shell
    /// keeps one wake.
    var nextWake: ContinuousClock.Instant? {
        let dwell = drag?.kind == .move ? drag?.dwellEnds : nil
        let groupDwell = drag?.kind == .move ? drag?.groupDwellEnds : nil
        return (pendingCorrections.compactMap { lastCorrection[$0].map { $0 + Self.correctionInterval } }
            + [finderExpectation?.deadline, dwell, groupDwell, tabs.pendingReveal?.deadline, tabs.closeQueue?.deadline, earliestPlaceholderDeadline]
            .compactMap { $0 }).min()
    }

    /// Puts a dockable, present, non-excluded window that no desk holds on its own Space's Desktop layer, at its own
    /// frame. Never docks it (TILE-07). Creates the desk the first time such a window is seen there, so a fullscreen
    /// Space, which holds no present window, never gets one (WIN-07).
    private mutating func admit(_ info: WindowInfo) throws(LayoutError) {
        guard info.kind == .dockable, !info.isExcluded, info.state == .present, deskKey(of: info.window) == nil,
            let key = home(of: info)
        else { return }
        guard !gestureLive else {
            heldAdmits.insert(info.window.identity)
            return
        }
        if world[key] == nil { try world.addDesk(key) }
        // A kept wanted frame beats the real one (WR-02).
        let frame = wantedFrames[info.window.identity] ?? info.frame
        try world.reflow(key) { desk, _ throws(LayoutError) in try desk.desktop.add(info.window, frame: frame) }
        wantedFrames[info.window.identity] = frame
    }

    /// The gesture is over: the windows it held back float on their desks, with no auto-tile (WR-01).
    private mutating func admitHeld() -> [ArrangerEffect] {
        let held = heldAdmits.sorted()
        heldAdmits = []
        var effects: [ArrangerEffect] = []
        for info in held.compactMap({ windows[$0] }) {
            do throws(LayoutError) {
                try admit(info)
                effects += widen(toShow: info.window, new: true)
            } catch { effects.append(.fault("could not add \(info.window) after a drag: \(error)")) }
        }
        return effects + replan()
    }

    /// A docked window, or a floating group's member, whose app was just excluded floats on its desk's Desktop at its
    /// current frame, out of any group (D-29, TILE-18). A hidden member floats at its group's content rect instead, where
    /// the window system's last write before the exclusion put it (`releaseFrames(forExcluding:)`, CR-01). An OS fact:
    /// it goes through `World.reflow`, with no undo step, and its neighbours take its room at the re-plan.
    private mutating func release(_ info: WindowInfo) throws(LayoutError) {
        guard info.isExcluded, let key = deskKey(of: info.window), let state = world[key]?.state(of: info.window) else { return }
        let docked = world[key]?.tree.state(of: info.window) != nil
        let group = tabGroup(holding: info.window)
        guard docked || group != nil else { return }
        let frame = group.flatMap { $0.members[$0.selected] != info.window ? contentRect(of: $0) : nil } ?? info.frame
        try world.reflow(key) { desk, _ throws(LayoutError) in
            if docked { try desk.tree.remove(info.window) } else { try desk.desktop.remove(info.window) }
            try desk.desktop.add(info.window, frame: frame)
            if state != .present { try desk.desktop.setState(state, for: info.window) }
        }
        wantedFrames[info.window.identity] = frame
    }

    /// The desk a window belongs on (D-25): its display's, on the shown Space unless its known Spaces exclude that
    /// one, then on the lowest of them. Nil for a window on no known display.
    func home(of info: WindowInfo) -> DeskKey? {
        guard let display = displays.first(where: { $0.uuid == info.displayUUID }) else { return nil }
        guard let shown = display.currentSpaceID, let spaces = info.spaces, !spaces.contains(shown), let lowest = spaces.min()
        else { return Self.key(display) }
        return DeskKey(displayUUID: display.uuid, spaceID: lowest)
    }

    /// A present window whose display changed, or whose known, non-empty Spaces no longer include its desk's, floats
    /// on its home desk at its current frame, so no layout plans a window that is not there (D-25). An OS fact: it
    /// goes through `World.reflow`, with no undo step. An empty set (a hidden tab, 02-14) never moves a window.
    private mutating func rehome(_ info: WindowInfo) throws(LayoutError) {
        guard info.state == .present, let from = deskKey(of: info.window), let desk = world[from], desk.state(of: info.window) == .present,
            !parkRequested.contains(info.window.identity),  // camera-parked too (RESEARCH Pitfall 1)
            !isHiddenTab(info.window),  // a hidden member never moves on its own; its group follows the selected one
            !placeholders.arriving.contains(info.window.identity),  // on its way to its tile (CR-03)
            let to = home(of: info), to != from
        else { return }
        let spaces = info.spaces ?? []
        let leftSpace = from.spaceID.map { !spaces.isEmpty && !spaces.contains($0) } ?? false
        guard to.displayUUID != from.displayUUID || leftSpace else { return }
        // While displays settle, a display move is macOS's: the tile is kept for the re-plug (Pitfall 4).
        if settling, to.displayUUID != from.displayUUID { return }
        // A group's selected member takes the whole group to another display, where it floats as one (UI-SPEC Surface 5).
        // A frame write cannot move a hidden member to another Space of the same display, so a Space move takes the
        // selected member out alone and the rest stay grouped on the old desk, a neighbour selected (WR-03).
        let group = to.displayUUID != from.displayUUID ? tabGroup(holding: info.window) : nil
        var taken: (node: Node, states: [WindowIdentity: WindowState])?
        var candidate = world
        try candidate.reflow(from) { desk, _ throws(LayoutError) in
            if let group {
                taken = try Self.takeGroup(group, from: &desk)
            } else if desk.desktop.contains(info.window) { try desk.desktop.remove(info.window) } else { try desk.tree.remove(info.window) }
        }
        if candidate[to] == nil { try candidate.addDesk(to) }
        try candidate.reflow(to) { desk, ids throws(LayoutError) in
            if let taken, case .tabs(let members, let selected) = taken.node {
                let frame = TabBand.frame(ofContent: info.frame)
                try desk.desktop.addGroup(FloatingTabGroup(id: try ids.make(), members: members, selected: selected, frame: frame), states: taken.states)
            } else {
                try desk.desktop.add(info.window, frame: info.frame)
            }
        }
        world = candidate
        // An OS fact, not a user action: a frame from the desk it left would pull it back there.
        wantedFrames[info.window.identity] = info.frame
    }

    // MARK: Commands

    /// Docks a floating window where a drop at its centre would land (D-12). A dock that would leave any window
    /// without room is refused and changes nothing (D-26). A floating group's member docks the whole group, at the
    /// group frame's centre (Dock Group, UI-SPEC Surface 5).
    mutating func dock(_ window: WindowRef) throws(LayoutError) -> [ArrangerEffect] {
        guard let key = deskKey(of: window), let desk = world[key], let area = display(for: key)?.visibleFrame else { return [.beep] }
        let group = tabGroup(holding: window).flatMap { $0.floating ? $0 : nil }
        let shown = group.map { $0.members[$0.selected] } ?? window
        let mins = minimums
        let current = try Planner.plan(desk: desk, area: area, gap: gap, mins: mins)
        // Where the window is, or is about to be when Transom has just clamped it.
        guard let content = current.frames[shown] ?? desk.desktop.frame(of: shown) else { return [.beep] }
        let frame = group == nil ? content : TabBand.frame(ofContent: content)
        guard let target = Planner.dockTarget(at: Point(x: frame.midX, y: frame.midY), desk: desk, area: area, resolution: current.resolution)
        else { return [.beep] }
        if case .tile(_, .center) = target { return [.beep] }  // dockTarget never gives a centre: keyboard commands never group
        var candidate = world, candidateHistory = history
        try candidate.edit(key, history: &candidateHistory) { desk, ids throws(LayoutError) in
            if let group {
                let taken = try Self.takeGroup(group, from: &desk)
                try desk.tree.applyDrop(target, leaf: taken.node, states: taken.states, ids: &ids)
            } else {
                try desk.desktop.remove(window)
                try desk.tree.applyDrop(target, window: window, ids: &ids)
            }
        }
        guard let docked = candidate[key] else { return [.beep] }
        var collapsed: Collapse?
        if try !Planner.plan(desk: docked, area: area, gap: gap, mins: mins).unfit.isEmpty {
            // Zoom on: accepted, the windows without room collapse (D-A).
            collapsed = try collapse(docked, area: area)
            guard collapsed != nil else {
                // Keyboard parity (UI-SPEC Surface 2): the blocked preview flashes at the frame it would have had.
                let loose = try Planner.plan(desk: docked, area: area, gap: gap, mins: [:])
                let frame = group == nil ? loose.frames[window] : docked.tree.leaf(containing: shown).flatMap { loose.resolution.nodeRects[$0] }
                return [.beep, .announce(Self.noRoom)] + (frame.map { [.flashBlocked($0, displayUUID: key.displayUUID)] } ?? [])
            }
        }
        world = candidate
        history = candidateHistory
        let note = accept(collapsed, moving: shown)
        return replan() + note + (group.map { [.info("group \($0.key.node): docked")] } ?? [])
    }

    /// Undocks a window to floating (TILE-09); the green button floats through here too. It goes to its pre-dock
    /// (wanted) frame clamped on screen; with none known, or one that would land back on the tile, to a frame 90% of the
    /// tile centred on the visible frame (`Planner.floatFrame`). Docking fills the tile (D-12), so the toggle
    /// always moves the window (G-03-4).
    private mutating func float(_ window: WindowRef) throws(LayoutError) -> [ArrangerEffect] {
        if let group = tabGroup(holding: window), !group.floating { return try floatGroup(group) }  // the whole group (Surface 5)
        guard let key = deskKey(of: window), let desk = world[key], let area = display(for: key)?.visibleFrame,
            let state = desk.tree.state(of: window)
        else { return [.beep] }
        let mins = minimums
        guard let tile = try Planner.plan(desk: desk, area: area, gap: gap, mins: mins).frames[window] ?? windows[window.identity]?.frame
        else { return [.beep] }
        let wanted = wantedFrames[window.identity]
        var kept: Rect?
        try world.edit(key, history: &history) { desk, _ throws(LayoutError) in
            try desk.tree.remove(window)
            let frame = Planner.floatFrame(wanted: wanted, tile: tile, desktop: area, minimum: mins[window])
            try desk.desktop.add(window, frame: frame)
            // Float's clamp of the pre-dock frame is Transom's: the pre-dock frame stays wanted (WR-01).
            kept = wanted.map { Planner.clamp($0, into: area) } == frame ? wanted : frame
            if state != .present { try desk.desktop.setState(state, for: window) }
        }
        wantedFrames[window.identity] = kept
        return replan()
    }

    /// Restores the previous layout of the focused window's desk (TILE-09). Windows the undo revived get their real
    /// states first (`requery`, then `requeried`); otherwise the desk is re-planned at once. Wanted frames are not part
    /// of a desk snapshot: a window an undo floats again goes back to its kept wanted frame, and one it docks again gets
    /// back the wanted frame Float All or a ⇧-undock replaced (`undockedWanted`, WR-02).
    private mutating func undo(_ focused: WindowRef?) throws(LayoutError) -> [ArrangerEffect] {
        guard let key = targetKey(focused), let revived = try LifecycleSync.undo(key, world: &world, history: &history) else {
            return [.beep]
        }
        for window in world[key]?.tree.windows ?? [] {
            if let wanted = undockedWanted.removeValue(forKey: window.identity) { wantedFrames[window.identity] = wanted }
        }
        // The snapshot predates OS facts with no undo step (a window admitted, rehomed or excluded since): apply them again.
        var faults: [ArrangerEffect] = []
        for info in windows.values.sorted(by: { $0.window.identity < $1.window.identity }) {
            do throws(LayoutError) {
                try release(info)
                try admit(info)
            } catch { faults.append(.fault("could not re-add \(info.window) after an undo: \(error)")) }
        }
        return faults + (revived.windows.isEmpty ? replan() : [.requery(revived)])
    }

    /// Focuses the nearest tile across `edge` of the window's tile, or of its frame when it floats (D-11, TILE-09).
    /// Ties go to the most recently focused; the Desktop tile stands for its floating windows there. A Desktop
    /// neighbour focuses its most recently focused present floating window. No neighbour, or an empty Desktop: beep.
    private func focusNeighbour(of window: WindowRef, toward edge: Edge) throws(LayoutError) -> [ArrangerEffect] {
        guard let key = deskKey(of: window), let desk = world[key], let area = display(for: key)?.visibleFrame else { return [.beep] }
        let resolution = try Planner.plan(desk: desk, area: area, gap: gap, mins: minimums).resolution
        let leaf = desk.tree.leaf(containing: window)
        guard let rect = leaf.flatMap({ resolution.nodeRects[$0] }) ?? desk.desktop.frame(of: window) else { return [.beep] }
        // A hidden tab never takes focus this way (UI-SPEC Surface 3); its group's selected member stands for it.
        let floating = desk.desktop.windows.filter { $0.state == .present && !isHiddenTab($0.window) && placeholders.table[$0.window.identity] == nil }.map(\.window)
        guard let id = Neighbours.neighbour(
            of: rect, excluding: leaf, toward: edge, tree: desk.tree, resolution: withoutWaiting(resolution, tree: desk.tree), gap: gap, recency: recency(on: desk))
        else { return [.beep] }
        let target: WindowRef?
        switch desk.tree.node(id) {
        case .panel(let panel)?: target = panel
        case .tabs(let tabs, let selected)?: target = tabs[selected]  // LayoutTree.validate keeps selected in range
        case .desktop?:
            // Never-focused floating windows come after every focused one, in Desktop order.
            target = floating.min { (focusOrder.firstIndex(of: $0.identity) ?? .max) < (focusOrder.firstIndex(of: $1.identity) ?? .max) }
        case .split?, nil: target = nil
        }
        return target.map { [.perform([.focus($0)])] } ?? [.beep]
    }

    /// The desk's leaves, the most recently focused first: the Desktop tile stands for its present floating windows.
    func recency(on desk: Desk) -> [NodeID] {
        focusOrder.compactMap { id -> NodeID? in
            if desk.desktop.windows.contains(where: { $0.state == .present && $0.window.identity == id }) { return .desktop }
            return desk.tree.windows.first { $0.identity == id }.flatMap(desk.tree.leaf(containing:))
        }
    }

    /// Waits for a new Finder window to split the current tile along its longer side: width >= height splits to the
    /// right, otherwise below (D-14, TILE-17). The current tile is the focused docked window's; with a floating focused
    /// window, or none, the largest tile of that desk (or of the main display's visible desk); on an empty desk the new
    /// window fills the visible frame.
    private mutating func finderSplit(_ focused: WindowRef?, now: ContinuousClock.Instant) throws(LayoutError) -> [ArrangerEffect] {
        guard let key = targetKey(focused), let area = display(for: key)?.visibleFrame else { return [.beep] }
        var tile: (NodeID, Rect)?
        if let desk = world[key] {
            let resolution = try Planner.plan(desk: desk, area: area, gap: gap, mins: minimums).resolution
            let focusedLeaf = focused.flatMap { desk.tree.leaf(containing: $0) }
            tile = focusedLeaf.flatMap { leaf in resolution.nodeRects[leaf].map { (leaf, $0) } } ?? Self.largestTile(resolution, in: desk.tree)
        }
        let rect = tile?.1 ?? area
        finderExpectation = FinderExpectation(
            key: key, target: tile?.0, edge: rect.width >= rect.height ? .right : .bottom,
            known: Set(windows.keys.filter { $0.bundleID == Self.finderBundleID }), deadline: now + Self.finderWait)
        return [.openFinderWindow] + (nextWake.map { [.wake(at: $0)] } ?? [])
    }

    /// Docks the first Finder window created before the deadline that was not tracked at the press, in the split the
    /// press asked for. A dock that would leave any window without room is refused; the window keeps floating (D-26).
    private mutating func takeFinderWindow(_ info: WindowInfo, now: ContinuousClock.Instant) throws(LayoutError) -> [ArrangerEffect] {
        guard let expected = finderExpectation, expected.matches(info, now: now), let from = deskKey(of: info.window), world[from]?.desktop.contains(info.window) == true,
            let area = display(for: expected.key)?.visibleFrame
        else { return [] }
        finderExpectation = nil
        let drop = expected.target.map { DropTarget.tile($0, .edge(expected.edge)) } ?? .layoutEdge(expected.edge)
        var candidate = world, candidateHistory = history
        // Finder may open the window on another display: it leaves that Desktop first (an OS fact, no undo step).
        if from != expected.key {
            try candidate.reflow(from) { desk, _ throws(LayoutError) in try desk.desktop.remove(info.window) }
            if candidate[expected.key] == nil { try candidate.addDesk(expected.key) }
        }
        try candidate.edit(expected.key, history: &candidateHistory) { desk, ids throws(LayoutError) in
            if desk.desktop.contains(info.window) { try desk.desktop.remove(info.window) }
            try desk.tree.applyDrop(drop, window: info.window, ids: &ids)
        }
        guard let docked = candidate[expected.key], try Planner.plan(desk: docked, area: area, gap: gap, mins: minimums).unfit.isEmpty else {
            return [.beep, .announce(Self.noRoom)]
        }
        world = candidate
        history = candidateHistory
        return []
    }

    /// Pause Arranging adds `user`; Resume clears `user` and `crashLoop` and, once no reason is left, re-applies the
    /// layout (D-23).
    private mutating func togglePause() -> [ArrangerEffect] {
        guard !pauseReasons.isEmpty else {
            pauseReasons.insert(.user)
            return hideHandles()
        }
        pauseReasons.subtract([.user, .crashLoop])
        return pauseReasons.isEmpty ? resume() : []
    }

    /// Leaving the paused state: a window moved off its tile while paused is no longer "already requested", so the
    /// re-plan puts it back along with everything that changed.
    private mutating func resume() -> [ArrangerEffect] {
        lastRequested = lastRequested.filter { id, rect in windows[id].map { Self.near($0.frame, rect) } ?? false }
        return replan()
    }

    // MARK: Drags

    /// One left-button event (RESEARCH Pattern 4). A press on a tracked, dockable, present window of an app that is not
    /// excluded starts a session; nothing starts while paused (D-23). Modifiers are read from every event (D-05).
    private mutating func pointer(_ event: PointerEvent, now: ContinuousClock.Instant) -> [ArrangerEffect] {
        switch event.kind {
        case .down:
            let stale = abandonDrag()
            tabs.tearPress = nil  // a press whose mouse-up never arrived
            if let tab = event.pressTab {
                pressTab(tab)
                return stale
            }
            guard let pressed = event.pressWindow, let info = windows[pressed.identity], canDrag(info) else { return stale }
            drag = DragSession(window: info.window, start: event.location, startFrame: info.frame, modifiers: event.modifiers)
            return stale
        case .dragged, .flagsChanged:
            if drag == nil, event.kind == .dragged, let press = tabs.tearPress, !press.strip.contains(event.location) {
                guard pauseReasons.isEmpty else {
                    tabs.tearPress = nil
                    return []
                }
                tearOff(press, at: event.location, modifiers: event.modifiers)
            }
            guard var session = drag else { return [] }
            guard pauseReasons.isEmpty else { return endDrag() }
            session.pointer = event.location
            session.modifiers = event.modifiers
            if !event.modifiers.contains(.control) { session.controlAtPress = false }
            if session.tearOffGroup != nil {
                drag = session
                return [tearOffGhost(session)] + follow(now: now)
            }
            var effects: [ArrangerEffect] = []
            if !session.polling, session.travelled {
                session.polling = true
                effects.append(.pollDragFrame(session.window))
            }
            if let frame = windows[session.window.identity]?.frame {
                session.observe(frame, lastApplied: lastApplied[session.window.identity])
            }
            drag = session
            return effects + follow(now: now)
        case .up:
            tabs.tearPress = nil  // released inside the strip: the strip's own click
            guard drag != nil else { return [] }
            drag?.modifiers = event.modifiers
            return release(now: now)
        }
    }

    /// A press whose mouse-up never arrived (the tap was disabled for a moment): the miss rules, never its preview.
    private mutating func abandonDrag() -> [ArrangerEffect] {
        guard let session = drag else { return [] }
        let effects = endDrag()
        // A tear-off is never committed without its release: the tab stays in its group.
        guard session.kind != nil, session.tearOffGroup == nil, deskKey(of: session.window) != nil else { return effects }
        do throws(LayoutError) {
            return effects + (try missed(session.window))
        } catch {
            return effects + [.fault("could not settle the drag of \(session.window): \(error)")] + replan()
        }
    }

    private func canDrag(_ info: WindowInfo) -> Bool {
        guard pauseReasons.isEmpty, !sessionPaused, info.kind == .dockable, !info.isExcluded, info.state == .present,
            let key = deskKey(of: info.window), let desk = world[key], desk.state(of: info.window) == .present
        else { return false }
        return true
    }

    /// Ends the session: stops the poll and withdraws the preview.
    mutating func endDrag() -> [ArrangerEffect] {
        guard let session = drag else { return [] }
        drag = nil
        dragPlans = [:]
        tabs.tearPress = nil
        tabs.tearing = nil
        return (session.polling ? [.pollDragFrame(nil)] : []) + (session.shown != nil ? [.preview(nil, displayUUID: session.shownOn)] : [])
            + (session.tearOffGroup != nil ? [.tearOffGhost(nil)] : [])
            + (session.guides.isEmpty ? [] : session.guidesOn.map { [.fourthGuides([], displayUUID: $0)] } ?? [])
    }

    /// A move session's pointer or frame changed: a new hover withdraws the preview and restarts the dwell; a held one
    /// shows its preview once the dwell has passed.
    private mutating func follow(now: ContinuousClock.Instant) -> [ArrangerEffect] {
        if drag?.kind == .resize { return followResize() }
        guard var session = drag, session.kind == .move else { return [] }
        let hidden = hideHandles()  // no gap handles while a window is dragged
        guard windows[session.window.identity]?.isExcluded == false, deskKey(of: session.window) != nil else { return endDrag() }
        let hover = hover(for: session)
        guard session.update(hover: hover, at: now) else {
            drag = session  // a group dwell restarted by a move is kept; the earlier wake's tick re-arms for it
            return hidden + settleDrag(now: now)
        }
        var effects = hidden
        if session.shown != nil {
            effects.append(.preview(nil, displayUUID: session.shownOn))
            session.shown = nil
            session.shownOn = nil
        }
        effects += followGuides(&session, to: hover)
        drag = session
        return effects + (nextWake.map { [.wake(at: $0)] } ?? [])
    }

    /// Runs the dry run once the hover has held for the dwell (and the group dry run once a centre has held for the group
    /// dwell), and shows (or moves) the preview it gives.
    private mutating func settleDrag(now: ContinuousClock.Instant) -> [ArrangerEffect] {
        guard var session = drag, session.kind == .move else { return [] }
        let window = session.window
        _ = session.settle(at: now) { decide($0, window: window) }
        _ = session.settleGroup(at: now) { decideGroup($0, window: window) }
        var guides: [ArrangerEffect] = []
        // Before the guard: a fourth with no result to show still has its zones.
        if session.current != nil, session.guides.isEmpty, let hover = session.hover, let bands = fourthBands(for: hover), let uuid = hover.displayUUID {
            session.guides = bands
            session.guidesOn = uuid
            guides = [.fourthGuides(bands, displayUUID: uuid)]
        }
        let raw = windows[window.identity]?.frame ?? session.startFrame
        let frame = session.tearOffGroup != nil ? session.landingFrame(at: session.pointer) : movingGroup(window) == nil ? raw : TabBand.frame(ofContent: raw)
        let preview = session.current.flatMap { decision in decision.clampInto.map { .clamp(Planner.clamp(frame, into: $0)) } ?? decision.preview }
        guard let decision = session.current, preview != session.shown else {
            drag = session
            return guides
        }
        session.shown = preview
        session.shownOn = decision.display
        drag = session
        return guides + [.preview(preview, displayUUID: decision.display)]
    }

    /// The zone guides `hover` wants: the five bands of its display along its axis; nil when it is not a fourth.
    private func fourthBands(for hover: Hover) -> [Rect]? {
        guard case .fourth(_, let axis)? = hover.target, let display = displays.first(where: { $0.uuid == hover.displayUUID }) else { return nil }
        return FourthZones.bands(in: display.visibleFrame, axis: axis)
    }

    /// A changed hover and the guides on screen: they stay steady across zones, follow the axis at once, and go when the
    /// hover leaves fourths or their display. First guides wait for the dwell (`settleDrag`).
    private func followGuides(_ session: inout DragSession, to hover: Hover) -> [ArrangerEffect] {
        guard !session.guides.isEmpty, let shownOn = session.guidesOn else { return [] }
        guard hover.displayUUID == shownOn, let bands = fourthBands(for: hover) else {
            session.guides = []
            session.guidesOn = nil
            return [.fourthGuides([], displayUUID: shownOn)]
        }
        guard bands != session.guides else { return [] }
        session.guides = bands
        return [.fourthGuides(bands, displayUUID: shownOn)]
    }

    /// What the pointer is over, reduced to what decides the drop (UI-SPEC Surface 2): the dwell restarts only when this
    /// changes. A docked window over its own tile is a miss; another docked leaf's centre is a miss until the group dwell.
    private mutating func hover(for session: DragSession) -> Hover {
        let window = session.window
        guard let ownKey = deskKey(of: window), let ownDesk = world[ownKey], let ownPlan = dragPlan(.desk(ownKey)) else { return Hover() }
        // A tear-off (D-10) hit-tests the pointer: back over its strip it shows nothing; it has no tile to swap from or
        // snap back to, and its own group is never a group target.
        let torn = session.tearOffGroup
        if case .tearOff(_, let strip, _) = session.origin, strip.contains(session.pointer) { return Hover(overStrip: true) }
        let docked = torn == nil && ownDesk.tree.state(of: window) != nil
        // The selected member of a group drags the whole group (UI-SPEC Surface 5): its frame is the group frame, and
        // no centre groups (merging groups is out of scope, Surface 1).
        let whole = movingGroup(window) != nil
        let raw = windows[window.identity]?.frame ?? session.startFrame
        let frame = whole ? TabBand.frame(ofContent: raw) : raw
        let point = session.pointer
        if session.modifiers.contains(.shift), torn != nil {
            return Hover(displayUUID: displays.first { $0.frame.contains(point) }?.uuid, modifiers: [.shift])
        }
        // Anywhere goes: only whether the frame would cross a docked tile, once floating, matters (TILE-02).
        func floatHover(plain: Bool) -> Hover {
            let plan = ownDesk.tree.isDesktopHidden == true ? nil : docked ? dragPlan(.undock) : ownPlan
            return Hover(
                displayUUID: ownKey.displayUUID, modifiers: [.shift],
                crossesTiles: plan.map { Self.crosses(frame, $0, except: window) } ?? false, plain: plain)
        }
        if session.modifiers.contains(.shift) { return floatHover(plain: false) }
        let display = displays.first { $0.frame.contains(point) }
        // ⌃ takes a share of the whole desk under the pointer, ⌘ with it the rows, ⌥ ignored (UI-SPEC rows 2-3). A miss waits
        // for no dwell here, in Hold ⌥ mode too: this is not a plain drag.
        if session.modifiers.contains(.control), !session.controlAtPress {
            guard let display else { return Hover() }
            let axis: Axis = session.modifiers.contains(.command) ? .vertical : .horizontal
            return Hover(displayUUID: display.uuid, target: .fourth(FourthZones.slot(at: point, in: display.visibleFrame, axis: axis), axis))
        }
        // ⌘ over any part of another docked panel of the same desk swaps (TILE-11); ⌘ is ignored for a floating window.
        if docked, session.modifiers.contains(.command), let display, Self.key(display) == ownKey,
            let other = ownPlan.resolution.windowRects.first(where: { $0.key != window && $0.value.contains(point) })?.key,
            let leaf = ownDesk.tree.leaf(containing: other), case .panel? = ownDesk.tree.node(leaf)
        {
            return Hover(displayUUID: ownKey.displayUUID, swapWith: other, modifiers: [.command])
        }
        // Hold ⌥ with ⌥ up (D-08, D-08a): a torn tab takes ⇧'s tear-off hover, so decide answers tearOffMiss and it floats.
        // Under 16 pt a docked window is decide's ordinary snap-back miss, and so is ⌘, which never pulls a window out.
        if dragToDock == .holdOption, !session.modifiers.contains(.option) {
            if torn != nil { return Hover(displayUUID: display?.uuid, modifiers: [.shift]) }
            if docked, session.modifiers.contains(.command) || !session.travelledToPullOut { return Hover(displayUUID: ownKey.displayUUID) }
            return floatHover(plain: true)
        }
        var target: DropTarget?
        var groupTarget: GroupTarget?
        if let display, let plan = dragPlan(.desk(Self.key(display))) {
            let key = Self.key(display)
            target = DropZones.target(at: point, in: display.visibleFrame, tree: (world[key] ?? Desk()).tree, resolution: plan.resolution)
            let overDesktop = if case .tile(.desktop, _)? = target { true } else { target == nil }
            switch target {
            case .tile(let id, _)? where docked && key == ownKey && id == ownDesk.tree.leaf(containing: window): target = nil
            case .tile(let id, .center)?:
                // A docked leaf's centre groups after the group dwell (D-01); until then it is a miss.
                target = nil
                groupTarget = !whole && GroupKey(desk: key, node: id) != torn && groupable(id, on: key) ? .tile(key, id) : nil
            default: break
            }
            // On the Desktop tile a floating window's centre groups after the group dwell (D-02); the tile's own centre
            // stays a plain floating move.
            if overDesktop, !whole, let floating = floatingGroupTarget(at: point, on: key, dragging: window),
                floating != torn.map({ .floatingGroup($0.desk, $0.node) })
            {
                target = nil
                groupTarget = floating
            }
        }
        return Hover(
            displayUUID: display?.uuid, target: target,
            crossesTiles: torn == nil && !docked && target == nil && Self.crosses(frame, ownPlan, except: window), groupTarget: groupTarget)
    }

    /// The dry run for one held hover (UI-SPEC Surface 2 state matrix): a copy of the World with the drop applied, then
    /// planned. A drop that leaves any window without room is blocked, showing the frame it would get ignoring minimums.
    mutating func decide(_ hover: Hover, window: WindowRef) -> Decision {
        guard let ownKey = deskKey(of: window), let ownDesk = world[ownKey], let ownPlan = dragPlan(.desk(ownKey)) else {
            return Decision(action: .miss)
        }
        let docked = ownDesk.tree.state(of: window) != nil
        let own = ownKey.displayUUID
        let group = movingGroup(window)
        // Previews show the group frame, strip included, for a whole-group drag (Surface 5).
        func shown(_ plan: FramePlan, on desk: Desk) -> Rect? {
            guard group != nil else { return plan.frames[window] }
            return desk.tree.leaf(containing: window).flatMap { plan.resolution.nodeRects[$0] }
                ?? plan.frames[window].map(TabBand.frame(ofContent:))
        }
        let origin = shown(ownPlan, on: ownDesk)
        let torn = tabs.tearing == window
        let miss = torn
            ? tearOffMiss(hover, window: window)
            : docked
            ? Decision(preview: origin.map { .snapBack($0, label: nil) }, action: .miss, display: own)
            : Decision(action: .miss, display: own, clampInto: hover.crossesTiles ? ownPlan.desktopRect : nil)
        if torn, hover.overStrip || hover.modifiers.contains(.shift) { return miss }  // ⇧ bypasses: the float
        if hover.modifiers.contains(.shift) {
            // A floating window can't exist while the Desktop tile is hidden (D-31).
            if ownDesk.tree.isDesktopHidden == true {
                return Decision(
                    preview: origin.map { .snapBack($0, label: Self.showDesktopToFloat) }, action: .refuse(Self.showDesktopToFloat), display: own)
            }
            guard docked else { return miss }
            let minimum = (group.map { groupMinimum($0.members) } ?? minimums[window]) ?? Size(width: 1, height: 1)
            guard let plan = dragPlan(.undock), let desktop = plan.desktopRect, plan.unfit.isEmpty,
                minimum.width <= desktop.width, minimum.height <= desktop.height
            else {
                let over = dragPlan(.undock)?.desktopRect ?? display(for: ownKey)?.visibleFrame
                return Decision(preview: over.map(PreviewState.blocked), action: .refuse(Self.noRoom), display: own)
            }
            return Decision(action: .undock, display: own, clampInto: hover.crossesTiles ? desktop : nil)
        }
        if let other = hover.swapWith, let origin, let rect = ownPlan.frames[other] {
            return Decision(preview: .swap(target: rect, origin: origin), action: .swap(other), display: own)
        }
        guard let target = hover.target, let uuid = hover.displayUUID, let display = displays.first(where: { $0.uuid == uuid }) else {
            return miss
        }
        func landing(_ rect: Rect, _ label: String?) -> PreviewState {
            label.map { .fourth(rect, label: $0) } ?? .dock(rect)
        }
        let key = Self.key(display)
        do throws(LayoutError) {
            let candidate = try dropping(window, on: key, at: target)
            guard let desk = candidate.world[key] else { return miss }
            let plan = try Planner.plan(desk: desk, area: display.visibleFrame, gap: gap, mins: minimums)
            if plan.unfit.isEmpty, let frame = shown(plan, on: desk) {
                return Decision(preview: landing(frame, candidate.fourthLabel), action: .dock(key, target), display: uuid)
            }
            let loose = shown(try Planner.plan(desk: desk, area: display.visibleFrame, gap: gap, mins: [:]), on: desk)
            // D-A: with zoom on the drop is accepted and the windows without room collapse.
            if let collapsed = try collapse(desk, area: display.visibleFrame) {
                let copy = Self.collapseCopy(collapsed.newly, moving: window)
                let preview = loose.map { rect in copy.map { PreviewState.collapsed(rect, label: $0.label) } ?? landing(rect, candidate.fourthLabel) }
                return Decision(preview: preview, action: .dock(key, target), display: uuid)
            }
            return Decision(preview: loose.map(PreviewState.blocked), action: .refuse(Self.noRoom), display: uuid)
        } catch {
            return miss  // the target went stale since the hit test
        }
    }

    /// The World and history with `window` taken off its desk and dropped on `key`'s at `target`: one undo step there.
    /// The selected member of a group takes its whole group, as one leaf (Surface 5).
    /// `group` is the keyboard's whole group, for any focused member; a drag leaves it nil and uses `movingGroup`.
    /// `fourthLabel` names what a fourth gets, read off the desk with the window out of it (D-23).
    func dropping(
        _ window: WindowRef, on key: DeskKey, at target: DropTarget, moving group: TabGroupRef? = nil
    ) throws(LayoutError) -> (world: World, history: UndoHistory, fourthLabel: String?) {
        var candidate = world, candidateHistory = history
        var fourthLabel: String?
        func nameFourth(on tree: LayoutTree) {
            guard case .fourth(let slot, let axis) = target else { return }
            fourthLabel = FourthCopy.label(slot, axis, span: tree.fourthSpan(slot, axis: axis))
        }
        let group = group ?? movingGroup(window)
        var taken: (node: Node, states: [WindowIdentity: WindowState])?
        if let from = deskKey(of: window), from != key {
            // Leaving another display's desk is a fact of where it was dropped, not a second undo step.
            try candidate.reflow(from) { desk, _ throws(LayoutError) in
                if let group {
                    taken = try Self.takeGroup(group, from: &desk)
                } else if desk.desktop.contains(window) { try desk.desktop.remove(window) } else { try desk.tree.remove(window) }
            }
            if candidate[key] == nil { try candidate.addDesk(key) }
        }
        try candidate.edit(key, history: &candidateHistory) { desk, ids throws(LayoutError) in
            if let group {
                let moved: (node: Node, states: [WindowIdentity: WindowState])
                if let taken { moved = taken } else { moved = try Self.takeGroup(group, from: &desk) }
                nameFourth(on: desk.tree)
                try desk.tree.applyDrop(target, leaf: moved.node, states: moved.states, ids: &ids)
                return
            }
            if desk.desktop.contains(window) {
                try desk.desktop.remove(window)
            } else if desk.tree.state(of: window) != nil {
                try desk.tree.remove(window)
            }
            nameFourth(on: desk.tree)
            try desk.tree.applyDrop(target, window: window, ids: &ids)
        }
        return (candidate, candidateHistory, fourthLabel)
    }

    /// Mouse-up: applies exactly the decision whose preview is on screen; with none, the miss rules (WYSIWYG). A Hold ⌥
    /// plain drag has nothing to wait for, so it decides here and its result never depends on the dwell.
    private mutating func release(now: ContinuousClock.Instant) -> [ArrangerEffect] {
        guard let session = drag else { return [] }
        // Before endDrag, which clears what undockPlan reads (RESEARCH Pitfall 2).
        var plain: Decision?
        if session.kind == .move, session.tearOffGroup == nil {
            let hover = hover(for: session)
            if hover.plain { plain = decide(hover, window: session.window) }
        }
        var effects = endDrag()
        let window = session.window
        guard windows[window.identity]?.isExcluded == false, deskKey(of: window) != nil else { return effects }
        guard let kind = session.kind else {
            // No pointer travel (a click, an ⌥-zoom, a title-bar double-click): a frame change during the press is the
            // app's own, answered like one after it (D-33, Pitfall 6).
            guard let frame = windows[window.identity]?.frame, !Self.near(frame, session.startFrame, within: DragSession.echoTolerance)
            else { return effects }
            do throws(LayoutError) {
                return effects + (try moved(window, to: frame, now: now))
            } catch {
                return effects + [.fault("could not answer the frame change of \(window): \(error)")] + replan()
            }
        }
        if session.tearOffGroup != nil { return effects + releaseTearOff(session) }
        let action = kind == .move ? plain?.action ?? session.current?.action ?? .miss : .miss
        do throws(LayoutError) {
            if kind == .resize, let key = deskKey(of: window), world[key]?.tree.state(of: window) != nil,
                let change = try boundaryChange(key, edgeMoves(session))
            {
                try world.edit(key, history: &history, change)
                lastRequested[window.identity] = nil  // settles exactly into the new tile
                return effects + replan()
            }
            switch action {
            case .dock(let key, let target): effects += try commitDock(window, on: key, at: target)
            case .group(let key, let target): effects += try commitGroup(window, on: key, into: target)
            case .swap(let other): effects += try commitSwap(window, with: other)
            case .undock: effects += try commitUndock(window)
            case .refuse(let text): effects += [.announce(text)] + (try missed(window))
            case .miss, .tearOffFloat: effects += try missed(window)
            }
        } catch {
            effects += [.fault("drop of \(window) failed: \(error)")] + replan()
        }
        return effects
    }

    mutating func commitDock(_ window: WindowRef, on key: DeskKey, at target: DropTarget) throws(LayoutError) -> [ArrangerEffect] {
        let candidate = try dropping(window, on: key, at: target)
        guard let area = display(for: key)?.visibleFrame, let desk = candidate.world[key] else {
            return [.announce(Self.noRoom)] + (try missed(window))
        }
        let plan = try Planner.plan(desk: desk, area: area, gap: gap, mins: minimums)
        var collapsed: Collapse?
        if !plan.unfit.isEmpty {
            guard let collapse = try collapse(desk, area: area) else { return [.announce(Self.noRoom)] + (try missed(window)) }
            collapsed = collapse
        }
        if case .fourth = target, collapsed == nil, let before = world[key], try fourthChangesNothing(window, on: before, area: area, to: plan) {
            return try missed(window)  // its own zone: it goes back to the tile it holds, with no undo step (WR-08)
        }
        world = candidate.world
        history = candidate.history
        lastRequested[window.identity] = nil
        let note = accept(collapsed, moving: window)
        guard let label = candidate.fourthLabel else { return replan() + note }
        return widen(toShow: window, new: false) + replan() + (note.isEmpty ? [.announce(FourthCopy.docked(label))] : note)
    }

    /// ⌘-drop: the two docked windows exchange tiles, one undo step (TILE-11).
    private mutating func commitSwap(_ window: WindowRef, with other: WindowRef) throws(LayoutError) -> [ArrangerEffect] {
        guard let key = deskKey(of: window) else { return try missed(window) }
        try world.edit(key, history: &history) { desk, _ throws(LayoutError) in try desk.tree.swap(window, other) }
        lastRequested[window.identity] = nil
        return replan() + [.announce(Self.swapped)]
    }

    /// ⇧-drop of a docked window: it floats at its release frame, clamped inside the Desktop rect the undock leaves if it
    /// crosses a tile; one undo step (TILE-02).
    private mutating func commitUndock(_ window: WindowRef) throws(LayoutError) -> [ArrangerEffect] {
        guard let key = deskKey(of: window), let area = display(for: key)?.visibleFrame, let frame = windows[window.identity]?.frame
        else { return try missed(window) }
        let gap = gap, mins = minimums, group = movingGroup(window)
        try world.edit(key, history: &history) { desk, ids throws(LayoutError) in
            guard let group else {
                try desk.tree.remove(window)
                try desk.desktop.add(window, frame: frame)
                if let clamped = try Planner.plan(desk: desk, area: area, gap: gap, mins: mins).frames[window] {
                    try desk.desktop.setFrame(clamped, for: window)
                }
                return
            }
            // The whole group floats at its group frame, clamped as one if it crosses a tile (Surface 5).
            let taken = try Self.takeGroup(group, from: &desk)
            let outer = TabBand.frame(ofContent: frame)
            try desk.desktop.addGroup(
                FloatingTabGroup(id: try ids.make(), members: group.members, selected: group.selected, frame: outer), states: taken.states)
            let plan = try Planner.plan(desk: desk, area: area, gap: gap, mins: mins)
            if let desktop = plan.desktopRect, plan.resolution.windowRects.values.contains(where: outer.overlaps) {
                try desk.desktop.setFrame(TabBand.content(of: Planner.clamp(outer, into: desktop)), for: window)
            }
        }
        undockedWanted[window.identity] = wantedFrames[window.identity]
        wantedFrames[window.identity] = world[key]?.desktop.frame(of: window)
        lastRequested[window.identity] = nil
        return replan() + (dragToDock == .holdOption ? [.announce(FourthCopy.floating)] : [])
    }

    /// The miss rules (D-01, D-06): a docked window snaps back to its tile; a floating one stays where it was released,
    /// clamped into the Desktop rect if it crosses a docked tile, and moves to the desk of the display it is now on.
    mutating func missed(_ window: WindowRef) throws(LayoutError) -> [ArrangerEffect] {
        guard let key = deskKey(of: window), let desk = world[key], let info = windows[window.identity] else { return replan() }
        if desk.tree.state(of: window) != nil {
            if let tile = lastRequested[window.identity], Self.near(info.frame, tile, within: 2) { return replan() }
            lastRequested[window.identity] = nil
            return replan()
        }
        try world.recordFloatingFrame(info.frame, for: window)
        if let area = display(for: key)?.visibleFrame, let desk = world[key],
            let clamped = try Planner.plan(desk: desk, area: area, gap: gap, mins: minimums).frames[window]
        {
            try world.recordFloatingFrame(clamped, for: window)
        }
        try rehome(info)
        if let key = deskKey(of: window) { wantedFrames[window.identity] = world[key]?.desktop.frame(of: window) }
        return replan()
    }

    /// A docked window's edge-resize session (D-07): its neighbours follow on a transient copy of the World, the
    /// dragged window is never written, and nothing is committed before mouse-up. A floating one waits for mouse-up,
    /// where its frame is recorded as a fact.
    private mutating func followResize() -> [ArrangerEffect] {
        guard let session = drag, let key = deskKey(of: session.window), world[key]?.tree.state(of: session.window) != nil else { return [] }
        do throws(LayoutError) {
            guard let change = try boundaryChange(key, edgeMoves(session)) else { return [] }
            return try replan(with: change, on: key)
        } catch {
            return [.fault("could not follow the resize of \(session.window): \(error)")]
        }
    }

    /// Plans the shown desks as if `change` were applied to `key`'s desk, without changing the World: the live half of
    /// a resize. Writes still coalesce (latest wins), and mouse-up commits the change as one `World.edit`.
    private mutating func replan(with change: (inout Desk, inout IDSource) throws(LayoutError) -> Void, on key: DeskKey) throws(LayoutError) -> [ArrangerEffect] {
        let committed = world
        defer { world = committed }
        try world.reflow(key, change)  // weights never make a window unfit; a gap drag's lost-room floats came first
        return planShown()
    }

    /// The inner edges of the pressed docked window that its frame has moved off its tile, each as the split boundary
    /// it drags (`Neighbours.boundary`). An outer edge has none, so a window dragged only by those snaps back.
    private mutating func edgeMoves(_ session: DragSession) -> [BoundaryMove] {
        let window = session.window
        guard let key = deskKey(of: window), let desk = world[key], let leaf = desk.tree.leaf(containing: window),
            let plan = dragPlan(.desk(key)), let tile = plan.frames[window], let frame = windows[window.identity]?.frame
        else { return [] }
        let shifts: [(Edge, Double)] = [
            (.left, frame.minX - tile.minX), (.right, frame.maxX - tile.maxX), (.top, frame.minY - tile.minY), (.bottom, frame.maxY - tile.maxY),
        ]
        return shifts.compactMap { edge, shift in
            guard abs(shift) > 1, let boundary = Neighbours.boundary(for: leaf, edge: edge, in: desk.tree),
                case .split(_, let children, _)? = desk.tree.node(boundary.split)
            else { return nil }
            // The nearest sibling that takes part: a minimised one in between keeps its weight (Pitfall 9).
            let taking = { (i: Int) in plan.resolution.nodeRects[children[i]] != nil }
            let first = edge.isLeading ? (0...boundary.index).reversed().first(where: taking) : boundary.index
            let second = edge.isLeading ? boundary.index + 1 : (boundary.index + 1..<children.count).first(where: taking)
            guard let first, let second else { return nil }
            return BoundaryMove(split: boundary.split, first: first, second: second, points: shift)
        }
    }

    /// The change that moves each boundary of `key`'s desk by its points (positive grows `first`), or nil when nothing
    /// would move. Points become weight through the split's laid-out length, and are cut to what the shrinking side can
    /// give before its minimum, so the stored weights say what the screen shows (no dead zone on the way back).
    func boundaryChange(_ key: DeskKey, _ moves: [BoundaryMove]) throws(LayoutError) -> ((inout Desk, inout IDSource) throws(LayoutError) -> Void)? {
        guard !moves.isEmpty, let desk = world[key], let area = display(for: key)?.visibleFrame else { return nil }
        let gap = gap, mins = minimums
        let before = try Planner.plan(desk: desk, area: area, gap: gap, mins: mins).resolution
        func size(_ id: NodeID, _ axis: Axis, _ resolution: Resolution) -> Double {
            resolution.nodeRects[id].map { axis == .horizontal ? $0.width : $0.height } ?? 0
        }
        func apply(_ moves: [BoundaryMove], to desk: inout Desk) throws(LayoutError) {
            var rebased: Set<NodeID> = []
            for move in moves {
                guard case .split(let axis, let children, var weights)? = desk.tree.node(move.split), let rect = before.nodeRects[move.split]
                else { throw .nodeNotFound(move.split) }
                let taking = children.indices.filter { before.nodeRects[children[$0]] != nil }
                let length = (axis == .horizontal ? rect.width : rect.height) - gap.rounded() * Double(taking.count - 1)
                guard length > 0 else { continue }
                let weight = taking.reduce(0) { $0 + weights[$1] }
                // Weights re-based to the laid-out sizes, so a side pinned at its minimum no longer soaks up the move
                // (G-03-3 H1). Once per split: a second re-base would erase the first move. A minimised child keeps its weight.
                // Only where a share is off by more than a point: re-based whole-point sizes can floor a point short.
                let sizes = taking.map { size(children[$0], axis, before) }
                let laidOut = sizes.reduce(0, +)
                let offScreen = zip(taking, sizes).contains { abs(weights[$0] / weight * laidOut - $1) > 1 }
                if rebased.insert(move.split).inserted, offScreen, laidOut > 0, sizes.allSatisfy({ $0 > 0 }) {
                    for (i, index) in taking.enumerated() { weights[index] = sizes[i] / laidOut * weight }
                    try desk.tree.setWeights(in: move.split, weights)
                }
                try desk.tree.resizeBetween(in: move.split, move.first, move.second, by: move.points * weight / length)
            }
        }
        var raw = desk
        try apply(moves, to: &raw)
        let after = try Planner.plan(desk: raw, area: area, gap: gap, mins: mins).resolution
        let cut = try moves.map { move throws(LayoutError) -> BoundaryMove in
            guard case .split(let axis, let children, _)? = desk.tree.node(move.split) else { throw .nodeNotFound(move.split) }
            let loser = children[move.points > 0 ? move.second : move.first]
            let room = max(0, size(loser, axis, before) - size(loser, axis, after))
            var cut = move
            cut.points = move.points > 0 ? min(move.points, room) : -min(-move.points, room)
            return cut
        }
        guard cut.contains(where: { abs($0.points) >= 0.5 }) else { return nil }
        return { desk, _ throws(LayoutError) in try apply(cut, to: &desk) }
    }

    private mutating func dragPlan(_ key: DragPlanKey) -> FramePlan? {
        if let plan = dragPlans[key] { return plan }
        let plan: FramePlan?
        switch key {
        case .desk(let desk):
            // A desk that cannot be planned has no drop targets; replan reports the same fault.
            plan = display(for: desk).flatMap { try? Planner.plan(desk: world[desk] ?? Desk(), area: $0.visibleFrame, gap: gap, mins: minimums) }
        case .undock:
            plan = undockPlan()
        }
        dragPlans[key] = plan
        return plan
    }

    private func undockPlan() -> FramePlan? {
        guard let session = drag, let key = deskKey(of: session.window), var desk = world[key], let area = display(for: key)?.visibleFrame
        else { return nil }
        do throws(LayoutError) {
            if let group = movingGroup(session.window) {
                var ids = world.ids
                let taken = try Self.takeGroup(group, from: &desk)
                let floating = FloatingTabGroup(
                    id: try ids.make(), members: group.members, selected: group.selected, frame: TabBand.frame(ofContent: session.startFrame))
                try desk.desktop.addGroup(floating, states: taken.states)
            } else {
                try desk.tree.remove(session.window)
                try desk.desktop.add(session.window, frame: session.startFrame)
            }
            return try Planner.plan(desk: desk, area: area, gap: gap, mins: minimums)
        } catch {
            return nil
        }
    }

    /// `frame` overlaps a docked tile of `plan` other than `window`'s own.
    private static func crosses(_ frame: Rect, _ plan: FramePlan, except window: WindowRef) -> Bool {
        plan.resolution.windowRects.contains { $0.key != window && $0.value.overlaps(frame) }
    }

    // MARK: Planning

    /// Plans the shown desks, with the live gap move applied until mouse-up so no mid-drag event writes the pre-drag
    /// desk (G-03-3 H2). A live move whose split is gone, or that fails, is dropped.
    mutating func replan() -> [ArrangerEffect] {
        guard let live = liveGap else { return planShown() }
        // Lost-room floats are OS facts: made on the World itself before the transient live move, or every drag event
        // would float the window again on a throwaway copy and repeat the notice (WR-01).
        let floated = floatLostRoom()
        guard let key = shownDesk(holding: live.handle.split) else {
            liveGap = nil
            return floated + planShown()
        }
        do throws(LayoutError) {
            guard let change = try boundaryChange(key, [BoundaryMove(live.handle, live.delta)]) else { return floated + planShown() }
            return try floated + replan(with: change, on: key)
        } catch {
            liveGap = nil
            return floated + [.fault("could not drag the gap of \(live.handle.split): \(error)")] + planShown()
        }
    }

    /// Floats every docked window a shown desk has no room for, as `planShown` does, and returns its notice. A desk
    /// that cannot be planned is skipped here: the `planShown` that follows reports it.
    private mutating func floatLostRoom() -> [ArrangerEffect] {
        guard !sessionPaused, pauseReasons.isEmpty, !settling else { return [] }
        let mins = minimums
        var lost: [WindowRef] = []
        for display in displays where world[Self.key(display)] != nil {
            lost += (try? planFloatingLostRoom(Self.key(display), area: display.visibleFrame, mins: mins).1) ?? []
        }
        return lost.isEmpty ? [] : [.notice(.lostRoom(lost.sorted { $0.identity < $1.identity }))]
    }

    /// Plans every desk shown on a display and writes only the frames that changed by more than 0.5 pt. Docked
    /// windows left without room float first, and are named in one notice (D-26). A hidden Desktop's floating windows
    /// are parked once each, first in the perform, and only after an immediate save holding their home frames (D-16).
    mutating func planShown() -> [ArrangerEffect] {
        guard !sessionPaused, pauseReasons.isEmpty, !settling else { return [] }
        var parks: [WindowCommand] = []
        var parkedNow: Set<WindowIdentity> = []
        var commands: [WindowCommand] = []
        var faults: [ArrangerEffect] = []
        var planned: Set<WindowIdentity> = []
        var lost: [WindowRef] = []
        var handles: [String: [GapHandle]] = [:]
        var blocks: [String: [CollapsedBlock]] = [:]
        var strips: [String: [TabStrip]] = [:]
        var waiting: [String: [PlaceholderTile]] = [:]
        var fitAtHome: Set<WindowIdentity> = []
        let mins = minimums
        for display in displays {
            let key = Self.key(display)
            guard world[key] != nil else { continue }
            var plan: FramePlan
            var collapsed: [WindowRef: Rect] = [:]
            // Lost room at home is an OS fact and still floats (CONTEXT E); a zoomed display then plans its view.
            let view = effectiveView(for: key, notes: &faults)
            do throws(LayoutError) {
                let floated: [WindowRef]
                (plan, floated) = try planFloatingLostRoom(key, area: display.visibleFrame, mins: mins)
                lost += floated
                // With zoom on every view, home included, is planned with the collapse pass (ZOOM-13).
                if camera.enabled, let desk = world[key] {
                    let viewPlan = try ViewPlanner.plan(
                        desk: desk, view: view, area: display.visibleFrame, gap: gap, mins: learnedMinimums, wanted: wantedFrames,
                        collapsible: camera.collapsible)
                    (plan.frames, plan.parks, plan.parkSizes, plan.resolution) = (viewPlan.frames, viewPlan.parks, viewPlan.parkSizes, viewPlan.resolution)
                    collapsed = viewPlan.collapsed
                    blocks[display.uuid] = viewPlan.collapsed.filter { !isPlaceholder($0.key) }.map {
                        CollapsedBlock(window: $0.key, rect: $0.value, groupSize: tabGroup(holding: $0.key).map { liveTabs($0.members, selected: $0.selected).members.count } ?? 1)
                    }
                        .sorted { $0.window.identity < $1.window.identity }
                    let home = view == .home ? viewPlan : try ViewPlanner.plan(
                        desk: desk, view: .home, area: display.visibleFrame, gap: gap, mins: learnedMinimums, wanted: wantedFrames,
                        collapsible: camera.collapsible)
                    fitAtHome.formUnion(home.frames.keys.map(\.identity))
                }
            } catch {
                faults.append(.fault("could not plan \(key): \(error)"))
                continue
            }
            guard let desk = world[key] else { continue }
            strips[display.uuid] = tabStrips(key, desk: desk, plan: plan)
            waiting[display.uuid] = placeholderTiles(frames: plan.frames, collapsed: collapsed, resolution: plan.resolution)
            // A gap drag edits home weights, so a zoomed display shows no handles.
            if drag?.kind != .move {
                handles[display.uuid] = view == .home ? GapHandles.handles(tree: desk.tree, resolution: plan.resolution, gap: gap) : []
            }
            // Transom never moves an excluded app's window: no clamp, no park (D-29). An untracked (dormant, G-03-8) window
            // gets nothing either: the window system would drop the command, and its windowCreated replans it.
            var desired = plan.frames.filter { windows[$0.key.identity]?.isExcluded == false }
            // A just-created window outside the view stays where it opened until its widen move settles (Pitfall 3).
            // A tab being replaced keeps covering the content rect until the new one reads back (Pattern 5).
            for window in plan.parks
            where windows[window.identity]?.isExcluded == false && !camera.unparkedNew.contains(window.identity) && window != tabs.pendingReveal?.previous
            {
                // Never written before mouse-up (D-23), a tab switched mid-drag included (WR-04); one already parked stays so.
                if window == drag?.window {
                    if parkRequested.contains(window.identity) { parkedNow.insert(window.identity) }
                    continue
                }
                parkedNow.insert(window.identity)
                let size = plan.parkSizes[window]
                let resized = size.map { new in
                    parkedSize[window.identity].map { abs($0.width - new.width) > 0.5 || abs($0.height - new.height) > 0.5 } ?? true
                } ?? false
                guard parkRequested.insert(window.identity).inserted || resized else { continue }
                if homeFrames[window.identity] == nil, windows[window.identity]?.isExcluded != true {
                    homeFrames[window.identity] = desk.desktop.frame(of: window)
                }
                parkedSize[window.identity] = size
                parks.append(.park(window, displayUUID: display.uuid, size: size))
            }
            // A floating window not where the model has it (after Float, Snap or Undo) is moved there.
            for floating in desk.desktop.windows
            where floating.state == .present && desired[floating.window] == nil
                && windows[floating.window.identity]?.isExcluded != true && !parkedNow.contains(floating.window.identity)
                && desk.desktop.group(containing: floating.window).map({ $0.members[$0.selected] == floating.window }) ?? true
            {
                if let actual = windows[floating.window.identity]?.frame, !Self.near(actual, floating.frame) {
                    desired[floating.window] = floating.frame
                }
            }
            for (window, rect) in desired.sorted(by: { $0.key.identity < $1.key.identity }) {
                planned.insert(window.identity)
                if window == drag?.window { continue }  // never written before mouse-up (D-23)
                if let last = lastRequested[window.identity], Self.near(last, rect) { continue }
                lastRequested[window.identity] = rect
                commands.append(.setFrame(window, rect))
                if window == tabs.pendingReveal?.revealed { commands.append(.focus(window)) }
            }
        }
        // A window that left the plan (absent, fullscreen, floating clear of tiles) is written again when it returns.
        // A present window on a desk whose Space is not shown keeps its entry, so showing it again re-sends nothing.
        let shown = Set(displays.map(Self.key))
        let hidden = Set(world.desks.filter { !shown.contains($0.key) }.values.flatMap { desk in
            (desk.tree.windows + desk.desktop.windows.map(\.window)).filter { desk.state(of: $0) == .present }.map(\.identity)
        })
        lastRequested = lastRequested.filter { planned.contains($0.key) || hidden.contains($0.key) }
        // A window that left the tree gets its retry again when it is docked back into the same tile (WR-03).
        refusalRetried = refusalRetried.filter { id, _ in
            windows[id].map { info in world.desks.values.contains { $0.tree.state(of: info.window) != nil } } ?? false
        }
        parkRequested = parkRequested.filter { parkedNow.contains($0) || hidden.contains($0) }
        parkedSize = parkedSize.filter { parkRequested.contains($0.key) }
        // Collapsible only while collapsed: one that fits its home tile again, or left every tree, gets CONTEXT E's
        // refusals and lost-room float again (WR-01). A desk not shown keeps its windows' membership.
        camera.collapsible = camera.collapsible.filter { id in
            !fitAtHome.contains(id) && world.desks.values.contains { $0.tree.state(of: WindowRef(identity: id)) != nil }
        }
        commands = parks + commands
        return faults + (parks.isEmpty ? [] : [.save(.now)]) + (commands.isEmpty ? [] : [.perform(commands)])
            + (lost.isEmpty ? [] : [.notice(.lostRoom(lost.sorted { $0.identity < $1.identity }))]) + show(handles) + showBlocks(blocks)
            + showStrips(strips) + showPlaceholders(waiting)
    }

    /// Sends each display's collapsed blocks that changed; a display with none (or gone) gets an empty list.
    mutating func showBlocks(_ blocks: [String: [CollapsedBlock]]) -> [ArrangerEffect] {
        let uuids = Set(blocks.keys).union(camera.shownBlocks.keys).sorted()
        return uuids.compactMap { uuid in
            let next = blocks[uuid] ?? []
            guard next != camera.shownBlocks[uuid] ?? [] else { return nil }
            camera.shownBlocks[uuid] = next.isEmpty ? nil : next
            return .collapsedBlocks(next, displayUUID: uuid)
        }
    }

    /// Sends each display's handles that changed; a display with none planned (or gone) gets an empty list.
    private mutating func show(_ handles: [String: [GapHandle]]) -> [ArrangerEffect] {
        let uuids = Set(handles.keys).union(shownHandles.keys).sorted()
        return uuids.compactMap { uuid in
            let next = handles[uuid] ?? []
            guard next != shownHandles[uuid] ?? [] else { return nil }
            shownHandles[uuid] = next.isEmpty ? nil : next
            return .gapHandles(next, displayUUID: uuid)
        }
    }

    /// Hides every shown gap handle: paused, a window drag, a Space change (UI-SPEC Surface 3).
    private mutating func hideHandles() -> [ArrangerEffect] {
        show([:])
    }

    /// A gap-handle drag (TILE-05, D-07): until mouse-up both sides follow on a transient copy of the World (`liveGap`,
    /// applied by every replan); mouse-up commits one `World.edit`. Nothing moves while paused or while a window is
    /// being dragged or resized.
    private mutating func gapDrag(_ handle: GapHandle, delta: Double, ended: Bool) -> [ArrangerEffect] {
        if ended { liveGap = nil }  // first, so a mouse-up always ends the live move (T-03-56)
        guard pauseReasons.isEmpty, !sessionPaused, drag?.kind == nil, delta.isFinite, let key = shownDesk(holding: handle.split)
        else { return [] }
        guard ended else {
            liveGap = (handle, delta)
            return replan()
        }
        do throws(LayoutError) {
            if let change = try boundaryChange(key, [BoundaryMove(handle, delta)]) { try world.edit(key, history: &history, change) }
            return replan()
        } catch {
            return [.fault("could not drag the gap of \(handle.split): \(error)")] + replan()
        }
    }

    /// The shown desk holding `split` (split IDs are unique in the World).
    private func shownDesk(holding split: NodeID) -> DeskKey? {
        displays.map(Self.key).first { key in
            if case .split? = world[key]?.tree.node(split) { true } else { false }
        }
    }

    /// Plans `key`'s desk after floating every docked window it has no room for (D-26), in one pass: a floater takes no
    /// room (D-05), so floating one never leaves a neighbour short. Each float is an OS fact (`World.reflow`, no undo
    /// step), at the window's current frame clamped into the display's visible frame. Dock and drops refuse up front, so
    /// this only runs for changes after a window docked.
    private mutating func planFloatingLostRoom(
        _ key: DeskKey, area: Rect, mins: [WindowRef: Size]
    ) throws(LayoutError) -> (FramePlan, [WindowRef]) {
        var mins = mins
        guard let desk = world[key] else { throw .deskNotFound(key) }
        var plan = try Planner.plan(desk: desk, area: area, gap: gap, mins: mins)
        // A window that is not there has no frame to float at, and its minimum can wait until it comes back.
        let waiting = plan.unfit.filter { isPlaceholder($0) && mins[$0] != nil }
        if !waiting.isEmpty {
            for window in waiting { mins[window] = nil }
            plan = try Planner.plan(desk: desk, area: area, gap: gap, mins: mins)
        }
        guard !plan.unfit.isEmpty else { return (plan, []) }
        var unfit: [(WindowRef, Rect)] = []
        for window in plan.unfit.sorted(by: { $0.identity < $1.identity }) {
            guard let frame = windows[window.identity]?.frame else { throw .windowNotFound(window) }
            unfit.append((window, Planner.clamp(frame, into: area)))
        }
        try world.reflow(key) { desk, _ throws(LayoutError) in
            for (window, frame) in unfit {
                try desk.tree.remove(window)
                try desk.desktop.add(window, frame: frame)
            }
        }
        for (window, frame) in unfit { wantedFrames[window.identity] = frame }
        guard let floated = world[key] else { throw .deskNotFound(key) }
        return (try Planner.plan(desk: floated, area: area, gap: gap, mins: mins), unfit.map(\.0))
    }

    /// The minimums every Phase 3 plan and dry run uses: `learnedMinimums`, with 1x1 for a collapsible window, which
    /// may get less than it needs at home and so is never unfit there (ZOOM-13). Zoom off: the set is empty.
    var minimums: [WindowRef: Size] {
        var mins = learnedMinimums
        for window in mins.keys where camera.collapsible.contains(window.identity) { mins[window] = Size(width: 1, height: 1) }
        return mins
    }

    /// Excluded windows have none: they never dock. ViewPlanner gets these,
    /// so it can tell which collapsible windows are collapsed.
    var learnedMinimums: [WindowRef: Size] {
        Dictionary(
            windows.values.compactMap { info in info.isExcluded ? nil : info.learnedMinimum.map { (info.window, $0) } }
                + placeholders.table.values.compactMap { held in held.minimum.map { (held.ref, $0) } },
            uniquingKeysWith: { $1 })
    }

    func display(for key: DeskKey) -> DisplayInfo? {
        displays.first { Self.key($0) == key }
    }

    /// The desk shown on `display` right now.
    static func key(_ display: DisplayInfo) -> DeskKey {
        DeskKey(displayUUID: display.uuid, spaceID: display.currentSpaceID)
    }

    private static func near(_ a: Rect, _ b: Rect, within tolerance: Double = 0.5) -> Bool {
        Planner.near(a, b, within: tolerance)
    }
}

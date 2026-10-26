import PaneModel

/// Everything the Arranger reacts to. `requeried` carries the real states of windows an undo revived (D-11).
public enum ArrangerInput: Sendable {
    case inventory(WindowInventory)
    case event(WindowEvent)
    case command(Command, focused: WindowRef?)
    case requeried(RevivedWindows, [(WindowRef, WindowState)])
    /// The instant a `wake` asked for has come.
    case tick
    /// The layout saved by the last session (layout.json). It is re-attached by identity at the first complete inventory.
    case restore(World, homeFrames: [WindowIdentity: Rect])
    /// Sets or clears one pause reason; Stage Manager (plan 16) and the crash loop (plan 14) arrive this way.
    case setPaused(PauseReason, Bool)
    /// The gap between tiles (D-27), already validated by the shell's allow-list.
    case gap(Double)
    /// A left-button or modifier event from the event tap (TILE-01).
    case pointer(PointerEvent)
    /// The pressed window's CG bounds from the 60 Hz drag poll.
    case dragFrame(WindowIdentity, Rect)
}

/// Why arranging is paused (D-23). Arranging runs only while no reason is set. A lower raw value is a higher priority,
/// which picks the menu's pause line.
public enum PauseReason: Int, Comparable, Hashable, Sendable {
    case stageManager = 0, crashLoop = 1, user = 2

    public static func < (lhs: Self, rhs: Self) -> Bool { lhs.rawValue < rhs.rawValue }
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
}

/// The pure layout owner (RESEARCH Pattern 1): window-system inputs and user commands in, commands and effects out.
/// It never sleeps and never touches the OS; `ArrangeController` (PaneMac) and the tests drive it the same way.
/// OS facts change the World through `LifecycleSync` and `World.reflow`, user commands through `World.edit`.
public struct Arranger: Sendable {
    public static let noRoom = "Not enough room to dock here"
    public static let finderBundleID = "com.apple.finder"
    /// How long ⌃⌥⌘N waits for Finder's new window (D-14).
    public static let finderWait: Duration = .seconds(2)

    public private(set) var world = World()
    public private(set) var history = UndoHistory()
    /// The latest info per tracked window, docked or not.
    public private(set) var windows: [WindowIdentity: WindowInfo] = [:]
    public private(set) var displays: [DisplayInfo] = []
    /// Where each parked window goes back to (plan 08); restored from layout.json.
    public private(set) var homeFrames: [WindowIdentity: Rect] = [:]
    public var gap: Double
    /// While any reason is set, facts still change the World but no window command is sent (TILE-08).
    public private(set) var pauseReasons: Set<PauseReason> = []
    /// The last frame requested for each window that is still planned; a frame within 0.5 pt of it is not written
    /// again, so an app echoing frames cannot cause a write storm (T-03-08).
    private var lastRequested: [WindowIdentity: Rect] = [:]
    /// Locked or asleep: nothing is written until the session resumes, then every visible desk is re-planned.
    private var sessionPaused = false
    /// The Spaces-off fallback (A7) is reported once per session.
    private var reportedSpacesOff = false
    /// Each window's last read-back (`frameApplied`): a move or resize within 2 pt of it is Pane's own write coming
    /// back, never a move to answer (the echo rule).
    private var lastApplied: [WindowIdentity: Rect] = [:]
    /// When each docked window was last put back in its tile, and the ones waiting for that second to pass (T-03-13).
    private var lastCorrection: [WindowIdentity: ContinuousClock.Instant] = [:]
    private var pendingCorrections: Set<WindowIdentity> = []
    private static let correctionInterval: Duration = .seconds(1)
    /// The layout saved by the last session, waiting for the first complete inventory (SAFE-06).
    private var pendingRestore: (world: World, homeFrames: [WindowIdentity: Rect])?
    /// Windows a `park` was sent for and that are still parked, so each is parked once, not on every re-plan.
    private var parkRequested: Set<WindowIdentity> = []
    /// The left-button press in progress, if any (TILE-01).
    public private(set) var drag: DragSession?
    /// A title-bar drag is under way (plan 16 defers alerts while it is).
    public var isDragging: Bool { drag?.kind == .move }
    /// Desk plans a drag hit-tests against, computed once per drag (and again after the World changes).
    private var dragPlans: [DragPlanKey: FramePlan] = [:]

    private enum DragPlanKey: Hashable {
        case desk(DeskKey)
    }
    /// Window identities, the most recently focused first: focus ties go to the earliest (D-11).
    public private(set) var focusOrder: [WindowIdentity] = []
    /// The split ⌃⌥⌘N asked for, waiting for Finder's new window; a newer one replaces it.
    private var finderExpectation: FinderExpectation?

    private struct FinderExpectation: Sendable {
        let key: DeskKey
        let target: NodeID
        let edge: Edge
        /// Finder windows already tracked at the press: a change to one of them is never the new window.
        let known: Set<WindowIdentity>
        let deadline: ContinuousClock.Instant
    }

    public init(gap: Double = 8) {
        self.gap = gap
    }

    /// Every input that changes the World ends with `.save(.debounced)`, so layout.json follows it (D-16).
    public mutating func handle(_ input: ArrangerInput, now: ContinuousClock.Instant) -> [ArrangerEffect] {
        let before = world
        let effects = process(input, now: now)
        guard world != before else { return effects }
        dragPlans = [:]  // the plans a drag caches are of the World before
        return effects + [.save(.debounced)]
    }

    private mutating func process(_ input: ArrangerInput, now: ContinuousClock.Instant) -> [ArrangerEffect] {
        switch input {
        case .inventory(let inventory):
            displays = inventory.displays
            sessionPaused = inventory.sessionPaused
            windows = Dictionary(inventory.windows.map { ($0.window.identity, $0) }, uniquingKeysWith: { $1 })
            guard let restore = pendingRestore else { return place(inventory) }
            // The saved layout waits for every app's first answer, so no saved window is dropped as untracked.
            guard inventory.initialRefreshComplete else { return [] }
            pendingRestore = nil
            // Re-planned quietly: a window that lost its room still floats, but with no toast.
            return reattach(restore, tracked: inventory.windows) + place(inventory).filter {
                if case .notice = $0 { false } else { true }
            }
        case .event(let event):
            // Until the saved layout is re-attached, the next complete inventory says everything an event would.
            guard pendingRestore == nil else { return [] }
            return handle(event, now: now)
        case .command(let command, let focused):
            guard isAvailable(command, focused: focused) else { return [.beep] }
            do throws(LayoutError) {
                switch (command, focused) {
                case (.dock, let window?): return try dock(window)
                case (.float, let window?): return try float(window)
                case (.undo, _): return try undo(focused)
                case (.toggleDesktop, _): return try toggleDesktop(focused)
                case (.focus(let edge), let window?): return try focusNeighbour(of: window, toward: edge)
                case (.finderSplit, _): return try finderSplit(focused, now: now)
                case (.togglePause, _): return togglePause()
                case (.toggleExcludeFrontmost, _): return [.fault("toggleExcludeFrontmost reached the Arranger; the shell handles it")]
                case (.dock, nil), (.float, nil), (.focus, nil): return [.beep]
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
        case .restore(let world, let homeFrames):
            pendingRestore = (world, homeFrames)
            return []
        case .setPaused(let reason, let on):
            let wasPaused = !pauseReasons.isEmpty
            if on { pauseReasons.insert(reason) } else { pauseReasons.remove(reason) }
            return wasPaused && pauseReasons.isEmpty ? resume() : []
        case .gap(let value):
            gap = value
            return replan()
        case .pointer(let event):
            return pointer(event, now: now)
        case .dragFrame(let id, let frame):
            guard drag?.window.identity == id else { return [] }
            windows[id]?.frame = frame
            drag?.observe(frame, lastApplied: lastApplied[id])
            return follow(now: now)
        }
    }

    /// What layout.json should hold now: while a restore waits, the saved layout itself, so a write then loses nothing.
    public var snapshot: (world: World, homeFrames: [WindowIdentity: Rect]) {
        pendingRestore ?? (world, homeFrames)
    }

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
                try rehome(info)
                try admit(info)
            } catch { faults.append(.fault("could not add \(info.window): \(error)")) }
        }
        return faults + replan()
    }

    /// Replaces the World with the saved one re-attached by identity (SAFE-06), with each window's real state and, for
    /// a present floating window, its real frame. Each docked window's current frame counts as already requested, so
    /// only tiles more than 0.5 pt off are written. Undo history starts empty (session-only). Home frames are kept only
    /// for windows tracked under a real ID. If the saved layout cannot be re-attached, the World starts empty.
    private mutating func reattach(_ restore: (world: World, homeFrames: [WindowIdentity: Rect]), tracked: [WindowInfo]) -> [ArrangerEffect] {
        history = UndoHistory()
        let real = Set(tracked.filter { $0.idSource != .synthetic }.map(\.window.identity))
        homeFrames = restore.homeFrames.filter { real.contains($0.key) }
        do throws(LayoutError) {
            var candidate = try LayoutRestore.reattach(restore.world, tracked: tracked).world
            var seeded: [WindowIdentity: Rect] = [:]
            for info in tracked where info.state != .closed {
                guard let key = candidate.desks.first(where: { $0.value.contains(info.window) })?.key, let desk = candidate[key] else {
                    continue
                }
                if desk.state(of: info.window) != info.state { try candidate.apply(info.state, for: info.window, on: key, history: &history) }
                if !desk.desktop.contains(info.window) {
                    seeded[info.window.identity] = info.frame
                } else if info.state == .present {
                    try candidate.recordFloatingFrame(info.frame, for: info.window)
                }
            }
            world = candidate
            lastRequested = seeded
            return []
        } catch {
            return [.fault("could not re-attach the saved layout; starting empty: \(error)")]
        }
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
        case .finderSplit:
            return targetKey(focused).flatMap(display(for:)) != nil
        case .togglePause, .toggleExcludeFrontmost:
            return true  // answered above
        case .toggleDesktop:
            // Hiding with nothing docked and present would leave an empty screen (UI-SPEC Surface 1 row 17).
            guard let key = targetKey(focused), let desk = world[key] else { return false }
            return desk.tree.isDesktopHidden == true || desk.tree.windows.contains { desk.tree.state(of: $0) == .present }
        }
    }

    /// Whether the Desktop tile of the desk a command on `focused` targets is hidden: the toggle item's title.
    public func isDesktopHidden(focused: WindowRef?) -> Bool {
        targetKey(focused).flatMap { world[$0]?.tree.isDesktopHidden } == true
    }

    /// The focused window's desk or, with none focused (or one on no desk), the main display's visible desk.
    private func targetKey(_ focused: WindowRef?) -> DeskKey? {
        focused.flatMap(deskKey(of:)) ?? displays.first.map(Self.key)
    }

    // MARK: Events

    private mutating func handle(_ event: WindowEvent, now: ContinuousClock.Instant) -> [ArrangerEffect] {
        var subject: WindowIdentity?
        do throws(LayoutError) {
            switch event {
            case .windowCreated(let info), .windowChanged(let info):
                windows[info.window.identity] = info
                subject = info.window.identity
            case .windowRekeyed(let from, let to):
                windows[from.identity] = nil
                windows[to.window.identity] = to
                lastRequested[to.window.identity] = lastRequested.removeValue(forKey: from.identity)
                lastApplied[to.window.identity] = lastApplied.removeValue(forKey: from.identity)
                lastCorrection[to.window.identity] = lastCorrection.removeValue(forKey: from.identity)
                if pendingCorrections.remove(from.identity) != nil { pendingCorrections.insert(to.window.identity) }
                if parkRequested.remove(from.identity) != nil { parkRequested.insert(to.window.identity) }
                if let home = homeFrames.removeValue(forKey: from.identity) { homeFrames[to.window.identity] = home }
                focusOrder = focusOrder.map { $0 == from.identity ? to.window.identity : $0 }
                subject = to.window.identity
            case .windowMoved(let window, let frame), .windowResized(let window, let frame):
                windows[window.identity]?.frame = frame
                return try moved(window, to: frame, now: now)
            case .frameApplied(let window, _, let actual):
                lastApplied[window.identity] = actual
                return []
            case .windowStateChanged(let window, let state):
                if state == .closed { forget(window) } else { windows[window.identity]?.state = state }
                subject = window.identity
            case .windowDestroyed(let window):
                forget(window)
            case .sessionPaused(let paused):
                sessionPaused = paused
            case .spaceChanged(let uuid, let spaceID):
                // Only the shown Space's desk is planned; the one left keeps its layout untouched (D-25).
                if let i = displays.firstIndex(where: { $0.uuid == uuid }) { displays[i].currentSpaceID = spaceID }
            case .windowFocused(let window):
                focusOrder.removeAll { $0 == window.identity }
                focusOrder.insert(window.identity, at: 0)
            case .appResponsiveness, .appLaunched, .appTerminated, .displaysChanged:
                break
            }
            _ = try LifecycleSync.handle(event, world: &world, history: &history)
            if case .windowChanged(let info) = event {
                try release(info)
                // The pressed window may be crossing displays; where it lands is decided at mouse-up.
                if drag?.window != info.window { try rehome(info) }
            }
            // A window that just became dockable, present or known floats on its display's Desktop (D-24).
            if let subject, let info = windows[subject] { try admit(info) }
        } catch {
            return [.fault("ignored an event: \(error)")]
        }
        guard case .windowCreated(let info) = event else { return replan() }
        do throws(LayoutError) {
            return try takeFinderWindow(info, now: now) + replan()
        } catch {
            return [.fault("could not dock the new Finder window: \(error)")] + replan()
        }
    }

    private mutating func forget(_ window: WindowRef) {
        windows[window.identity] = nil
        lastRequested[window.identity] = nil
        lastApplied[window.identity] = nil
        lastCorrection[window.identity] = nil
        pendingCorrections.remove(window.identity)
        parkRequested.remove(window.identity)
        homeFrames[window.identity] = nil
        focusOrder.removeAll { $0 == window.identity }
    }

    // MARK: Moves

    /// A window moved or resized. Within 2 pt of Pane's last read-back it is Pane's own write coming back: a floating
    /// window's frame is still recorded as a fact, and nothing is answered. Otherwise a floating window's frame is
    /// recorded (TILE-07, no undo step), clamped into the Desktop only if it now overlaps a docked tile, and a docked
    /// window goes back to its tile, at most once per second (T-03-13). There is no pointer state yet, so every move
    /// counts as finished; plan 10 adds drag sessions so a user dragging a docked window is never fought.
    private mutating func moved(_ window: WindowRef, to frame: Rect, now: ContinuousClock.Instant) throws(LayoutError) -> [ArrangerEffect] {
        // The pressed window is never answered while the button is down; mouse-up decides (D-01).
        if drag?.window == window {
            drag?.observe(frame, lastApplied: lastApplied[window.identity])
            return follow(now: now)
        }
        guard let key = deskKey(of: window), let desk = world[key] else { return [] }
        let floating = desk.desktop.contains(window)
        // A parked window keeps its Desktop frame: the move is the park, and showing the Desktop brings it back there.
        if floating, desk.tree.isDesktopHidden == true { return [] }
        if floating { try world.recordFloatingFrame(frame, for: window) }
        guard pauseReasons.isEmpty else { return [] }  // paused: the fact is recorded, nothing is answered (D-23)
        guard windows[window.identity]?.isExcluded != true else { return [] }  // never clamped or corrected (D-29)
        if let applied = lastApplied[window.identity], Self.near(applied, frame, within: 2) { return [] }
        if floating {
            if let area = display(for: key)?.visibleFrame, let desk = world[key],
                let clamped = try Planner.plan(desk: desk, area: area, gap: gap, mins: minimums).frames[window]
            {
                try world.recordFloatingFrame(clamped, for: window)
            }
            return replan()
        }
        guard desk.tree.state(of: window) == .present else { return [] }
        if let tile = lastRequested[window.identity], Self.near(tile, frame, within: 2) { return [] }
        if let last = lastCorrection[window.identity], now < last + Self.correctionInterval {
            pendingCorrections.insert(window.identity)
            return nextWake.map { [.wake(at: $0)] } ?? []
        }
        return correct([window.identity], now: now)
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
        return missed + effects + settleDrag(now: now) + (nextWake.map { [.wake(at: $0)] } ?? [])
    }

    /// Forgets the tile last sent, so the re-plan writes it again.
    private mutating func correct(_ ids: Set<WindowIdentity>, now: ContinuousClock.Instant) -> [ArrangerEffect] {
        for id in ids {
            lastCorrection[id] = now
            lastRequested[id] = nil
        }
        return replan()
    }

    /// The earliest instant a waiting correction, the Finder deadline or a drag's dwell is due: the shell keeps one wake.
    private var nextWake: ContinuousClock.Instant? {
        let dwell = drag?.kind == .move ? drag?.dwellEnds : nil
        return (pendingCorrections.compactMap { lastCorrection[$0].map { $0 + Self.correctionInterval } } + [finderExpectation?.deadline, dwell].compactMap { $0 }).min()
    }

    /// Puts a dockable, present, non-excluded window that no desk holds on its own Space's Desktop layer, at its own
    /// frame. Never docks it (TILE-07). Creates the desk the first time such a window is seen there, so a fullscreen
    /// Space, which holds no present window, never gets one (WIN-07).
    private mutating func admit(_ info: WindowInfo) throws(LayoutError) {
        guard info.kind == .dockable, !info.isExcluded, info.state == .present, deskKey(of: info.window) == nil,
            let key = home(of: info)
        else { return }
        if world[key] == nil { try world.addDesk(key) }
        // D-31: a floating window can't exist while the Desktop is hidden, so a new one shows it again (no undo step).
        if world[key]?.tree.isDesktopHidden == true { try world.reflow(key, showingDesktop()) }
        try world.reflow(key) { desk, _ throws(LayoutError) in try desk.desktop.add(info.window, frame: info.frame) }
    }

    /// A docked window whose app was just excluded floats on its desk's Desktop at its current frame (D-29, TILE-18).
    /// An OS fact: it goes through `World.reflow`, with no undo step, and its neighbours take its room at the re-plan.
    private mutating func release(_ info: WindowInfo) throws(LayoutError) {
        guard info.isExcluded, let key = deskKey(of: info.window), let state = world[key]?.tree.state(of: info.window) else { return }
        try world.reflow(key) { desk, _ throws(LayoutError) in
            try desk.tree.remove(info.window)
            try desk.desktop.add(info.window, frame: info.frame)
            if state != .present { try desk.desktop.setState(state, for: info.window) }
        }
    }

    /// The desk a window belongs on (D-25): its display's, on the shown Space unless its known Spaces exclude that
    /// one, then on the lowest of them. Nil for a window on no known display.
    private func home(of info: WindowInfo) -> DeskKey? {
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
            !(desk.tree.isDesktopHidden == true && desk.desktop.contains(info.window)),  // parked: off its display on purpose
            let to = home(of: info), to != from
        else { return }
        let spaces = info.spaces ?? []
        let leftSpace = from.spaceID.map { !spaces.isEmpty && !spaces.contains($0) } ?? false
        guard to.displayUUID != from.displayUUID || leftSpace else { return }
        var candidate = world
        try candidate.reflow(from) { desk, _ throws(LayoutError) in
            if desk.desktop.contains(info.window) { try desk.desktop.remove(info.window) } else { try desk.tree.remove(info.window) }
        }
        if candidate[to] == nil { try candidate.addDesk(to) }
        if candidate[to]?.tree.isDesktopHidden == true { try candidate.reflow(to, showingDesktop()) }  // D-31
        try candidate.reflow(to) { desk, _ throws(LayoutError) in try desk.desktop.add(info.window, frame: info.frame) }
        world = candidate
    }

    // MARK: Commands

    /// Docks a floating window where a drop at its centre would land (D-12). A dock that would leave any window
    /// without room is refused and changes nothing (D-26).
    private mutating func dock(_ window: WindowRef) throws(LayoutError) -> [ArrangerEffect] {
        guard let key = deskKey(of: window), let desk = world[key], let area = display(for: key)?.visibleFrame else { return [.beep] }
        let mins = minimums
        let current = try Planner.plan(desk: desk, area: area, gap: gap, mins: mins)
        // Where the window is, or is about to be when Pane has just clamped it.
        guard let frame = current.frames[window] ?? desk.desktop.frame(of: window),
            let target = Planner.dockTarget(at: Point(x: frame.midX, y: frame.midY), desk: desk, area: area, resolution: current.resolution)
        else { return [.beep] }
        if case .tile(_, .center) = target { return [.beep] }  // tab groups from a centre drop are Phase 7
        var candidate = world, candidateHistory = history
        try candidate.edit(key, history: &candidateHistory) { desk, ids throws(LayoutError) in
            try desk.desktop.remove(window)
            try desk.tree.applyDrop(target, window: window, ids: &ids)
        }
        guard let docked = candidate[key], try Planner.plan(desk: docked, area: area, gap: gap, mins: mins).unfit.isEmpty else {
            return [.beep, .announce(Self.noRoom)]
        }
        world = candidate
        history = candidateHistory
        return replan()
    }

    /// Undocks a window to the Desktop at its tile rect, clamped into the Desktop rect the undock leaves (TILE-09).
    private mutating func float(_ window: WindowRef) throws(LayoutError) -> [ArrangerEffect] {
        guard let key = deskKey(of: window), let desk = world[key], let area = display(for: key)?.visibleFrame,
            let state = desk.tree.state(of: window)
        else { return [.beep] }
        let mins = minimums
        guard let tile = try Planner.plan(desk: desk, area: area, gap: gap, mins: mins).frames[window] ?? windows[window.identity]?.frame
        else { return [.beep] }
        let gap = gap
        let show = showingDesktop()
        try world.edit(key, history: &history) { desk, ids throws(LayoutError) in
            // A floating window can't exist while the Desktop is hidden (UI-SPEC Surface 2), so floating shows it.
            if desk.tree.isDesktopHidden == true { try show(&desk, &ids) }
            try desk.tree.remove(window)
            let desktop = try Planner.plan(desk: desk, area: area, gap: gap, mins: mins).desktopRect ?? area
            try desk.desktop.add(window, frame: Planner.clamp(tile, into: desktop))
            if state != .present { try desk.desktop.setState(state, for: window) }
        }
        return replan()
    }

    /// Restores the previous layout of the focused window's desk (TILE-09). Windows the undo revived get their real
    /// states first (`requery`, then `requeried`); otherwise the desk is re-planned at once.
    private mutating func undo(_ focused: WindowRef?) throws(LayoutError) -> [ArrangerEffect] {
        guard let key = targetKey(focused), let revived = try LifecycleSync.undo(key, world: &world, history: &history) else {
            return [.beep]
        }
        return revived.windows.isEmpty ? replan() : [.requery(revived)]
    }

    /// Hides the target desk's Desktop tile, so the docked tiles take its space and its floating windows are parked
    /// (TILE-15, D-24), or shows it with every parked window back at its home frame. One undo step either way. The
    /// home frames are recorded first; `replan` saves them at once, before any park is sent (D-16).
    private mutating func toggleDesktop(_ focused: WindowRef?) throws(LayoutError) -> [ArrangerEffect] {
        guard let key = targetKey(focused), let desk = world[key] else { return [.beep] }
        if desk.tree.isDesktopHidden == true {
            try world.edit(key, history: &history, showingDesktop())
        } else {
            for floating in desk.desktop.windows where windows[floating.window.identity]?.isExcluded != true {
                homeFrames[floating.window.identity] = floating.frame
            }
            try world.edit(key, history: &history) { desk, _ throws(LayoutError) in try desk.tree.setDesktopHidden(true) }
        }
        return replan()
    }

    /// Focuses the nearest tile across `edge` of the window's tile, or of its frame when it floats (D-11, TILE-09).
    /// Ties go to the most recently focused; the Desktop tile stands for its floating windows there. A Desktop
    /// neighbour focuses its most recently focused present floating window. No neighbour, or an empty Desktop: beep.
    private func focusNeighbour(of window: WindowRef, toward edge: Edge) throws(LayoutError) -> [ArrangerEffect] {
        guard let key = deskKey(of: window), let desk = world[key], let area = display(for: key)?.visibleFrame else { return [.beep] }
        let resolution = try Planner.plan(desk: desk, area: area, gap: gap, mins: minimums).resolution
        let leaf = desk.tree.leaf(containing: window)
        guard let rect = leaf.flatMap({ resolution.nodeRects[$0] }) ?? desk.desktop.frame(of: window) else { return [.beep] }
        let floating = desk.desktop.windows.filter { $0.state == .present }.map(\.window)
        let recency = focusOrder.compactMap { id -> NodeID? in
            if floating.contains(where: { $0.identity == id }) { return .desktop }
            return desk.tree.windows.first { $0.identity == id }.flatMap(desk.tree.leaf(containing:))
        }
        guard let id = Neighbours.neighbour(
            of: rect, excluding: leaf, toward: edge, tree: desk.tree, resolution: resolution, gap: gap, recency: recency)
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

    /// Waits for a new Finder window to split the current tile along its longer side: width >= height splits to the
    /// right, otherwise below (D-14, TILE-17). The current tile is the focused docked window's; with a floating focused
    /// window, or none, it is the Desktop tile of that desk (or of the main display's visible desk).
    private mutating func finderSplit(_ focused: WindowRef?, now: ContinuousClock.Instant) throws(LayoutError) -> [ArrangerEffect] {
        guard let key = targetKey(focused), let area = display(for: key)?.visibleFrame else { return [.beep] }
        let target = focused.flatMap { world[key]?.tree.leaf(containing: $0) } ?? .desktop
        let rect: Rect?
        if let desk = world[key] {
            rect = try Planner.plan(desk: desk, area: area, gap: gap, mins: minimums).resolution.nodeRects[target]
        } else {
            rect = area  // no desk there yet: it is all Desktop
        }
        guard let rect else { return [.beep] }  // a hidden Desktop has no tile to split
        finderExpectation = FinderExpectation(
            key: key, target: target, edge: rect.width >= rect.height ? .right : .bottom,
            known: Set(windows.keys.filter { $0.bundleID == Self.finderBundleID }), deadline: now + Self.finderWait)
        return [.openFinderWindow] + (nextWake.map { [.wake(at: $0)] } ?? [])
    }

    /// Docks the first Finder window created before the deadline that was not tracked at the press, in the split the
    /// press asked for. A dock that would leave any window without room is refused; the window keeps floating (D-26).
    private mutating func takeFinderWindow(_ info: WindowInfo, now: ContinuousClock.Instant) throws(LayoutError) -> [ArrangerEffect] {
        guard let expected = finderExpectation, info.window.bundleID == Self.finderBundleID, !expected.known.contains(info.window.identity),
            now < expected.deadline, let from = deskKey(of: info.window), world[from]?.desktop.contains(info.window) == true,
            let area = display(for: expected.key)?.visibleFrame
        else { return [] }
        finderExpectation = nil
        let drop = DropTarget.tile(expected.target, .edge(expected.edge))
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
            return []
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

    /// The change that shows a desk's Desktop tile, with each floating window that has a home frame back at it.
    private func showingDesktop() -> (inout Desk, inout IDSource) throws(LayoutError) -> Void {
        let homes = homeFrames
        return { desk, _ throws(LayoutError) in
            try desk.tree.setDesktopHidden(false)
            for floating in desk.desktop.windows {
                if let home = homes[floating.window.identity] { try desk.desktop.setFrame(home, for: floating.window) }
            }
        }
    }

    // MARK: Drags

    /// One left-button event (RESEARCH Pattern 4). A press on a tracked, dockable, present window of an app that is not
    /// excluded starts a session; nothing starts while paused (D-23). Modifiers are read from every event (D-05).
    private mutating func pointer(_ event: PointerEvent, now: ContinuousClock.Instant) -> [ArrangerEffect] {
        switch event.kind {
        case .down:
            let stale = endDrag()  // a press whose mouse-up never arrived
            guard let pressed = event.pressWindow, let info = windows[pressed.identity], canDrag(info) else { return stale }
            drag = DragSession(window: info.window, start: event.location, startFrame: info.frame, modifiers: event.modifiers)
            return stale
        case .dragged, .flagsChanged:
            guard var session = drag else { return [] }
            guard pauseReasons.isEmpty else { return endDrag() }
            session.pointer = event.location
            session.modifiers = event.modifiers
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
            guard drag != nil else { return [] }
            drag?.modifiers = event.modifiers
            return release(now: now)
        }
    }

    private func canDrag(_ info: WindowInfo) -> Bool {
        guard pauseReasons.isEmpty, !sessionPaused, info.kind == .dockable, !info.isExcluded, info.state == .present,
            let key = deskKey(of: info.window), let desk = world[key], desk.state(of: info.window) == .present
        else { return false }
        return !(desk.desktop.contains(info.window) && desk.tree.isDesktopHidden == true)  // parked
    }

    /// Ends the session: stops the poll and withdraws the preview.
    private mutating func endDrag() -> [ArrangerEffect] {
        guard let session = drag else { return [] }
        drag = nil
        dragPlans = [:]
        return (session.polling ? [.pollDragFrame(nil)] : []) + (session.shown != nil ? [.preview(nil, displayUUID: session.shownOn)] : [])
    }

    /// A move session's pointer or frame changed: a new hover withdraws the preview and restarts the dwell; a held one
    /// shows its preview once the dwell has passed.
    private mutating func follow(now: ContinuousClock.Instant) -> [ArrangerEffect] {
        guard var session = drag, session.kind == .move else { return [] }
        guard windows[session.window.identity]?.isExcluded == false, deskKey(of: session.window) != nil else { return endDrag() }
        let hover = hover(for: session)
        guard session.update(hover: hover, at: now) else { return settleDrag(now: now) }
        var effects: [ArrangerEffect] = []
        if session.shown != nil {
            effects.append(.preview(nil, displayUUID: session.shownOn))
            session.shown = nil
            session.shownOn = nil
        }
        drag = session
        return effects + (nextWake.map { [.wake(at: $0)] } ?? [])
    }

    /// Runs the dry run once the hover has held for the dwell, and shows (or moves) the preview it gives.
    private mutating func settleDrag(now: ContinuousClock.Instant) -> [ArrangerEffect] {
        guard var session = drag, session.kind == .move else { return [] }
        let window = session.window
        _ = session.settle(at: now) { decide($0, window: window) }
        let frame = windows[window.identity]?.frame ?? session.startFrame
        let preview = session.decision.flatMap { decision in decision.clampInto.map { .clamp(Planner.clamp(frame, into: $0)) } ?? decision.preview }
        guard let decision = session.decision, preview != session.shown else {
            drag = session
            return []
        }
        session.shown = preview
        session.shownOn = decision.display
        drag = session
        return [.preview(preview, displayUUID: decision.display)]
    }

    /// What the pointer is over, reduced to what decides the drop (UI-SPEC Surface 2): the dwell restarts only when this
    /// changes. A docked window over its own tile, and any tile centre, are a miss.
    private mutating func hover(for session: DragSession) -> Hover {
        let window = session.window
        guard let ownKey = deskKey(of: window), let ownDesk = world[ownKey], let ownPlan = dragPlan(.desk(ownKey)) else { return Hover() }
        let docked = ownDesk.tree.state(of: window) != nil
        let frame = windows[window.identity]?.frame ?? session.startFrame
        let point = session.pointer
        let display = displays.first { $0.frame.contains(point) }
        var target: DropTarget?
        if let display, let plan = dragPlan(.desk(Self.key(display))) {
            let key = Self.key(display)
            target = DropZones.target(at: point, in: display.visibleFrame, tree: (world[key] ?? Desk()).tree, resolution: plan.resolution)
            switch target {
            case .tile(_, .center)?: target = nil  // tab groups from a centre drop are Phase 7 (D-02)
            case .tile(let id, _)? where docked && key == ownKey && id == ownDesk.tree.leaf(containing: window): target = nil
            default: break
            }
        }
        return Hover(
            displayUUID: display?.uuid, target: target,
            crossesTiles: !docked && target == nil && Self.crosses(frame, ownPlan, except: window))
    }

    /// The dry run for one held hover: a copy of the World with the drop applied, then planned.
    private mutating func decide(_ hover: Hover, window: WindowRef) -> Decision {
        guard let ownKey = deskKey(of: window) else { return Decision(action: .miss) }
        let miss = Decision(action: .miss, display: ownKey.displayUUID)
        guard let target = hover.target, let uuid = hover.displayUUID, let display = displays.first(where: { $0.uuid == uuid }) else {
            return miss
        }
        let key = Self.key(display)
        do throws(LayoutError) {
            guard let desk = try dropping(window, on: key, at: target).world[key] else { return miss }
            let plan = try Planner.plan(desk: desk, area: display.visibleFrame, gap: gap, mins: minimums)
            guard plan.unfit.isEmpty, let frame = plan.frames[window] else { return miss }
            return Decision(preview: .dock(frame), action: .dock(key, target), display: uuid)
        } catch {
            return miss  // the target went stale since the hit test
        }
    }

    /// The World and history with `window` taken off its desk and dropped on `key`'s at `target`: one undo step there.
    private func dropping(_ window: WindowRef, on key: DeskKey, at target: DropTarget) throws(LayoutError) -> (world: World, history: UndoHistory) {
        var candidate = world, candidateHistory = history
        if let from = deskKey(of: window), from != key {
            // Leaving another display's desk is a fact of where it was dropped, not a second undo step.
            try candidate.reflow(from) { desk, _ throws(LayoutError) in
                if desk.desktop.contains(window) { try desk.desktop.remove(window) } else { try desk.tree.remove(window) }
            }
            if candidate[key] == nil { try candidate.addDesk(key) }
        }
        try candidate.edit(key, history: &candidateHistory) { desk, ids throws(LayoutError) in
            if desk.desktop.contains(window) {
                try desk.desktop.remove(window)
            } else if desk.tree.state(of: window) != nil {
                try desk.tree.remove(window)
            }
            try desk.tree.applyDrop(target, window: window, ids: &ids)
        }
        return (candidate, candidateHistory)
    }

    /// Mouse-up: applies exactly the decision whose preview is on screen; with none, the miss rules (WYSIWYG).
    private mutating func release(now: ContinuousClock.Instant) -> [ArrangerEffect] {
        guard let session = drag else { return [] }
        var effects = endDrag()
        let window = session.window
        guard let kind = session.kind, windows[window.identity]?.isExcluded == false, deskKey(of: window) != nil else { return effects }
        let action = kind == .move ? session.decision?.action ?? .miss : .miss
        do throws(LayoutError) {
            switch action {
            case .dock(let key, let target): effects += try commitDock(window, on: key, at: target)
            case .swap, .undock, .refuse, .miss: effects += try missed(window)
            }
        } catch {
            effects += [.fault("drop of \(window) failed: \(error)")] + replan()
        }
        return effects
    }

    private mutating func commitDock(_ window: WindowRef, on key: DeskKey, at target: DropTarget) throws(LayoutError) -> [ArrangerEffect] {
        let candidate = try dropping(window, on: key, at: target)
        guard let area = display(for: key)?.visibleFrame, let desk = candidate.world[key],
            try Planner.plan(desk: desk, area: area, gap: gap, mins: minimums).unfit.isEmpty
        else { return [.announce(Self.noRoom)] + (try missed(window)) }
        world = candidate.world
        history = candidate.history
        lastRequested[window.identity] = nil
        return replan()
    }

    /// The miss rules (D-01, D-06): a docked window snaps back to its tile; a floating one stays where it was released,
    /// clamped into the Desktop rect if it crosses a docked tile, and moves to the desk of the display it is now on.
    private mutating func missed(_ window: WindowRef) throws(LayoutError) -> [ArrangerEffect] {
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
        return replan()
    }

    private mutating func dragPlan(_ key: DragPlanKey) -> FramePlan? {
        if let plan = dragPlans[key] { return plan }
        let plan: FramePlan?
        switch key {
        case .desk(let desk):
            // A desk that cannot be planned has no drop targets; replan reports the same fault.
            plan = display(for: desk).flatMap { try? Planner.plan(desk: world[desk] ?? Desk(), area: $0.visibleFrame, gap: gap, mins: minimums) }
        }
        dragPlans[key] = plan
        return plan
    }

    /// `frame` overlaps a docked tile of `plan` other than `window`'s own.
    private static func crosses(_ frame: Rect, _ plan: FramePlan, except window: WindowRef) -> Bool {
        plan.resolution.windowRects.contains { $0.key != window && $0.value.overlaps(frame) }
    }

    // MARK: Planning

    /// Plans every desk shown on a display and writes only the frames that changed by more than 0.5 pt. Docked
    /// windows left without room float first, and are named in one notice (D-26). A hidden Desktop's floating windows
    /// are parked once each, first in the perform, and only after an immediate save holding their home frames (D-16).
    private mutating func replan() -> [ArrangerEffect] {
        guard !sessionPaused, pauseReasons.isEmpty else { return [] }
        var parks: [WindowCommand] = []
        var parkedNow: Set<WindowIdentity> = []
        var commands: [WindowCommand] = []
        var faults: [ArrangerEffect] = []
        var planned: Set<WindowIdentity> = []
        var lost: [WindowRef] = []
        let mins = minimums
        for display in displays {
            let key = Self.key(display)
            guard world[key] != nil else { continue }
            let plan: FramePlan
            do throws(LayoutError) {
                let floated: [WindowRef]
                (plan, floated) = try planFloatingLostRoom(key, area: display.visibleFrame, mins: mins)
                lost += floated
            } catch {
                faults.append(.fault("could not plan \(key): \(error)"))
                continue
            }
            guard let desk = world[key] else { continue }
            // Pane never moves an excluded app's window: no clamp, no park (D-29).
            var desired = plan.frames.filter { windows[$0.key.identity]?.isExcluded != true }
            let desktopHidden = desk.tree.isDesktopHidden == true
            for window in plan.parks where windows[window.identity]?.isExcluded != true {
                parkedNow.insert(window.identity)
                guard parkRequested.insert(window.identity).inserted else { continue }
                if homeFrames[window.identity] == nil, windows[window.identity]?.isExcluded != true {
                    homeFrames[window.identity] = desk.desktop.frame(of: window)
                }
                parks.append(.park(window, displayUUID: display.uuid))
            }
            // Home frames are only for parked windows; on a shown Desktop they are spent.
            if !desktopHidden { for floating in desk.desktop.windows { homeFrames[floating.window.identity] = nil } }
            // A floating window not where the model has it (after Float, Undo or Show Desktop) is moved there.
            for floating in desk.desktop.windows
            where !desktopHidden && floating.state == .present && desired[floating.window] == nil
                && windows[floating.window.identity]?.isExcluded != true
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
            }
        }
        // A window that left the plan (absent, fullscreen, floating clear of tiles) is written again when it returns.
        // A present window on a desk whose Space is not shown keeps its entry, so showing it again re-sends nothing.
        let shown = Set(displays.map(Self.key))
        let hidden = Set(world.desks.filter { !shown.contains($0.key) }.values.flatMap { desk in
            (desk.tree.windows + desk.desktop.windows.map(\.window)).filter { desk.state(of: $0) == .present }.map(\.identity)
        })
        lastRequested = lastRequested.filter { planned.contains($0.key) || hidden.contains($0.key) }
        parkRequested = parkRequested.filter { parkedNow.contains($0) || hidden.contains($0) }
        commands = parks + commands
        return faults + (parks.isEmpty ? [] : [.save(.now)]) + (commands.isEmpty ? [] : [.perform(commands)])
            + (lost.isEmpty ? [] : [.notice(.lostRoom(lost.sorted { $0.identity < $1.identity }))])
    }

    /// Plans `key`'s desk after floating every docked window it has no room for (D-26). A floated window's minimum
    /// sizes the Desktop tile, which can leave a neighbour without room in turn, so this repeats until all fit. Each
    /// float is an OS fact (`World.reflow`, no undo step), at the window's current frame clamped into the Desktop
    /// rect it leaves. Dock and drops refuse up front, so this only runs for changes after a window docked.
    private mutating func planFloatingLostRoom(
        _ key: DeskKey, area: Rect, mins: [WindowRef: Size]
    ) throws(LayoutError) -> (FramePlan, [WindowRef]) {
        guard let desk = world[key] else { throw .deskNotFound(key) }
        var plan = try Planner.plan(desk: desk, area: area, gap: gap, mins: mins)
        var lost: [WindowRef] = []
        // Each pass takes at least one window out of the tree, so this ends.
        while !plan.unfit.isEmpty {
            var unfit: [(WindowRef, Rect)] = []
            for window in plan.unfit.sorted(by: { $0.identity < $1.identity }) {
                guard let frame = windows[window.identity]?.frame else { throw .windowNotFound(window) }
                unfit.append((window, frame))
            }
            let gap = gap
            try world.reflow(key) { desk, _ throws(LayoutError) in
                for (window, frame) in unfit {
                    try desk.tree.remove(window)
                    try desk.desktop.add(window, frame: frame)
                }
                let desktop = try Planner.plan(desk: desk, area: area, gap: gap, mins: mins).desktopRect ?? area
                for (window, frame) in unfit { try desk.desktop.setFrame(Planner.clamp(frame, into: desktop), for: window) }
            }
            lost += unfit.map(\.0)
            guard let desk = world[key] else { throw .deskNotFound(key) }
            plan = try Planner.plan(desk: desk, area: area, gap: gap, mins: mins)
        }
        return (plan, lost)
    }

    /// Excluded windows have none: they never dock, and the Desktop tile is not sized for them.
    private var minimums: [WindowRef: Size] {
        Dictionary(
            windows.values.compactMap { info in info.isExcluded ? nil : info.learnedMinimum.map { (info.window, $0) } }, uniquingKeysWith: { $1 })
    }

    private func display(for key: DeskKey) -> DisplayInfo? {
        displays.first { Self.key($0) == key }
    }

    /// The desk shown on `display` right now.
    private static func key(_ display: DisplayInfo) -> DeskKey {
        DeskKey(displayUUID: display.uuid, spaceID: display.currentSpaceID)
    }

    private static func near(_ a: Rect, _ b: Rect, within tolerance: Double = 0.5) -> Bool {
        abs(a.x - b.x) <= tolerance && abs(a.y - b.y) <= tolerance && abs(a.width - b.width) <= tolerance
            && abs(a.height - b.height) <= tolerance
    }
}

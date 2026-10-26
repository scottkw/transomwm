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
        return world == before ? effects : effects + [.save(.debounced)]
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
        guard context.ready else { return false }
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
            if case .windowChanged(let info) = event { try rehome(info) }
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
        guard let key = deskKey(of: window), let desk = world[key] else { return [] }
        let floating = desk.desktop.contains(window)
        // A parked window keeps its Desktop frame: the move is the park, and showing the Desktop brings it back there.
        if floating, desk.tree.isDesktopHidden == true { return [] }
        if floating { try world.recordFloatingFrame(frame, for: window) }
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
        return missed + effects + (nextWake.map { [.wake(at: $0)] } ?? [])
    }

    /// Forgets the tile last sent, so the re-plan writes it again.
    private mutating func correct(_ ids: Set<WindowIdentity>, now: ContinuousClock.Instant) -> [ArrangerEffect] {
        for id in ids {
            lastCorrection[id] = now
            lastRequested[id] = nil
        }
        return replan()
    }

    /// The earliest instant a waiting correction is due.
    /// The earliest instant a waiting correction or the Finder deadline is due: the shell keeps one wake only.
    private var nextWake: ContinuousClock.Instant? {
        (pendingCorrections.compactMap { lastCorrection[$0].map { $0 + Self.correctionInterval } } + [finderExpectation?.deadline].compactMap { $0 }).min()
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

    // MARK: Planning

    /// Plans every desk shown on a display and writes only the frames that changed by more than 0.5 pt. Docked
    /// windows left without room float first, and are named in one notice (D-26). A hidden Desktop's floating windows
    /// are parked once each, first in the perform, and only after an immediate save holding their home frames (D-16).
    private mutating func replan() -> [ArrangerEffect] {
        guard !sessionPaused else { return [] }
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
            var desired = plan.frames
            let desktopHidden = desk.tree.isDesktopHidden == true
            for window in plan.parks {
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
            for floating in desk.desktop.windows where !desktopHidden && floating.state == .present && desired[floating.window] == nil {
                if let actual = windows[floating.window.identity]?.frame, !Self.near(actual, floating.frame) {
                    desired[floating.window] = floating.frame
                }
            }
            for (window, rect) in desired.sorted(by: { $0.key.identity < $1.key.identity }) {
                planned.insert(window.identity)
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

    private var minimums: [WindowRef: Size] {
        Dictionary(windows.values.compactMap { info in info.learnedMinimum.map { (info.window, $0) } }, uniquingKeysWith: { $1 })
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

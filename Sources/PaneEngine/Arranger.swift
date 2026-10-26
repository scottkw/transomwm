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
}

/// The pure layout owner (RESEARCH Pattern 1): window-system inputs and user commands in, commands and effects out.
/// It never sleeps and never touches the OS; `ArrangeController` (PaneMac) and the tests drive it the same way.
/// OS facts change the World through `LifecycleSync` and `World.reflow`, user commands through `World.edit`.
public struct Arranger: Sendable {
    public static let noRoom = "Not enough room to dock here"

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
                case (.dock, nil), (.float, nil): return [.beep]
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

    /// Whether `command` can act now: the same rule greys menu items and makes a refused hotkey beep.
    public func isAvailable(_ command: Command, focused: WindowRef?) -> Bool {
        switch command {
        case .dock:
            guard let focused, let info = windows[focused.identity], info.kind == .dockable, !info.isExcluded,
                info.state == .present
            else { return false }
            return world.desks.values.contains { $0.desktop.contains(focused) && $0.state(of: focused) == .present }
        case .float:
            guard let focused else { return false }
            return world.desks.values.contains { $0.tree.state(of: focused) != nil }
        case .undo:
            return undoKey(focused).map { history.depth(for: $0) > 0 } ?? false
        }
    }

    /// The focused window's desk or, with none focused (or one on no desk), the main display's visible desk.
    private func undoKey(_ focused: WindowRef?) -> DeskKey? {
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
            case .windowFocused, .appResponsiveness, .appLaunched, .appTerminated, .displaysChanged:
                break
            }
            _ = try LifecycleSync.handle(event, world: &world, history: &history)
            if case .windowChanged(let info) = event { try rehome(info) }
            // A window that just became dockable, present or known floats on its display's Desktop (D-24).
            if let subject, let info = windows[subject] { try admit(info) }
        } catch {
            return [.fault("ignored an event: \(error)")]
        }
        return replan()
    }

    private mutating func forget(_ window: WindowRef) {
        windows[window.identity] = nil
        lastRequested[window.identity] = nil
        lastApplied[window.identity] = nil
        lastCorrection[window.identity] = nil
        pendingCorrections.remove(window.identity)
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
        let due = pendingCorrections.filter { id in lastCorrection[id].map { now >= $0 + Self.correctionInterval } ?? true }
        pendingCorrections.subtract(due)
        let off = due.filter { id in
            guard let info = windows[id], let tile = lastRequested[id] else { return false }
            return world.desks.values.contains { $0.tree.state(of: info.window) == .present } && !Self.near(info.frame, tile, within: 2)
        }
        let effects = off.isEmpty ? [] : correct(off, now: now)
        return effects + (nextWake.map { [.wake(at: $0)] } ?? [])
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
    private var nextWake: ContinuousClock.Instant? {
        pendingCorrections.compactMap { lastCorrection[$0].map { $0 + Self.correctionInterval } }.min()
    }

    /// Puts a dockable, present, non-excluded window that no desk holds on its own Space's Desktop layer, at its own
    /// frame. Never docks it (TILE-07). Creates the desk the first time such a window is seen there, so a fullscreen
    /// Space, which holds no present window, never gets one (WIN-07).
    private mutating func admit(_ info: WindowInfo) throws(LayoutError) {
        guard info.kind == .dockable, !info.isExcluded, info.state == .present, deskKey(of: info.window) == nil,
            let key = home(of: info)
        else { return }
        if world[key] == nil { try world.addDesk(key) }
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
        guard info.state == .present, let from = deskKey(of: info.window), world[from]?.state(of: info.window) == .present,
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
        try world.edit(key, history: &history) { desk, _ throws(LayoutError) in
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
        guard let key = undoKey(focused), let revived = try LifecycleSync.undo(key, world: &world, history: &history) else {
            return [.beep]
        }
        return revived.windows.isEmpty ? replan() : [.requery(revived)]
    }

    // MARK: Planning

    /// Plans every desk shown on a display and writes only the frames that changed by more than 0.5 pt. Docked
    /// windows left without room float first, and are named in one notice (D-26).
    private mutating func replan() -> [ArrangerEffect] {
        guard !sessionPaused else { return [] }
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
            // A floating window not where the model has it (after Float or Undo) is moved there.
            for floating in desk.desktop.windows where floating.state == .present && desired[floating.window] == nil {
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
        return faults + (commands.isEmpty ? [] : [.perform(commands)])
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

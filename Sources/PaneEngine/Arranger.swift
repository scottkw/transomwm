import PaneModel

/// Everything the Arranger reacts to. `requeried` carries the real states of windows an undo revived (D-11).
public enum ArrangerInput: Sendable {
    case inventory(WindowInventory)
    case event(WindowEvent)
    case command(Command, focused: WindowRef?)
    case requeried(RevivedWindows, [(WindowRef, WindowState)])
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
    public var gap: Double
    /// The last frame requested for each window that is still planned; a frame within 0.5 pt of it is not written
    /// again, so an app echoing frames cannot cause a write storm (T-03-08).
    private var lastRequested: [WindowIdentity: Rect] = [:]
    /// Locked or asleep: nothing is written until the session resumes, then every visible desk is re-planned.
    private var sessionPaused = false
    /// The Spaces-off fallback (A7) is reported once per session.
    private var reportedSpacesOff = false

    public init(gap: Double = 8) {
        self.gap = gap
    }

    public mutating func handle(_ input: ArrangerInput, now: ContinuousClock.Instant) -> [ArrangerEffect] {
        switch input {
        case .inventory(let inventory):
            displays = inventory.displays
            sessionPaused = inventory.sessionPaused
            windows = Dictionary(inventory.windows.map { ($0.window.identity, $0) }, uniquingKeysWith: { $1 })
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
        case .event(let event):
            return handle(event)
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

    private mutating func handle(_ event: WindowEvent) -> [ArrangerEffect] {
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
                subject = to.window.identity
            case .windowMoved(let window, let frame), .windowResized(let window, let frame):
                windows[window.identity]?.frame = frame
                // A floating window's frame is a fact (TILE-07): recorded with no undo step.
                if world.desks.values.contains(where: { $0.desktop.contains(window) }) { try world.recordFloatingFrame(frame, for: window) }
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
            case .windowFocused, .frameApplied, .appResponsiveness, .appLaunched, .appTerminated, .displaysChanged:
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

    /// Plans every desk shown on a display and writes only the frames that changed by more than 0.5 pt.
    private mutating func replan() -> [ArrangerEffect] {
        guard !sessionPaused else { return [] }
        var commands: [WindowCommand] = []
        var faults: [ArrangerEffect] = []
        var planned: Set<WindowIdentity> = []
        let mins = minimums
        for display in displays {
            let key = Self.key(display)
            guard let desk = world[key] else { continue }
            let plan: FramePlan
            do throws(LayoutError) {
                plan = try Planner.plan(desk: desk, area: display.visibleFrame, gap: gap, mins: mins)
            } catch {
                faults.append(.fault("could not plan \(key): \(error)"))
                continue
            }
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

    private static func near(_ a: Rect, _ b: Rect) -> Bool {
        abs(a.x - b.x) <= 0.5 && abs(a.y - b.y) <= 0.5 && abs(a.width - b.width) <= 0.5 && abs(a.height - b.height) <= 0.5
    }
}

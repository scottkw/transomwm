import TransomModel

/// Windows an undo of `key`'s desk brought back that no desk held before it. Their states are the
/// snapshot's and may be stale until re-queried (D-11).
public struct RevivedWindows: Equatable, Sendable {
    public let key: DeskKey
    public let windows: [WindowRef]

    public init(key: DeskKey, windows: [WindowRef]) {
        self.key = key
        self.windows = windows
    }
}

/// The one path from OS lifecycle facts into the layout model (D-10). Every change goes through
/// `World.apply` or `World.rekey`, never `World.edit`, so no OS fact ever lands on the user's undo stack.
/// No state of its own.
public enum LifecycleSync {
    /// Applies a lifecycle event to `world`. Returns true when the event was applied: a state change for a
    /// window some desk holds, any close, or any rekey. A close always applies, even for a window no desk holds, so
    /// it is purged from every undo snapshot; a rekey likewise always re-points the snapshots (`World.rekey`).
    /// Every other event, and a state change for a window on no desk, returns false and leaves `world` and
    /// `history` untouched. A throw from `World.apply` or `World.rekey` leaves both unchanged.
    public static func handle(_ event: WindowEvent, world: inout World, history: inout UndoHistory) throws(LayoutError) -> Bool {
        switch event {
        case .windowDestroyed(let window), .windowStateChanged(let window, .closed):
            // World.apply ignores the key for .closed and closes the window wherever it is, so any key will do.
            try world.apply(.closed, for: window, on: DeskKey(displayUUID: "", spaceID: nil), history: &history)
            return true
        case .windowStateChanged(let window, let state):
            guard let key = world.desks.keys.sorted().first(where: { world.desks[$0]?.contains(window) == true }) else {
                return false
            }
            try world.apply(state, for: window, on: key, history: &history)
            return true
        case .windowRekeyed(let from, let to):
            // An ID correction is an OS fact too: World.rekey re-points the desks and every undo snapshot, no undo step.
            try world.rekey(from: from, to: to.window, history: &history)
            return true
        case .windowCreated, .windowMoved, .windowResized, .windowFocused, .windowChanged, .frameApplied,
             .appResponsiveness, .sessionPaused, .appLaunched, .appTerminated, .displaysChanged, .spaceChanged, .liveWindowsChanged:
            return false
        }
    }

    /// Undoes the newest user edit on `key`'s desk. Returns nil when there is nothing to undo. Otherwise the
    /// revived windows carry their snapshot states, which may be stale (D-11): callers must run `requery` and
    /// then `applyRequeried` for them before trusting their states. The steps are split so a caller holding
    /// the World in an actor never passes actor state inout across the `await`.
    public static func undo(_ key: DeskKey, world: inout World, history: inout UndoHistory) throws(LayoutError) -> RevivedWindows? {
        guard let windows = try world.undo(key, history: &history) else { return nil }
        return RevivedWindows(key: key, windows: windows)
    }

    /// Each revived window's real state, in order: what the window system reports, or `.closed` when it no
    /// longer knows the window (it returns nil only for one never seen or confirmed closed by two sources).
    public static func requery(_ revived: RevivedWindows, using system: any WindowSystem) async -> [(WindowRef, WindowState)] {
        var states: [(WindowRef, WindowState)] = []
        for window in revived.windows {
            states.append((window, await system.windowInfo(window)?.state ?? .closed))
        }
        return states
    }

    /// Reports re-queried states through `World.apply`, in order. A `.closed` pair removes the window and
    /// purges it from history (the key is ignored for it).
    public static func applyRequeried(
        _ states: [(WindowRef, WindowState)], on key: DeskKey, world: inout World, history: inout UndoHistory
    ) throws(LayoutError) {
        for (window, state) in states {
            try world.apply(state, for: window, on: key, history: &history)
        }
    }
}

import PaneModel

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
/// `World.apply`, never `World.edit`, so no OS fact ever lands on the user's undo stack. No state of its own.
public enum LifecycleSync {
    /// Applies a lifecycle event to `world`. Returns true when the event was applied: a state change for a
    /// window some desk holds, or any close. A close always applies, even for a window no desk holds, so it is
    /// purged from every undo snapshot. Every other event, and a state change for a window on no desk, returns
    /// false and leaves `world` and `history` untouched. A throw from `World.apply` leaves both unchanged.
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
        case .windowCreated, .windowMoved, .windowResized, .windowFocused, .windowChanged, .frameApplied,
             .appResponsiveness, .sessionPaused, .appLaunched, .appTerminated, .displaysChanged, .spaceChanged:
            return false
        }
    }

    public static func undo(_ key: DeskKey, world: inout World, history: inout UndoHistory) throws(LayoutError) -> RevivedWindows? {
        nil
    }

    public static func requery(_ revived: RevivedWindows, using system: any WindowSystem) async -> [(WindowRef, WindowState)] {
        []
    }

    public static func applyRequeried(
        _ states: [(WindowRef, WindowState)], on key: DeskKey, world: inout World, history: inout UndoHistory
    ) throws(LayoutError) {}
}

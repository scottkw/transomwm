import PaneModel

/// Re-attach by identity (SAFE-06, D-17, RESEARCH Pattern 10). Pure: the Arranger runs it once, at the first complete
/// inventory after a `.restore`.
public enum LayoutRestore {
    /// Keeps a saved window only when a tracked window has the same identity and a real ID: synthetic IDs are
    /// session-only (02-11), so one from another session never claims a window. Every other saved window is removed
    /// through the close path (`World.apply(.closed, …)` with a throwaway history). `unplaced` are the tracked dockable,
    /// present, non-excluded windows no desk holds afterwards; the caller floats them on their desk's Desktop.
    /// Throws only if closing a saved window leaves an invalid World; the caller then starts empty.
    public static func reattach(
        _ saved: World, tracked: [WindowInfo]
    ) throws(LayoutError) -> (world: World, removed: [WindowRef], unplaced: [WindowInfo]) {
        let real = Set(tracked.filter { $0.idSource != .synthetic }.map(\.window.identity))
        var world = saved
        var history = UndoHistory()
        var removed: [WindowRef] = []
        for (_, desk) in saved.desks.sorted(by: { $0.key < $1.key }) {
            for window in desk.tree.windows + desk.desktop.windows.map(\.window) where !real.contains(window.identity) {
                try world.apply(.closed, for: window, on: DeskKey(displayUUID: "", spaceID: nil), history: &history)
                removed.append(window)
            }
        }
        let placed = Set(world.desks.values.flatMap { $0.tree.windows + $0.desktop.windows.map(\.window) }.map(\.identity))
        let unplaced = tracked.filter {
            $0.kind == .dockable && $0.state == .present && !$0.isExcluded && !placed.contains($0.window.identity)
        }
        return (world, removed, unplaced)
    }
}

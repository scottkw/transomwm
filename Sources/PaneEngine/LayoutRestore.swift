import PaneModel

/// Re-attach by identity (SAFE-06, RESEARCH Pattern 10).
public enum LayoutRestore {
    public static func reattach(_ saved: World, tracked: [WindowInfo]) throws(LayoutError) -> (world: World, removed: [WindowRef], unplaced: [WindowInfo]) {
        (saved, [], [])  // RED stub
    }
}

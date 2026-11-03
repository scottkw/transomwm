import TransomModel

/// Re-attach by identity (SAFE-06, D-17, RESEARCH Pattern 10), then by hints (D-10, VIEW-04). Pure: the Arranger runs it
/// once, at the first complete inventory after a `.restore`.
public enum LayoutRestore {
    /// Keeps a saved window when a tracked window has the same identity and a real ID, or when `isAlive` holds for it
    /// in `live`; a nil `live` (unknown) keeps every saved window. A kept untracked window stays dormant in its desk (a
    /// window on a Space not shown at launch, G-03-8) until its first windowCreated. Synthetic IDs are session-only
    /// (02-11), so one from another session never claims a window. Every other saved window (one whose app relaunched
    /// has a new pid) goes to `HintMatcher` against the tracked windows no saved window holds, with its frame from
    /// `savedFrames`; a match re-points the saved window to the returning one, keeping its tile. `skipIdentity` (the boot
    /// session changed, so IDs may be reused, RESEARCH Pitfall 5) sends every saved window to the matcher. Each unmatched
    /// saved window is removed through the close path (`World.apply(.closed, …)` with a throwaway history). `unplaced`
    /// are the tracked dockable, present, non-excluded windows no desk holds afterwards; the caller floats them on their
    /// desk's Desktop. Throws only if closing or re-pointing a saved window leaves an invalid World; the caller then
    /// starts empty.
    public static func reattach(
        _ saved: World, tracked: [WindowInfo], live: [CGWindowEntry]? = [], savedFrames: [WindowIdentity: Rect] = [:],
        skipIdentity: Bool = false
    ) throws(LayoutError) -> (
        world: World, removed: [WindowRef], unplaced: [WindowInfo], matches: [HintMatcher.Match], ties: [HintMatcher.Tie]
    ) {
        let real = skipIdentity ? [] : Set(tracked.filter { $0.idSource != .synthetic }.map(\.window.identity))
        var world = saved
        var history = UndoHistory()
        let all = saved.desks.sorted { $0.key < $1.key }.flatMap { $0.value.tree.windows + $0.value.desktop.windows.map(\.window) }
        let unattached = all.filter {
            !real.contains($0.identity) && (skipIdentity || live.map { [identity = $0.identity] in !isAlive(identity, in: $0) } ?? false)
        }
        let held = Set(all.map(\.identity)).subtracting(unattached.map(\.identity))
        let eligible = tracked.filter { $0.kind == .dockable && $0.state == .present && !$0.isExcluded }
        let assigned = HintMatcher.assign(
            saved: unattached.map { HintMatcher.Saved(ref: $0, frame: savedFrames[$0.identity]) },
            candidates: eligible.filter { !held.contains($0.window.identity) }.map { HintMatcher.Candidate(ref: $0.window, frame: $0.frame) })
        let matched = Set(assigned.matches.map(\.saved))
        var removed: [WindowRef] = []
        for window in unattached where !matched.contains(window) {
            try world.apply(.closed, for: window, on: DeskKey(displayUUID: "", spaceID: nil), history: &history)
            removed.append(window)
        }
        // Through a placeholder identity first: with `skipIdentity` a returning window can carry another saved one's ID.
        let parked = assigned.matches.indices.map { WindowRef(identity: WindowIdentity(windowID: UInt32($0), pid: -1, bundleID: "")) }
        for (match, temp) in zip(assigned.matches, parked) { try world.rekey(from: match.saved, to: temp, history: &history) }
        for (match, temp) in zip(assigned.matches, parked) { try world.rekey(from: temp, to: match.window, history: &history) }
        let placed = Set(world.desks.values.flatMap { $0.tree.windows + $0.desktop.windows.map(\.window) }.map(\.identity))
        let unplaced = eligible.filter { !placed.contains($0.window.identity) }
        return (world, removed, unplaced, assigned.matches, assigned.ties)
    }

    /// Whether a CG window at layer 0 has this identity's real window ID and pid, on a Space when its Spaces are known:
    /// the window is still open, even on a Space AX does not list. An entry on no Space is a closed window's lingering
    /// one (Safari, G-03-9). Never true for a synthetic ID.
    public static func isAlive(_ identity: WindowIdentity, in live: [CGWindowEntry]) -> Bool {
        !identity.isSyntheticWindowID && live.contains {
            $0.layer == 0 && $0.windowID == identity.windowID && $0.pid == identity.pid && $0.spaces?.isEmpty != true
        }
    }
}

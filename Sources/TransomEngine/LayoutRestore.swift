import TransomModel

/// Re-attach by identity (SAFE-06, D-17, RESEARCH Pattern 10), then by hints (D-10, VIEW-04). Pure: the Arranger runs it
/// once, at the first complete inventory after a `.restore`.
public enum LayoutRestore {
    /// Keeps a saved window when a tracked window has the same identity and a real ID, or when `isAlive` holds for it
    /// in `live`; a nil `live` (unknown) keeps every saved window. A kept untracked window stays dormant in its desk (a
    /// window on a Space not shown at launch, G-03-8) until its first windowCreated. Synthetic IDs are session-only
    /// (02-11), so one from another session never claims a window. Every other saved window (one whose app relaunched
    /// has a new pid) goes to `HintMatcher` against the tracked windows no saved window holds, with its frame from
    /// `savedFrames` and its desk (`shownDesks` are those on screen); a match re-points the saved window to the returning
    /// one, keeping its tile. A retired window (`retire`) always goes to the matcher. Each unmatched
    /// saved window stays in the World and is returned in `waiting`, docked or floating, for the caller to hold until its
    /// deadline (D-12), or to close. `removed` are the unmatched ones a tracked window now carries the identity of (a reused
    /// or synthetic ID): the identity can't mean both, so they go through the close path (`World.apply(.closed, …)` with a
    /// throwaway history). shortcut: such a tile closes instead of waiting; re-point it to a free identity if that is ever
    /// seen outside a reboot's rare collision. `unplaced` are the tracked dockable, present, non-excluded windows no desk
    /// holds afterwards; the caller floats them on their desk. Throws only if closing or re-pointing a saved
    /// window leaves an invalid World; the caller then starts empty.
    public static func reattach(
        _ saved: World, tracked: [WindowInfo], live: [CGWindowEntry]? = [], savedFrames: [WindowIdentity: Rect] = [:],
        shownDesks: Set<DeskKey> = []
    ) throws(LayoutError) -> (
        world: World, waiting: [WindowRef], removed: [WindowRef], unplaced: [WindowInfo], matches: [HintMatcher.Match], ties: [HintMatcher.Tie]
    ) {
        let real = Set(tracked.filter { $0.idSource != .synthetic }.map(\.window.identity))
        var world = saved
        var history = UndoHistory()
        let all = saved.desks.sorted { $0.key < $1.key }.flatMap { $0.value.tree.windows + $0.value.desktop.windows.map(\.window) }
        let unattached = all.filter {
            !real.contains($0.identity) && ($0.identity.isRetiredWindowID || live.map { [identity = $0.identity] in !isAlive(identity, in: $0) } ?? false)
        }
        let held = Set(all.map(\.identity)).subtracting(unattached.map(\.identity))
        let eligible = tracked.filter { $0.kind == .dockable && $0.state == .present && !$0.isExcluded }
        let assigned = HintMatcher.assign(
            saved: unattached.map { window in
                HintMatcher.Saved(ref: window, frame: savedFrames[window.identity], desk: saved.desks.first { $0.value.contains(window) }?.key)
            },
            candidates: eligible.filter { !held.contains($0.window.identity) }.map {
                HintMatcher.Candidate(ref: $0.window, frame: $0.frame, displayUUID: $0.displayUUID, spaces: $0.spaces)
            },
            shown: shownDesks)
        let matched = Set(assigned.matches.map(\.saved))
        let trackedIDs = Set(tracked.map(\.window.identity))
        let unmatched = unattached.filter { !matched.contains($0) }
        let removed = unmatched.filter { trackedIDs.contains($0.identity) }
        for window in removed {
            try world.apply(.closed, for: window, on: DeskKey(displayUUID: "", spaceID: nil), history: &history)
        }
        // Through a placeholder identity first: with `skipIdentity` a returning window can carry another saved one's ID.
        let parked = assigned.matches.indices.map { WindowRef(identity: WindowIdentity(windowID: UInt32($0), pid: -1, bundleID: "")) }
        for (match, temp) in zip(assigned.matches, parked) { try world.rekey(from: match.saved, to: temp, history: &history) }
        for (match, temp) in zip(assigned.matches, parked) { try world.rekey(from: temp, to: match.window, history: &history) }
        let placed = Set(world.desks.values.flatMap { $0.tree.windows + $0.desktop.windows.map(\.window) }.map(\.identity))
        let unplaced = eligible.filter { !placed.contains($0.window.identity) }
        return (world, unmatched.filter { !trackedIDs.contains($0.identity) }, removed, unplaced, assigned.matches, assigned.ties)
    }

    /// After a reboot a saved ID and pid name no window, and may name another one (RESEARCH Pitfall 5): each saved window,
    /// in the World and every stored layout set alike, takes a retired identity, keeping its bundle and hints, so it can
    /// only come back through `HintMatcher`. layout.json then holds no old-boot identity from the first write on, so it can
    /// say this boot at once (WR-01). Sorted order is kept. One retired by an earlier boot stays as it is. Throws only if
    /// re-pointing leaves an invalid World.
    public static func retire(
        _ world: World, homeFrames: [WindowIdentity: Rect], wantedFrames: [WindowIdentity: Rect], sets: [LayoutSet], views: [SavedView]
    ) throws(LayoutError) -> (world: World, homeFrames: [WindowIdentity: Rect], wantedFrames: [WindowIdentity: Rect], sets: [LayoutSet], views: [SavedView]) {
        func held(_ world: World) -> [WindowRef] { world.desks.values.flatMap { $0.tree.windows + $0.desktop.windows.map(\.window) } }
        let all = Set(([world] + sets.map(\.world)).flatMap(held).map(\.identity))
        var taken = Set(all.filter(\.isRetiredWindowID).map(\.windowID))
        var next = WindowIdentity.retiredIDBase
        var retired: [WindowIdentity: WindowIdentity] = [:]
        for identity in all.sorted() {
            guard !identity.isRetiredWindowID else {
                retired[identity] = identity
                continue
            }
            while taken.contains(next) { next += 1 }  // a file under World.maxEncodedBytes can't hold enough to overflow
            taken.insert(next)
            retired[identity] = WindowIdentity(windowID: next, pid: -1, bundleID: identity.bundleID)
        }
        func repointed(_ world: World) throws(LayoutError) -> World {
            var world = world, history = UndoHistory()
            for window in held(world) {
                guard let identity = retired[window.identity] else { continue }
                let to = WindowRef(identity: identity, titleHint: window.titleHint, axIdentifier: window.axIdentifier, creationOrder: window.creationOrder)
                try world.rekey(from: window, to: to, history: &history)
            }
            return world
        }
        func mapped(_ frames: [WindowIdentity: Rect]) -> [WindowIdentity: Rect] {
            Dictionary(uniqueKeysWithValues: frames.compactMap { id, frame in retired[id].map { ($0, frame) } })
        }
        var newSets: [LayoutSet] = []
        for set in sets { newSets.append(LayoutSet(arrangement: set.arrangement, world: try repointed(set.world), lastUsed: set.lastUsed)) }
        let newViews = views.map { SavedView(slot: $0.slot, desk: $0.desk, home: $0.home, windows: $0.windows.compactMap { retired[$0] }) }
        return (try repointed(world), mapped(homeFrames), mapped(wantedFrames), newSets, newViews)
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

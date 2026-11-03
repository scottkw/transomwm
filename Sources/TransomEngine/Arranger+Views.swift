import TransomModel

/// Saved views (08 UI-SPEC Surface 1, D-01, D-02): a slot holds a desk and the identities of the windows inside the view,
/// and going back zooms to the smallest node holding the ones still there. Saving changes no window and no undo history.
extension Arranger {
    /// Saves that display's current view (the pending target while a move runs) into `slot`.
    mutating func saveView(_ slot: ViewSlot, displayUUID uuid: String) throws(LayoutError) -> [ArrangerEffect] {
        guard let display = displays.first(where: { $0.uuid == uuid }), let desk = world[Self.key(display)] else {
            return [.fault("save view \(slot): no desk on display \(uuid)")]
        }
        let key = Self.key(display)
        let view = currentView(uuid, key)
        var windows: [WindowIdentity] = []
        if case .node(let id) = view {
            // ViewPlanner's showsDesktop rule: a subtree holding the Desktop tile shows the Desktop layer's windows.
            let tree = try desk.tree.subtree(at: id)
            windows = tree.windows.map(\.identity) + (tree.nodes[.desktop] != nil ? desk.desktop.windows.map(\.window.identity) : [])
        }
        let replaced = camera.savedViews.save(SavedView(slot: slot, desk: key, home: view == .home, windows: windows))
        let space = key.spaceID.map(String.init) ?? "none"
        return [
            .notice(.viewSaved(slot, replaced: replaced, displayUUID: uuid)),
            .info("save view \(slot) on display \(uuid) space \(space): \(view == .home ? "home" : "\(windows.count) windows")\(replaced ? ", replaced" : "")"),
        ]
    }

    /// Where `view` takes the camera (RESEARCH Pattern 1): the desk holding most of its surviving windows (ties to the
    /// saved desk) and the smallest node holding them there; the saved desk's home for a home view or when none survive.
    func viewDestination(_ view: SavedView) -> (key: DeskKey, target: ViewTarget, allGone: Bool) {
        let alive = view.windows.compactMap { id in deskKey(of: WindowRef(identity: id)).map { (id: id, key: $0) } }
        guard !view.home, !alive.isEmpty else { return (view.desk, .home, !view.home) }
        let counts = Dictionary(alive.map { ($0.key, 1) }, uniquingKeysWith: +)
        // max(by:) keeps the first of equals, so a tie between two other desks goes to the smaller key.
        let rank = { (key: DeskKey) in (counts[key] ?? 0, key == view.desk ? 1 : 0) }
        guard let best = counts.keys.sorted().max(by: { rank($0) < rank($1) }), let tree = world[best]?.tree else { return (view.desk, .home, true) }
        let leaves = alive.filter { $0.key == best }.compactMap { leafNode(of: WindowRef(identity: $0.id)) }
        return (best, Navigator.lowestCommonAncestor(leaves, in: tree).map { Navigator.target($0, in: tree) } ?? .home, false)
    }

    /// Zooms that display's camera to the view in `slot`: one camera move, so it joins Back/Forward history (`.navigate`)
    /// and is never an undo step.
    mutating func goView(_ slot: ViewSlot, displayUUID uuid: String, focused: WindowRef?) -> [ArrangerEffect] {
        guard let saved = camera.savedViews[slot] else { return [.info("refused view \(slot): empty slot")] }
        let destination = viewDestination(saved)
        guard let display = displays.first(where: { $0.uuid == uuid }), Self.key(display) == destination.key else {
            return [.info("go view \(slot): desk \(destination.key) is not shown on display \(uuid)")]
        }
        let shown: [ArrangerEffect] = [.notice(.viewShown(slot, displayUUID: uuid))]
        // Already there: nothing moves, and it is not a refusal.
        guard destination.target != currentView(uuid, destination.key) else { return shown }
        return zoomTo(destination.target, displayUUID: uuid) + shown
    }
}

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
            // 8.1.1 D-14: floating windows are not part of a view.
            windows = try desk.tree.subtree(at: id).windows.map(\.identity)
            guard !windows.isEmpty else {
                return [.beep, .notice(.viewNothingToSave(displayUUID: uuid)), .info("refused save view \(slot): no windows in view")]
            }
        }
        let replaced = camera.savedViews.save(SavedView(slot: slot, desk: key, home: view == .home, windows: windows))
        let space = key.spaceID.map(String.init) ?? "none"
        return [
            .notice(.viewSaved(slot, replaced: replaced, displayUUID: uuid)),
            .info("save view \(slot) on display \(uuid) space \(space): \(view == .home ? "home" : "\(windows.count) windows")\(replaced ? ", replaced" : "")"),
            .save(.debounced),  // the World did not change, so `handle` adds none
        ]
    }

    /// A window's identity changed (a rekey, a relaunch match): the saved views follow it (D-02, RESEARCH Pitfall 3).
    mutating func remapViews(from: WindowIdentity, to: WindowIdentity) {
        camera.savedViews.remap(from: from, to: to)
    }

    /// The saved views for layout.json, without identities no desk of `worlds` holds. A view left with none keeps its slot
    /// and desk, and goes home there (D-05).
    func heldViews(in worlds: [World]) -> [SavedView] {
        let held = Set(worlds.flatMap { $0.desks.values.flatMap { $0.tree.windows + $0.desktop.windows.map(\.window) } }.map(\.identity))
        return camera.savedViews.sorted.map { SavedView(slot: $0.slot, desk: $0.desk, home: $0.home, windows: $0.windows.filter(held.contains)) }
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

    /// The destination of the view in `slot`, for the shell's Space and display switch (D-03); nil for an empty slot.
    /// `alive` are the saved windows on that desk, `total` all that were saved.
    public func viewDestination(slot: ViewSlot) -> (key: DeskKey, target: ViewTarget, allGone: Bool, alive: Int, total: Int)? {
        guard let view = camera.savedViews[slot] else { return nil }
        let destination = viewDestination(view)
        let alive = view.windows.filter { deskKey(of: WindowRef(identity: $0)) == destination.key }.count
        return (destination.key, destination.target, destination.allGone, alive, view.windows.count)
    }

    /// The filled slots, in order (the Debug line).
    public var savedViewSlots: [Int] { camera.savedViews.sorted.map(\.slot.number) }

    /// The saved view that display's camera shows (the menu bar's filled badge, D-14): the lowest slot whose destination
    /// is the shown desk and the committed view. Never one at home.
    public func currentViewSlot(displayUUID uuid: String) -> ViewSlot? {
        guard let display = displays.first(where: { $0.uuid == uuid }) else { return nil }
        let shown = view(on: uuid)
        guard shown != .home else { return nil }
        return camera.savedViews.sorted.first { (saved: SavedView) -> Bool in
            let destination = viewDestination(saved)
            return destination.key == Self.key(display) && destination.target == shown
        }?.slot
    }

    /// Zooms that display's camera to the view in `slot`: one camera move, so it joins Back/Forward history (`.navigate`)
    /// and is never an undo step.
    mutating func goView(_ slot: ViewSlot, displayUUID uuid: String, focused: WindowRef?) -> [ArrangerEffect] {
        guard let saved = camera.savedViews[slot] else {
            return [.beep, .notice(.viewEmpty(slot, displayUUID: uuid)), .info("refused view \(slot): empty slot")]
        }
        let destination = viewDestination(saved)
        guard displays.contains(where: { $0.uuid == destination.key.displayUUID }) else {
            return [.beep, .notice(.viewDisplayGone(slot, displayUUID: uuid)), .info("refused view \(slot): display not connected")]
        }
        guard let display = displays.first(where: { $0.uuid == uuid }) else { return [.beep, .info("refused view \(slot): no display \(uuid)")] }
        // The shell switches to the desk's Space first, so all gone and still not shown means that Space is gone: the
        // saved display's current Space, home.
        let key = destination.allGone && uuid == destination.key.displayUUID ? Self.key(display) : destination.key
        guard Self.key(display) == key, let tree = world[key]?.tree else {
            return [.beep, .info("refused view \(slot): desk \(key) is not shown on display \(uuid)")]
        }
        // D-05: every window gone shows the saved desk's home with N17 instead of N15; the slot stays.
        let shown: [ArrangerEffect] = [.notice(destination.allGone ? .viewWindowsClosed(slot, displayUUID: uuid) : .viewShown(slot, displayUUID: uuid))]
        // Already there: nothing moves, and it is not a refusal.
        guard destination.target != currentView(uuid, key) else { return shown }
        // Focus outside the view moves to the most recently focused window inside it.
        let node = Navigator.node(of: destination.target, in: tree)
        func inside(_ window: WindowRef) -> Bool {
            guard deskKey(of: window) == key, let leaf = leafNode(of: window), let node else { return false }
            return Navigator.ancestors(of: leaf, in: tree).contains(node)
        }
        let focus = focused.map(inside) == true ? nil : focusOrder.compactMap { windows[$0]?.window }.first(where: inside)
        return zoomTo(destination.target, displayUUID: uuid, focus: focus) + shown
    }
}

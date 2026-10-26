import PaneModel

/// The keyboard layout commands (TILE-11 to 14, TILE-16). Each user edit is one `World.edit`, dry-run first, so a
/// refusal changes nothing (D-26); a floating window's snap is a frame fact with no undo step (TILE-07).
extension Arranger {
    /// Grow Tile and Shrink Tile move this fraction of the split's length (UI-SPEC Surface 6).
    static let resizeStep = 0.1

    /// Moves a docked window into the tile across `edge`, docking it on that tile's near edge (D-11, TILE-13), or
    /// snaps a floating one to that half of the Desktop tile (TILE-14). No neighbour: beep.
    mutating func moveOrSnap(_ window: WindowRef, toward edge: Edge) throws(LayoutError) -> [ArrangerEffect] {
        guard let key = deskKey(of: window), let desk = world[key], let area = display(for: key)?.visibleFrame else { return [.beep] }
        if desk.desktop.contains(window) { return try snap(window, to: edge.half) }
        let resolution = try Planner.plan(desk: desk, area: area, gap: gap, mins: minimums).resolution
        guard let leaf = desk.tree.leaf(containing: window), let rect = resolution.nodeRects[leaf],
            let neighbour = Neighbours.neighbour(
                of: rect, excluding: leaf, toward: edge, tree: desk.tree, resolution: resolution, gap: gap, recency: recency(on: desk))
        else { return [.beep] }
        // A sibling's near edge is the window's own slot, so docking there changes nothing: it goes past the sibling.
        let side = desk.tree.parent(of: leaf) == desk.tree.parent(of: neighbour) ? edge : edge.opposite
        // The neighbour's NodeID survives the remove: only splits collapse.
        return try commit(key, flashing: window) { desk, ids throws(LayoutError) in
            try desk.tree.remove(window)
            try desk.tree.insert(window, at: side, of: neighbour, ids: &ids)
        }
    }

    /// Snaps a floating window to `target` inside the Desktop tile (TILE-14): a frame fact, no undo step.
    mutating func snap(_ window: WindowRef, to target: SnapTarget) throws(LayoutError) -> [ArrangerEffect] {
        guard let key = deskKey(of: window), let desk = world[key], let frame = desk.desktop.frame(of: window),
            let area = display(for: key)?.visibleFrame,
            let desktop = try Planner.plan(desk: desk, area: area, gap: gap, mins: minimums).desktopRect
        else { return [.beep] }
        try world.recordFloatingFrame(Snap.frame(target, window: frame, desktop: desktop, gap: gap), for: window)
        return replan()
    }

    /// Swaps a docked window with the docked panel focused before it on its desk (TILE-11). None: beep.
    mutating func swapPrevious(_ window: WindowRef) throws(LayoutError) -> [ArrangerEffect] {
        guard let other = previousDocked(before: window), let key = deskKey(of: window) else { return [.beep] }
        return try commit(key, flashing: window) { desk, _ throws(LayoutError) in try desk.tree.swap(window, other) }
    }

    /// Grows (positive) or shrinks the window's tile by `delta` of its split's length, from or to its siblings
    /// (TILE-13). At a size limit, where no rect would change, it beeps and pushes no undo step.
    mutating func resize(_ window: WindowRef, by delta: Double) throws(LayoutError) -> [ArrangerEffect] {
        guard let (key, split, index) = parentSplit(of: window) else { return [.beep] }
        do {
            return try commit(key, flashing: window, refusingNoChange: true) { desk, _ throws(LayoutError) in
                try desk.tree.resizeChild(in: split, index: index, by: delta)
            }
        } catch {
            if case .atSizeLimit = error { return [.beep] }
            throw error
        }
    }

    /// Balance, rotate or flip with the window's parent split, as one undo step (TILE-12). Rotate turns the whole
    /// layout from the root whichever split it is given (03-02).
    mutating func editSplit(
        of window: WindowRef, _ edit: (inout LayoutTree, NodeID) throws(LayoutError) -> Void
    ) throws(LayoutError) -> [ArrangerEffect] {
        guard let (key, split, _) = parentSplit(of: window) else { return [.beep] }
        return try commit(key, flashing: window) { desk, _ throws(LayoutError) in try edit(&desk.tree, split) }
    }

    /// The docked panel focused most recently before `window` on its desk, when `window` is a present docked panel.
    func previousDocked(before window: WindowRef) -> WindowRef? {
        guard let key = deskKey(of: window), let tree = world[key]?.tree, Self.isPresentPanel(window, in: tree) else { return nil }
        return focusOrder.lazy.filter { $0 != window.identity }
            .compactMap { id in tree.windows.first { $0.identity == id } }
            .first { Self.isPresentPanel($0, in: tree) }
    }

    /// The split holding a present docked window's leaf, and the leaf's index in it.
    func parentSplit(of window: WindowRef) -> (key: DeskKey, split: NodeID, index: Int)? {
        guard let key = deskKey(of: window), let tree = world[key]?.tree, tree.state(of: window) == .present,
            let leaf = tree.leaf(containing: window), let split = tree.parent(of: leaf),
            case .split(_, let children, _)? = tree.node(split), let index = children.firstIndex(of: leaf)
        else { return nil }
        return (key, split, index)
    }

    private static func isPresentPanel(_ window: WindowRef, in tree: LayoutTree) -> Bool {
        guard tree.state(of: window) == .present, let leaf = tree.leaf(containing: window), case .panel? = tree.node(leaf) else { return false }
        return true
    }

    /// Applies `change` to `key`'s desk as one undo step, unless the result leaves a window without room: then it
    /// beeps, announces it and flashes the blocked preview at `window`'s would-be frame, changing nothing (D-26).
    /// With `refusingNoChange`, an edit that leaves every rect where it was only beeps.
    private mutating func commit(
        _ key: DeskKey, flashing window: WindowRef, refusingNoChange: Bool = false,
        _ change: (inout Desk, inout IDSource) throws(LayoutError) -> Void
    ) throws(LayoutError) -> [ArrangerEffect] {
        guard let area = display(for: key)?.visibleFrame, let desk = world[key] else { return [.beep] }
        var candidate = world, candidateHistory = history
        try candidate.edit(key, history: &candidateHistory, change)
        guard let edited = candidate[key] else { return [.beep] }
        let plan = try Planner.plan(desk: edited, area: area, gap: gap, mins: minimums)
        guard plan.unfit.isEmpty else {
            let frame = try Planner.plan(desk: edited, area: area, gap: gap, mins: [:]).frames[window]
            return [.beep, .announce(Self.noRoom)] + (frame.map { [.flashBlocked($0, displayUUID: key.displayUUID)] } ?? [])
        }
        if refusingNoChange, try Planner.plan(desk: desk, area: area, gap: gap, mins: minimums).resolution == plan.resolution {
            return [.beep]
        }
        world = candidate
        history = candidateHistory
        return replan()
    }
}

extension Edge {
    fileprivate var opposite: Edge {
        switch self {
        case .left: .right
        case .right: .left
        case .top: .bottom
        case .bottom: .top
        }
    }

    /// The half of the Desktop tile ⌃⌥⌘⇧ and this arrow snap a floating window to.
    fileprivate var half: SnapTarget {
        switch self {
        case .left: .leftHalf
        case .right: .rightHalf
        case .top: .topHalf
        case .bottom: .bottomHalf
        }
    }
}

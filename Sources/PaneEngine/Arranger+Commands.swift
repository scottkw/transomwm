import PaneModel

/// The keyboard layout commands (TILE-11 to 14, TILE-16). Each user edit is one `World.edit`, dry-run first, so a
/// refusal changes nothing (D-26); a floating window's snap is a frame fact with no undo step (TILE-07).
extension Arranger {
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

    /// Applies `change` to `key`'s desk as one undo step, unless the result leaves a window without room: then it
    /// beeps, announces it and flashes the blocked preview at `window`'s would-be frame, changing nothing (D-26).
    private mutating func commit(
        _ key: DeskKey, flashing window: WindowRef, _ change: (inout Desk, inout IDSource) throws(LayoutError) -> Void
    ) throws(LayoutError) -> [ArrangerEffect] {
        guard let area = display(for: key)?.visibleFrame else { return [.beep] }
        var candidate = world, candidateHistory = history
        try candidate.edit(key, history: &candidateHistory, change)
        guard let edited = candidate[key] else { return [.beep] }
        guard try Planner.plan(desk: edited, area: area, gap: gap, mins: minimums).unfit.isEmpty else {
            let frame = try Planner.plan(desk: edited, area: area, gap: gap, mins: [:]).frames[window]
            return [.beep, .announce(Self.noRoom)] + (frame.map { [.flashBlocked($0, displayUUID: key.displayUUID)] } ?? [])
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

import TransomModel

/// What a window opened while Transom runs does (D-01). Float is TILE-07, the default.
public enum NewWindowsMode: String, CaseIterable, Sendable {
    case float, tile
}

extension Arranger {
    /// Under this on either axis a window is too small to tile (D-04).
    static let autoTileMinimum = Size(width: 200, height: 120)

    /// New Windows: Tile (D-02, D-03): docks a new window beside the focused docked tile, or the largest tile, along that
    /// tile's longer side; on an empty desk the window becomes the first tile and fills the visible frame (8.1.1 D-08). One
    /// undo step (D-06). Anything else returns no effects and leaves the window to `admit`, which
    /// floats it. A window that doesn't fit with zoom off stays silent, because nothing the user did was refused.
    mutating func autoTile(_ info: WindowInfo, now: ContinuousClock.Instant) -> [ArrangerEffect] {
        let window = info.window
        guard newWindows == .tile, !gestureLive, pauseReasons.isEmpty, !sessionPaused, !settling,
            info.openedWhileRunning, info.kind == .dockable, !info.isExcluded, info.state == .present,
            deskKey(of: window) == nil,  // restored, dormant and filled windows already are on a desk (D-05)
            !placeholders.fresh.contains(window.identity),  // a tie may still fill a tile as its title settles
            info.frame.width >= Self.autoTileMinimum.width, info.frame.height >= Self.autoTileMinimum.height,
            !(finderExpectation?.matches(info, now: now) ?? false),  // goes where ⌃⌥⌘N asked, and that needs it floating
            let key = home(of: info), let area = display(for: key)?.visibleFrame
        else { return [] }
        do throws(LayoutError) {
            var candidate = world, candidateHistory = history
            if candidate[key] == nil { try candidate.addDesk(key) }
            guard let desk = candidate[key] else { return [] }
            let resolution = try Planner.plan(desk: desk, area: area, gap: gap, mins: minimums).resolution
            // Its own `.windowFocused` can arrive first: the settle delay holds back `.windowCreated`.
            let focused = focusOrder.first { $0 != window.identity }.flatMap { windows[$0]?.window }
            let tile = focused.flatMap { desk.tree.leaf(containing: $0) }.flatMap { leaf in resolution.nodeRects[leaf].map { (leaf, $0) } }
            let drop: DropTarget
            if let (target, rect) = tile ?? Self.largestTile(resolution, in: desk.tree) {
                drop = .tile(target, .edge(rect.width >= rect.height ? .right : .bottom))
            } else {
                // Nothing placed: no tree, or every docked window minimized, hidden or full screen. Either way it fills the frame.
                drop = .layoutEdge(.right)
            }
            // The undo step's snapshot holds it floating where it opened.
            try candidate.reflow(key) { desk, _ throws(LayoutError) in try desk.desktop.add(window, frame: info.frame) }
            try candidate.edit(key, history: &candidateHistory) { desk, ids throws(LayoutError) in
                if desk.desktop.contains(window) { try desk.desktop.remove(window) }
                try desk.tree.applyDrop(drop, window: window, ids: &ids)
            }
            guard let docked = candidate[key] else { return [] }
            var collapsed: Collapse?
            if try !Planner.plan(desk: docked, area: area, gap: gap, mins: minimums).unfit.isEmpty {
                guard let collapse = try collapse(docked, area: area) else { return [] }
                collapsed = collapse
            }
            world = candidate
            history = candidateHistory
            wantedFrames[window.identity] = info.frame  // Float returns it to where it opened, as `admit` records
            if info.learnedMinimum == nil { awaitingFit.insert(window.identity) }
            return accept(collapsed, moving: window)
        } catch {
            return [.fault("left the new window \(window) floating: \(error)")]
        }
    }

    /// D-06 for a window whose minimum was not known when it docked: macOS has no way to ask, so `autoTile`'s check passed, the
    /// app refused the tile, and the learner says so about a second later. With zoom on it collapses. With zoom off it leaves
    /// the tree, and the `admit` that follows floats it where it opened, with no notice: nothing the user did was refused.
    /// shortcut: it shows in the tile for that second and its undo step stays, undoing nothing visible; curing both needs a probe before docking.
    mutating func settleAutoTile(_ info: WindowInfo) throws(LayoutError) -> [ArrangerEffect] {
        let window = info.window
        guard awaitingFit.contains(window.identity), info.learnedMinimum != nil, let key = deskKey(of: window), let desk = world[key],
            desk.tree.state(of: window) != nil, let area = display(for: key)?.visibleFrame,
            try !Planner.plan(desk: desk, area: area, gap: gap, mins: minimums).unfit.isEmpty
        else { return [] }
        awaitingFit.remove(window.identity)
        if let collapsed = try collapse(desk, area: area) { return accept(collapsed, moving: window) }
        try world.reflow(key) { desk, _ throws(LayoutError) in try desk.tree.remove(window) }
        return []
    }
}

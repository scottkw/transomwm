import TransomModel

/// What a window opened while Transom runs does (D-01). Float is TILE-07, the default.
public enum NewWindowsMode: String, CaseIterable, Sendable {
    case float, tile
}

extension Arranger {
    /// Under this on either axis a window is too small to tile (D-04).
    static let autoTileMinimum = Size(width: 200, height: 120)

    /// New Windows: Tile (D-02, D-03): docks a new window beside the focused docked tile, or the largest tile, along that
    /// tile's longer side, as one undo step (D-06). Anything else returns no effects and leaves the window to `admit`, which
    /// floats it. A window that doesn't fit with zoom off stays silent, because nothing the user did was refused.
    mutating func autoTile(_ info: WindowInfo, now: ContinuousClock.Instant) -> [ArrangerEffect] {
        let window = info.window
        guard newWindows == .tile, pauseReasons.isEmpty, !sessionPaused, !settling,
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
            guard let (target, rect) = tile ?? Self.largestTile(resolution, in: desk.tree) else { return [] }
            // The undo step's snapshot holds it floating where it opened. A hidden Desktop can't float it (D-31), and docking
            // must not show it, so undo re-admits it there instead.
            if desk.tree.isDesktopHidden != true {
                try candidate.reflow(key) { desk, _ throws(LayoutError) in try desk.desktop.add(window, frame: info.frame) }
            }
            let drop = DropTarget.tile(target, .edge(rect.width >= rect.height ? .right : .bottom))
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
            return accept(collapsed, moving: window)
        } catch {
            return [.fault("left the new window \(window) floating: \(error)")]
        }
    }
}

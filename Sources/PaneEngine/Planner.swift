import PaneModel

/// Where every window of one desk should be. `frames` holds docked windows' tile rects and the clamped frames of
/// floating windows that overlap a docked tile; floating windows clear of every tile are left where they are (D-24).
/// While the Desktop tile is hidden, its present floating windows are in `parks` instead, with no frame.
public struct FramePlan: Equatable, Sendable {
    public var frames: [WindowRef: Rect]
    public var parks: [WindowRef]
    public var unfit: Set<WindowRef>
    public var desktopRect: Rect?
    public var resolution: Resolution
}

/// Pure layout of one desk: no state, no AppKit.
public enum Planner {
    /// Lays `desk` out in `area` (the display's visibleFrame). The Desktop tile's minimum is the per-axis maximum
    /// of its present floating windows' minimums, so they keep room to sit in it. Docked windows win over floaters
    /// (G-03-6): if that leaves docked windows unfit that would fit beside a 1x1 Desktop, the floaters with the
    /// largest minimum area are dropped from it one at a time until they do; then each dropped floater that still fits
    /// is added back, last dropped first (WR-02). A dropped floater is only clamped, and may still overlap a tile if
    /// its app refuses to shrink (T-03-58).
    public static func plan(desk: Desk, area: Rect, gap: Double, mins: [WindowRef: Size]) throws(LayoutError) -> FramePlan {
        let floating = desk.desktop.windows.filter { $0.state == .present }
        var sizing = floating.compactMap { window in mins[window.window].map { (window: window.window, min: $0) } }
            .sorted { lhs, rhs in
                let l = lhs.min.width * lhs.min.height, r = rhs.min.width * rhs.min.height
                return l != r ? l > r : lhs.window.identity < rhs.window.identity
            }
        func resolved(_ sizing: [(window: WindowRef, min: Size)]) throws(LayoutError) -> Resolution {
            let desktopMinimum = Size(width: sizing.map(\.min.width).max() ?? 1, height: sizing.map(\.min.height).max() ?? 1)
            return try resolve(desk.tree, in: area, mins: mins, gap: gap, desktopMinimum: desktopMinimum)
        }
        var resolution = try resolved(sizing)
        if !resolution.unfit.isEmpty {
            let baselineUnfit = try resolved([]).unfit
            var dropped: [(window: WindowRef, min: Size)] = []
            // Ends: with no floater left, the resolution is the baseline.
            while !resolution.unfit.isSubset(of: baselineUnfit) {
                dropped.append(sizing.removeFirst())
                resolution = try resolved(sizing)
            }
            // The area order can drop a floater that was never the problem (or before a single-axis hint, area 0).
            for floater in dropped.reversed() {
                let trial = try resolved(sizing + [floater])
                if trial.unfit.isSubset(of: baselineUnfit) {
                    sizing.append(floater)
                    resolution = trial
                }
            }
        }
        var frames = resolution.windowRects
        let parks = desk.tree.isDesktopHidden == true ? floating.map(\.window) : []
        if let desktop = resolution.desktopRect {
            let tiles = Array(resolution.windowRects.values)
            for window in floating where tiles.contains(where: window.frame.overlaps) {
                frames[window.window] = clamp(window.frame, into: desktop)
            }
        }
        return FramePlan(frames: frames, parks: parks, unfit: resolution.unfit, desktopRect: resolution.desktopRect, resolution: resolution)
    }

    /// `frame` moved (and shrunk only if it must be) so it lies inside `desktop`.
    public static func clamp(_ frame: Rect, into desktop: Rect) -> Rect {
        let width = min(frame.width, desktop.width), height = min(frame.height, desktop.height)
        return Rect(
            x: min(max(frame.minX, desktop.minX), desktop.maxX - width),
            y: min(max(frame.minY, desktop.minY), desktop.maxY - height),
            width: width, height: height)
    }

    /// Where Dock puts a window whose centre is at `point`: the drop target there (D-12), except that a tile's centre
    /// zone means the nearest edge band of the same tile, since centre drops make tab groups only from Phase 7.
    public static func dockTarget(at point: Point, desk: Desk, area: Rect, resolution: Resolution) -> DropTarget? {
        let target = DropZones.target(at: point, in: area, tree: desk.tree, resolution: resolution)
        guard case let .tile(id, .center)? = target, let rect = resolution.nodeRects[id] else { return target }
        let fx = (point.x - rect.minX) / rect.width, fy = (point.y - rect.minY) / rect.height
        if min(fx, 1 - fx) <= min(fy, 1 - fy) { return .tile(id, .edge(fx < 0.5 ? .left : .right)) }
        return .tile(id, .edge(fy < 0.5 ? .top : .bottom))
    }
}

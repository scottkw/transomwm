import PaneModel

/// Where every window of one desk should be. `frames` holds docked windows' tile rects and the clamped frames of
/// floating windows that overlap a docked tile; floating windows clear of every tile are left where they are (D-24).
public struct FramePlan: Equatable, Sendable {
    public var frames: [WindowRef: Rect]
    public var unfit: Set<WindowRef>
    public var desktopRect: Rect?
    public var resolution: Resolution
}

/// Pure layout of one desk: no state, no AppKit.
public enum Planner {
    /// Lays `desk` out in `area` (the display's visibleFrame). The Desktop tile's minimum is the per-axis maximum
    /// of its present floating windows' minimums, so they keep room to sit in it.
    public static func plan(desk: Desk, area: Rect, gap: Double, mins: [WindowRef: Size]) throws(LayoutError) -> FramePlan {
        let floating = desk.desktop.windows.filter { $0.state == .present }
        let floatingMins = floating.compactMap { mins[$0.window] }
        let desktopMinimum = Size(
            width: floatingMins.map(\.width).max() ?? 1, height: floatingMins.map(\.height).max() ?? 1)
        let resolution = try resolve(desk.tree, in: area, mins: mins, gap: gap, desktopMinimum: desktopMinimum)
        var frames = resolution.windowRects
        if let desktop = resolution.desktopRect {
            let tiles = Array(resolution.windowRects.values)
            for window in floating where tiles.contains(where: window.frame.overlaps) {
                frames[window.window] = clamp(window.frame, into: desktop)
            }
        }
        return FramePlan(frames: frames, unfit: resolution.unfit, desktopRect: resolution.desktopRect, resolution: resolution)
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

import TransomModel

/// Where every docked window of one desk should be: `frames` holds docked windows' tile rects only. A tab group's hidden
/// members are in `parks`, never in `frames`, with their content size in `parkSizes` (D-07); a floating group's too,
/// once each, while its selected member is present. Floating windows are never planned: they stay where the user or
/// their app put them (D-05).
public struct FramePlan: Equatable, Sendable {
    public var frames: [WindowRef: Rect]
    public var parks: [WindowRef]
    /// The size each park is written at; a park with none keeps the window's own size.
    public var parkSizes: [WindowRef: Size] = [:]
    public var unfit: Set<WindowRef>
    public var resolution: Resolution
}

/// Pure layout of one desk: no state, no AppKit.
public enum Planner {
    /// Lays `desk`'s docked windows out in `area` (the display's visibleFrame). Floating windows take no room and get
    /// no frame (D-05).
    public static func plan(
        desk: Desk, area: Rect, gap: Double, mins: [WindowRef: Size]
    ) throws(LayoutError) -> FramePlan {
        let resolution = try resolve(desk.tree, in: area, mins: mins, gap: gap)
        var parks: [WindowRef] = []
        var parkSizes: [WindowRef: Size] = [:]
        for (window, content) in resolution.hiddenTabs.sorted(by: { $0.key.identity < $1.key.identity }) {
            parks.append(window)
            parkSizes[window] = Size(width: content.width, height: content.height)
        }
        let present = Set(desk.desktop.windows.filter { $0.state == .present }.map(\.window))
        for group in desk.desktop.groups where present.contains(group.members[group.selected]) {  // else no part, as docked
            let selected = group.members[group.selected], content = TabBand.content(of: group.frame)
            for hidden in group.members where hidden != selected && present.contains(hidden) {
                parks.append(hidden)
                parkSizes[hidden] = Size(width: content.width, height: content.height)
            }
        }
        return FramePlan(
            frames: resolution.windowRects, parks: parks, parkSizes: parkSizes, unfit: resolution.unfit, resolution: resolution)
    }

    static func near(_ a: Rect, _ b: Rect, within tolerance: Double) -> Bool {
        abs(a.x - b.x) <= tolerance && abs(a.y - b.y) <= tolerance && abs(a.width - b.width) <= tolerance
            && abs(a.height - b.height) <= tolerance
    }

    /// Where Float puts a window undocked from `tile` (G-03-4): its wanted (pre-dock) frame clamped into `desktop`,
    /// unless there is none or that lands within 2 pt of the tile. Then a frame centred in `desktop`, 90% of the
    /// tile per axis, at least `minimum` and at most the Desktop, so the toggle always moves the window.
    public static func floatFrame(wanted: Rect?, tile: Rect, desktop: Rect, minimum: Size?) -> Rect {
        if let wanted {
            let clamped = clamp(wanted, into: desktop)
            if !near(clamped, tile, within: 2) { return clamped }
        }
        let width = min(desktop.width, max(0.9 * tile.width, minimum?.width ?? 0))
        let height = min(desktop.height, max(0.9 * tile.height, minimum?.height ?? 0))
        return Rect(x: desktop.midX - width / 2, y: desktop.midY - height / 2, width: width, height: height)
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
    /// At the exact centre the tie picks the left edge (user decision 2026-10-27).
    public static func dockTarget(at point: Point, desk: Desk, area: Rect, resolution: Resolution) -> DropTarget? {
        let target = DropZones.target(at: point, in: area, tree: desk.tree, resolution: resolution)
        guard case let .tile(id, .center)? = target, let rect = resolution.nodeRects[id] else { return target }
        let fx = (point.x - rect.minX) / rect.width, fy = (point.y - rect.minY) / rect.height
        if min(fx, 1 - fx) <= min(fy, 1 - fy) { return .tile(id, .edge(fx <= 0.5 ? .left : .right)) }
        return .tile(id, .edge(fy < 0.5 ? .top : .bottom))
    }
}

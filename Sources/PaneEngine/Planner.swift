import PaneModel

public struct FramePlan: Equatable, Sendable {
    public var frames: [WindowRef: Rect]
    public var unfit: Set<WindowRef>
    public var desktopRect: Rect?
    public var resolution: Resolution
}

public enum Planner {
    public static func plan(desk: Desk, area: Rect, gap: Double, mins: [WindowRef: Size]) throws(LayoutError) -> FramePlan {
        FramePlan(frames: [:], unfit: [], desktopRect: nil, resolution: Resolution())
    }

    public static func clamp(_ frame: Rect, into desktop: Rect) -> Rect { frame }

    public static func dockTarget(at point: Point, desk: Desk, area: Rect, resolution: Resolution) -> DropTarget? { nil }
}

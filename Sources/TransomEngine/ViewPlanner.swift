import TransomModel

/// What the camera shows on one display (D-A). Home is a case, not a NodeID: the root's ID changes on every split
/// (RESEARCH Pattern 2). `.node(.desktop)` is the Desktop view.
public enum ViewTarget: Hashable, Sendable {
    case home
    case node(NodeID)
}

extension LayoutTree {
    /// The subtree rooted at `id`, with the states of its windows, built through the validating init.
    public func subtree(at id: NodeID) throws(LayoutError) -> LayoutTree {
        guard nodes[id] != nil else { throw .nodeNotFound(id) }
        var kept: [NodeID: Node] = [:], keptStates: [WindowIdentity: WindowState] = [:]
        var stack = [id]
        while let next = stack.popLast(), let node = nodes[next] {
            kept[next] = node
            switch node {
            case let .split(_, children, _): stack.append(contentsOf: children)
            case let .panel(window): keptStates[window.identity] = states[window.identity]
            case let .tabs(windows, _): for window in windows { keptStates[window.identity] = states[window.identity] }
            case .desktop: break
            }
        }
        return try LayoutTree(root: id, nodes: kept, states: keptStates)
    }
}

/// One desk planned at one view. `frames` and `parks` mean what they mean in `FramePlan`; `collapsed` holds the block
/// rect of each collapsed window (also in `parks`, never in `frames`). `homeResolution` is the home view's, which the
/// camera map reads.
public struct ViewPlan: Equatable, Sendable {
    public var frames: [WindowRef: Rect]
    public var parks: [WindowRef]
    public var unfit: Set<WindowRef>
    public var collapsed: [WindowRef: Rect]
    public var desktopRect: Rect?
    public var resolution: Resolution
    public var homeResolution: Resolution
}

/// Pure camera layout (RESEARCH Pattern 1): `.home` is exactly `Planner.plan`; `.node(X)` resolves X's subtree in the
/// whole `area` and parks every present window outside it at its own size.
public enum ViewPlanner {
    public static func plan(
        desk: Desk, view: ViewTarget, area: Rect, gap: Double, mins: [WindowRef: Size], wanted: [WindowIdentity: Rect] = [:],
        collapsible: Set<WindowIdentity> = []
    ) throws(LayoutError) -> ViewPlan {
        guard case .node(let id) = view else {
            var plan = try collapsing(desk: desk, area: area, gap: gap, mins: mins, wanted: wanted, collapsible: collapsible)
            plan.homeResolution = plan.resolution
            return plan
        }
        let home = try self.plan(desk: desk, view: .home, area: area, gap: gap, mins: mins, wanted: wanted, collapsible: collapsible)
        let tree = try desk.tree.subtree(at: id)
        let showsDesktop = tree.nodes[.desktop] != nil
        let viewDesk = Desk(tree: tree, desktop: showsDesktop ? desk.desktop : DesktopLayer())
        var plan = try collapsing(desk: viewDesk, area: area, gap: gap, mins: mins, wanted: wanted, collapsible: collapsible)
        let outside = desk.tree.windows.filter { tree.states[$0.identity] == nil && desk.tree.state(of: $0) == .present }
            + (showsDesktop ? [] : desk.desktop.windows.filter { $0.state == .present }.map(\.window))
        plan.parks = (plan.parks + outside).sorted { $0.identity < $1.identity }
        plan.homeResolution = home.resolution
        return plan
    }

    /// `Planner.plan`, then the zoom-on collapse pass for `collapsible` windows (Task 2).
    private static func collapsing(
        desk: Desk, area: Rect, gap: Double, mins: [WindowRef: Size], wanted: [WindowIdentity: Rect], collapsible: Set<WindowIdentity>
    ) throws(LayoutError) -> ViewPlan {
        let plan = try Planner.plan(desk: desk, area: area, gap: gap, mins: mins, wanted: wanted)
        return ViewPlan(
            frames: plan.frames, parks: plan.parks, unfit: plan.unfit, collapsed: [:], desktopRect: plan.desktopRect,
            resolution: plan.resolution, homeResolution: plan.resolution)
    }
}

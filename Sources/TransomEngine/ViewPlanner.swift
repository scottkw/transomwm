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
    public var parkSizes: [WindowRef: Size] = [:]
    public var unfit: Set<WindowRef>
    public var collapsed: [WindowRef: Rect]
    public var desktopRect: Rect?
    public var resolution: Resolution
    public var homeResolution: Resolution
}

/// Pure camera layout (RESEARCH Pattern 1): `.home` is exactly `Planner.plan`; `.node(X)` resolves X's subtree in the
/// whole `area` and parks every present window outside it at its own size (a hidden tab at its home content size).
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
        // A hidden tab outside the view keeps its home content size, so it is never parked twice (Pitfall 12).
        plan.parkSizes.merge(home.parkSizes.filter { outside.contains($0.key) }) { view, _ in view }
        plan.homeResolution = home.resolution
        return plan
    }

    /// `Planner.plan`, then the zoom-on collapse pass (RESEARCH Pattern 3): unfit `collapsible` windows are planned again
    /// at a 1x1 minimum, so each takes its weighted share while the others keep their real minimums. One whose share is
    /// below its minimum on an axis is collapsed (parked, its share the block rect); one still unfit at 1x1 is parked
    /// with no block. Unfit windows outside `collapsible` stay unfit (OS-caused lost room floats, CONTEXT E).
    private static func collapsing(
        desk: Desk, area: Rect, gap: Double, mins: [WindowRef: Size], wanted: [WindowIdentity: Rect], collapsible: Set<WindowIdentity>
    ) throws(LayoutError) -> ViewPlan {
        var plan = try Planner.plan(desk: desk, area: area, gap: gap, mins: mins, wanted: wanted)
        var shrunk: Set<WindowRef> = []
        var tiny = mins
        // Each pass grows `shrunk`, which the window count bounds, so this ends.
        while case let more = plan.unfit.filter({ collapsible.contains($0.identity) && !shrunk.contains($0) }), !more.isEmpty {
            shrunk.formUnion(more)
            for window in more { tiny[window] = Size(width: 1, height: 1) }
            plan = try Planner.plan(desk: desk, area: area, gap: gap, mins: tiny, wanted: wanted)
        }
        var result = ViewPlan(
            frames: plan.frames, parks: plan.parks, parkSizes: plan.parkSizes, unfit: plan.unfit, collapsed: [:], desktopRect: plan.desktopRect,
            resolution: plan.resolution, homeResolution: plan.resolution)
        guard !shrunk.isEmpty else { return result }
        for window in shrunk {
            let min = mins[window] ?? Size(width: 1, height: 1)
            // Its share is enough after all: it keeps its frame. Plain comparisons on resolve's own numbers, no epsilon.
            if let rect = plan.resolution.windowRects[window], !(rect.width < min.width || rect.height < min.height) { continue }
            result.collapsed[window] = plan.resolution.windowRects[window]
            result.frames[window] = nil
            result.parks.append(window)
        }
        result.parks.sort { $0.identity < $1.identity }
        result.unfit = plan.unfit.filter { !collapsible.contains($0.identity) }
        return result
    }
}

import TransomModel

/// Pure camera navigation over a desk's layout tree (RESEARCH Pattern 2): every command resolves a `ViewTarget` here,
/// and the Arranger extension below turns it into one `zoomTo` or a refusal.
public enum Navigator {
    /// Why a camera command can't act, with its UI-SPEC Surface 1 announcement.
    public enum Refusal: Error, Equatable, Sendable {
        case alreadyHome, nothingToZoomIn, noEarlierView, noLaterView, noArea(Edge), noDockedWindow, desktopHidden, paused, notReady
        case fullScreen

        public var announcement: String {
            switch self {
            case .alreadyHome: "Already showing all windows"
            case .nothingToZoomIn: "Nothing to zoom in to"
            case .noEarlierView: "No earlier view"
            case .noLaterView: "No later view"
            case .noArea(.left): "No area to the left"
            case .noArea(.right): "No area to the right"
            case .noArea(.top): "No area above"
            case .noArea(.bottom): "No area below"
            case .noDockedWindow: "No docked window to frame"
            case .desktopHidden: "The Desktop tile is hidden"
            case .paused: "Arranging is paused"
            case .notReady: "Transom needs Accessibility access"
            case .fullScreen: "Zoom isn't available in full screen"
            }
        }
    }

    /// The path from the root to `id`, ending with `id` itself; empty when `id` is not in `tree`.
    public static func ancestors(of id: NodeID, in tree: LayoutTree) -> [NodeID] {
        guard tree.node(id) != nil else { return [] }
        var path = [id]
        // A valid tree is at most maxDepth deep, so this walks at most that many parents.
        while let parent = tree.parent(of: path[0]) { path.insert(parent, at: 0) }
        return path
    }

    /// Home is a case, not a NodeID (the root's ID changes on every split), so the root is `.home`.
    public static func target(_ id: NodeID, in tree: LayoutTree) -> ViewTarget {
        id == tree.root ? .home : .node(id)
    }

    /// The node a view shows: the root at home.
    static func node(of view: ViewTarget, in tree: LayoutTree) -> NodeID? {
        if case .node(let id) = view { return id }
        return tree.root
    }

    /// The deepest node every one of `ids` descends from (or is); nil when `ids` is empty or one is not in `tree`.
    public static func lowestCommonAncestor(_ ids: [NodeID], in tree: LayoutTree) -> NodeID? {
        let paths = ids.map { ancestors(of: $0, in: tree) }
        guard var common = paths.first else { return nil }
        for path in paths.dropFirst() { common = zip(common, path).prefix { $0 == $1 }.map(\.0) }
        return common.last
    }

    /// The rubber band's target (UI-SPEC Surface 4): the lowest common ancestor of every tile in `tiles` (on-screen leaf
    /// rects) whose centre lies in `band`, edges included. Nil when no centre is inside.
    public static func rectTarget(band: Rect, tiles: [NodeID: Rect], tree: LayoutTree) -> NodeID? {
        let inside = tiles.filter { _, tile in
            band.minX <= tile.midX && tile.midX <= band.maxX && band.minY <= tile.midY && tile.midY <= band.maxY
        }
        return inside.isEmpty ? nil : lowestCommonAncestor(inside.keys.sorted(), in: tree)
    }

    /// The smallest view holding both the view and `leaf` (CONTEXT E); `.home` when that is the root.
    public static func widenTarget(view: ViewTarget, leaf: NodeID, tree: LayoutTree) -> ViewTarget {
        guard let node = node(of: view, in: tree), let common = lowestCommonAncestor([node, leaf], in: tree) else { return .home }
        return target(common, in: tree)
    }

    /// The parent of the view's node (`.home` when that is the root); nil at home.
    public static func stepOut(view: ViewTarget, tree: LayoutTree) -> ViewTarget? {
        guard case .node(let id) = view else { return nil }
        return tree.parent(of: id).map { target($0, in: tree) } ?? .home
    }

    /// One level down from the view's node: the child toward `focusedLeaf` when it is in view, else the child under
    /// `pointer` in `resolution` (the view's on-screen one), else the largest child by area, ties to the lower NodeID.
    /// Nil on a leaf (a tab group is a leaf).
    public static func stepIn(view: ViewTarget, tree: LayoutTree, resolution: Resolution, focusedLeaf: NodeID?, pointer: Point?) -> NodeID? {
        guard let node = node(of: view, in: tree), case .split(_, let children, _)? = tree.node(node) else { return nil }
        if let focusedLeaf {
            let path = ancestors(of: focusedLeaf, in: tree)
            if let i = path.firstIndex(of: node), i + 1 < path.count { return path[i + 1] }
        }
        if let pointer, let hit = children.first(where: { resolution.nodeRects[$0]?.contains(pointer) == true }) { return hit }
        return children.compactMap { id in resolution.nodeRects[id].map { (area: $0.width * $0.height, id: id) } }
            .max { ($0.area, $1.id) < ($1.area, $0.id) }?.id
    }

    /// The node across `edge` of the view's node in the home resolution, at the same depth (edges from the root): its
    /// near side within `gap + 1` pt of the view's far side and overlapping it on the other axis. The longest overlap
    /// wins, ties to the earliest in `recency` (the most recently viewed), then the lower NodeID. Nil at home.
    /// `Neighbours.neighbour` skips splits, hence this variant.
    public static func pan(view: ViewTarget, edge: Edge, tree: LayoutTree, homeResolution: Resolution, gap: Double, recency: [NodeID]) -> NodeID? {
        guard case .node(let id) = view, let rect = homeResolution.nodeRects[id] else { return nil }
        let depth = ancestors(of: id, in: tree).count
        var best: (overlap: Double, rank: Int, id: NodeID)?
        for (other, candidate) in homeResolution.nodeRects where other != id && ancestors(of: other, in: tree).count == depth {
            let distance: Double, overlap: Double
            switch edge {
            case .right: distance = candidate.minX - rect.maxX
            case .left: distance = rect.minX - candidate.maxX
            case .bottom: distance = candidate.minY - rect.maxY
            case .top: distance = rect.minY - candidate.maxY
            }
            switch edge.axis {
            case .horizontal: overlap = min(rect.maxY, candidate.maxY) - max(rect.minY, candidate.minY)
            case .vertical: overlap = min(rect.maxX, candidate.maxX) - max(rect.minX, candidate.minX)
            }
            guard abs(distance) <= gap + 1, overlap > 0 else { continue }
            let next = (overlap: -overlap, rank: recency.firstIndex(of: other) ?? .max, id: other)  // negated: the longest sorts first
            if best.map({ next < $0 }) ?? true { best = next }
        }
        return best?.id
    }
}

/// A view the camera showed: its desk, its target and the target's `Navigator.ancestors` when it was shown.
public struct ViewEntry: Hashable, Sendable {
    public var desk: DeskKey
    public var target: ViewTarget
    public var path: [NodeID]

    public init(desk: DeskKey, target: ViewTarget, path: [NodeID]) {
        self.desk = desk
        self.target = target
        self.path = path
    }
}

/// One display's Back and Forward stacks (D-D), the nearest entry last; each holds at most `limit`, dropping the oldest.
public struct CameraHistory: Equatable, Sendable {
    public static let limit = 50
    public var back: [ViewEntry] = []
    public var forward: [ViewEntry] = []

    public init() {}

    /// A new view: the one left goes on Back and Forward empties.
    public mutating func push(_ entry: ViewEntry) {
        forward = []
        Self.append([entry], to: &back)
    }

    /// The camera went `count` entries back: the deepest of them is where it is now. The view left, then the live
    /// entries passed over, go on Forward, so Forward retraces them.
    mutating func travelBack(_ count: Int, leaving left: ViewEntry?, live: (ViewEntry) -> Bool) {
        Self.travel(count, from: &back, to: &forward, leaving: left, live: live)
    }

    mutating func travelForward(_ count: Int, leaving left: ViewEntry?, live: (ViewEntry) -> Bool) {
        Self.travel(count, from: &forward, to: &back, leaving: left, live: live)
    }

    /// The nearest entry of `stack` past the `skip` nearest that `live` accepts, and how many entries reaching it drops.
    static func nearest(in stack: [ViewEntry], skipping skip: Int, where live: (ViewEntry) -> Bool) -> (entry: ViewEntry, count: Int)? {
        var count = skip
        for entry in stack.dropLast(skip).reversed() {
            count += 1
            if live(entry) { return (entry, count) }
        }
        return nil
    }

    private static func travel(_ count: Int, from: inout [ViewEntry], to: inout [ViewEntry], leaving left: ViewEntry?, live: (ViewEntry) -> Bool) {
        let passed = from.suffix(count).dropFirst().filter(live)
        from.removeLast(min(count, from.count))
        append((left.map { [$0] } ?? []) + passed.reversed(), to: &to)
    }

    private static func append(_ entries: [ViewEntry], to stack: inout [ViewEntry]) {
        stack += entries
        if stack.count > limit { stack.removeFirst(stack.count - limit) }
    }
}

/// The camera commands (UI-SPEC Surface 1): one path for hotkeys, menu items and URLs, so refusals behave the same.
extension Arranger {
    /// Moves `displayUUID`'s camera as `command` asks, or refuses with a beep, the announcement and a log line.
    mutating func camera(_ command: CameraCommand, displayUUID uuid: String, focused: WindowRef?, pointer: Point?) -> [ArrangerEffect] {
        guard camera.enabled else { return [.info("zoom off: \(command) ignored")] }
        guard command != .overview else { return [.fault("overview reached the Arranger; the shell handles it")] }
        do throws(LayoutError) {
            switch try cameraStep(command, displayUUID: uuid, focused: focused, pointer: pointer) {
            case .success(let step):
                switch command {
                case .view(let slot): return goView(slot, displayUUID: uuid, focused: focused)
                case .saveView(let slot): return try saveView(slot, displayUUID: uuid)
                default: return zoomTo(step.target, displayUUID: uuid, kind: step.kind)
                }
            case .failure(let refusal): return [.beep, .announce(refusal.announcement), .info("refused \(command): \(refusal)")]
            }
        } catch {
            return [.fault("could not plan \(command) on \(uuid): \(error)")]
        }
    }

    /// Whether `command` can act on `context.displayUUID` now: zoom on, ready, not paused, a desk on that display, and a
    /// target to move to. The menu greys an item on false.
    public func cameraAvailable(_ command: CameraCommand, context: CommandContext) -> Bool {
        guard camera.enabled, context.ready, let uuid = context.displayUUID,
            case .success? = try? cameraStep(command, displayUUID: uuid, focused: context.focused, pointer: nil)
        else { return false }
        return true
    }

    /// Every leaf of that display's committed view with its on-screen rect: collapsed tiles and the Desktop tile included,
    /// splits never. The band preview's `tiles` (04-06); empty for a display with no desk.
    public func shownLeafRects(displayUUID uuid: String) throws(LayoutError) -> [NodeID: Rect] {
        guard let display = displays.first(where: { $0.uuid == uuid }), let desk = world[Self.key(display)] else { return [:] }
        let plan = try ViewPlanner.plan(
            desk: desk, view: resolvedView(for: Self.key(display)), area: display.visibleFrame, gap: gap, mins: minimums, wanted: wantedFrames,
            collapsible: camera.collapsible)
        return plan.resolution.nodeRects.filter { if case .split? = desk.tree.node($0.key) { false } else { true } }
    }

    /// The docked window's leaf, or the Desktop tile for a present floater on a shown Desktop.
    public func leafNode(of window: WindowRef) -> NodeID? {
        guard let desk = deskKey(of: window).flatMap({ world[$0] }) else { return nil }
        if let leaf = desk.tree.leaf(containing: window) { return leaf }
        return desk.tree.isDesktopHidden == false && desk.desktop.windows.contains { $0.window == window && $0.state == .present } ? .desktop : nil
    }

    /// Whether that display's committed view frames the focused docked window (Frame Focused Window's checkmark).
    public func isFramingFocused(displayUUID uuid: String, focused: WindowRef?) -> Bool {
        guard let display = displays.first(where: { $0.uuid == uuid }), let focused,
            let leaf = world[Self.key(display)]?.tree.leaf(containing: focused)
        else { return false }
        return resolvedView(for: Self.key(display)) == .node(leaf)
    }

    /// Whether that display's committed view frames the Desktop tile (Frame Desktop's checkmark).
    public func isFramingDesktop(displayUUID uuid: String) -> Bool {
        displays.first { $0.uuid == uuid }.map { resolvedView(for: Self.key($0)) == .node(.desktop) } ?? false
    }

    typealias CameraStep = (target: ViewTarget, kind: PendingMove.Kind)

    /// Where `command` takes the camera from the current view (the pending target while a move is pending).
    func cameraStep(
        _ command: CameraCommand, displayUUID uuid: String, focused: WindowRef?, pointer: Point?
    ) throws(LayoutError) -> Result<CameraStep, Navigator.Refusal> {
        guard let display = displays.first(where: { $0.uuid == uuid }), let desk = world[Self.key(display)] else { return .failure(.fullScreen) }
        guard pauseReasons.isEmpty, !sessionPaused else { return .failure(.paused) }
        let key = Self.key(display)
        let view = currentView(uuid, key)
        let history = camera.histories[uuid] ?? CameraHistory()
        let pending = camera.pending[uuid].flatMap { $0.key == key ? $0.kind : nil }
        // An entry Back or Forward can go to: shown now, its node still there, and not the view itself.
        let live = { (entry: ViewEntry) in entry.desk == key && entry.target != view && Self.exists(entry.target, in: desk.tree) }
        func back() -> CameraStep? {
            let skip = if case .back(let count)? = pending { count } else { 0 }  // a second press goes on from the pending one
            return CameraHistory.nearest(in: history.back, skipping: skip, where: live).map { ($0.entry.target, .back($0.count)) }
        }
        func forward() -> CameraStep? {
            let skip = if case .forward(let count)? = pending { count } else { 0 }
            return CameraHistory.nearest(in: history.forward, skipping: skip, where: live).map { ($0.entry.target, .forward($0.count)) }
        }
        func navigate(_ target: ViewTarget?, else refusal: Navigator.Refusal) -> Result<CameraStep, Navigator.Refusal> {
            target.map { .success(($0, .navigate)) } ?? .failure(refusal)
        }
        // Frame toggles: framed already (the pending target counts), it goes Back, or home with no earlier view.
        func toggle(_ target: ViewTarget) -> Result<CameraStep, Navigator.Refusal> {
            .success(view == target ? back() ?? (.home, .navigate) : (target, .navigate))
        }
        switch command {
        case .zoomOutAll:
            return navigate(view == .home ? nil : .home, else: .alreadyHome)
        case .stepOut:
            return navigate(Navigator.stepOut(view: view, tree: desk.tree), else: .alreadyHome)
        case .stepIn:
            let resolution = withoutWaiting(
                try ViewPlanner.plan(
                    desk: desk, view: view, area: display.visibleFrame, gap: gap, mins: minimums, wanted: wantedFrames, collapsible: camera.collapsible
                ).resolution, tree: desk.tree)
            let focusedLeaf = focused.flatMap { deskKey(of: $0) == key ? leafNode(of: $0) : nil }
            let child = Navigator.stepIn(view: view, tree: desk.tree, resolution: resolution, focusedLeaf: focusedLeaf, pointer: pointer)
            return navigate(child.map { .node($0) }, else: .nothingToZoomIn)
        case .back:
            return back().map { .success($0) } ?? .failure(.noEarlierView)
        case .forward:
            return forward().map { .success($0) } ?? .failure(.noLaterView)
        case .pan(let edge):
            guard case .node(let viewed) = view else { return .failure(.noArea(edge)) }
            let home = withoutWaiting(
                try Planner.plan(desk: desk, area: display.visibleFrame, gap: gap, mins: minimums, wanted: wantedFrames).resolution, tree: desk.tree, keeping: viewed)
            let recency = history.back.reversed().compactMap { entry -> NodeID? in
                if entry.desk == key, case .node(let id) = entry.target { id } else { nil }
            }
            let across = Navigator.pan(view: view, edge: edge, tree: desk.tree, homeResolution: home, gap: gap, recency: recency)
            return navigate(across.map { .node($0) }, else: .noArea(edge))
        case .frameWindow:
            guard let focused, let info = windows[focused.identity], info.kind == .dockable, !info.isExcluded, deskKey(of: focused) == key,
                desk.tree.state(of: focused) == .present, let leaf = desk.tree.leaf(containing: focused)
            else { return .failure(.noDockedWindow) }
            return toggle(Navigator.target(leaf, in: desk.tree))
        case .frameDesktop:
            guard desk.tree.isDesktopHidden == false else { return .failure(.desktopHidden) }
            return toggle(Navigator.target(.desktop, in: desk.tree))
        case .overview:
            return .failure(.notReady)  // never a camera step: `camera` faults first and the shell decides availability
        case .view, .saveView:
            return .success((view, .navigate))  // past the shared refusals; `camera` hands these to goView and saveView
        }
    }
}

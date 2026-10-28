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
}

/// The camera commands (UI-SPEC Surface 1): one path for hotkeys, menu items and URLs, so refusals behave the same.
extension Arranger {
    /// Moves `displayUUID`'s camera as `command` asks, or refuses with a beep, the announcement and a log line.
    mutating func camera(_ command: CameraCommand, displayUUID uuid: String, focused: WindowRef?, pointer: Point?) -> [ArrangerEffect] {
        guard camera.enabled else { return [.info("zoom off: \(command) ignored")] }
        do throws(LayoutError) {
            switch try cameraStep(command, displayUUID: uuid, focused: focused, pointer: pointer) {
            case .success(let target): return zoomTo(target, displayUUID: uuid)
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

    /// The docked window's leaf, or the Desktop tile for a present floater on a shown Desktop.
    public func leafNode(of window: WindowRef) -> NodeID? {
        guard let desk = deskKey(of: window).flatMap({ world[$0] }) else { return nil }
        if let leaf = desk.tree.leaf(containing: window) { return leaf }
        return desk.tree.isDesktopHidden == false && desk.desktop.windows.contains { $0.window == window && $0.state == .present } ? .desktop : nil
    }

    /// Where `command` takes the camera from the current view (the pending target while a move is pending).
    func cameraStep(
        _ command: CameraCommand, displayUUID uuid: String, focused: WindowRef?, pointer: Point?
    ) throws(LayoutError) -> Result<ViewTarget, Navigator.Refusal> {
        guard let display = displays.first(where: { $0.uuid == uuid }), let desk = world[Self.key(display)] else { return .failure(.fullScreen) }
        guard pauseReasons.isEmpty, !sessionPaused else { return .failure(.paused) }
        let key = Self.key(display)
        let view = currentView(uuid, key)
        switch command {
        case .zoomOutAll:
            return view == .home ? .failure(.alreadyHome) : .success(.home)
        case .stepOut:
            return Navigator.stepOut(view: view, tree: desk.tree).map { .success($0) } ?? .failure(.alreadyHome)
        case .stepIn:
            let resolution = try ViewPlanner.plan(
                desk: desk, view: view, area: display.visibleFrame, gap: gap, mins: minimums, wanted: wantedFrames, collapsible: camera.collapsible
            ).resolution
            let focusedLeaf = focused.flatMap { deskKey(of: $0) == key ? leafNode(of: $0) : nil }
            let child = Navigator.stepIn(view: view, tree: desk.tree, resolution: resolution, focusedLeaf: focusedLeaf, pointer: pointer)
            return child.map { .success(.node($0)) } ?? .failure(.nothingToZoomIn)
        }
    }
}

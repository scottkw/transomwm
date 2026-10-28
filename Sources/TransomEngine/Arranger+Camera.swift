import TransomModel

/// All camera state, session-only (never saved, so layout.json stays schema 1). The committed view per desk; a move
/// waiting for its `.cameraSettle` per display.
public struct CameraState: Sendable {
    public var enabled = false
    public var views: [DeskKey: ViewTarget] = [:]
    public var pending: [String: PendingMove] = [:]
    public var nextMoveID: UInt64 = 0
    /// Windows the user accepted as collapsed by a drop or keyboard Dock/Move (ZOOM-13, fed from 04-07).
    public var collapsible: Set<WindowIdentity> = []
    /// Back/Forward per display (D-D); changed only at settle.
    public var histories: [String: CameraHistory] = [:]
    /// Each committed node view's `Navigator.ancestors`, so a vanished node falls back to its deepest surviving one.
    public var paths: [DeskKey: [NodeID]] = [:]
    /// New windows outside the view, kept unparked until the move that shows them settles (RESEARCH Pitfall 3).
    public var unparkedNew: Set<WindowIdentity> = []
    /// The collapsed blocks last sent per display, so only a change is sent again.
    public var shownBlocks: [String: [CollapsedBlock]] = [:]

    public init() {}
}

public struct PendingMove: Equatable, Sendable {
    /// What the settle does to the history: push the view left, or travel that many entries back or forward.
    public enum Kind: Equatable, Sendable { case navigate, back(Int), forward(Int) }
    public var id: UInt64
    public var key: DeskKey
    public var target: ViewTarget
    public var kind: Kind = .navigate
    /// Focused right after the settle's writes.
    public var focus: WindowRef?
}

/// One camera move for the stage: a start and end rect per window, no writes (RESEARCH Pattern 4).
public struct CameraMove: Equatable, Sendable {
    public var id: UInt64
    public var displayUUID: String
    public var from: ViewTarget
    public var to: ViewTarget
    /// Sorted by window identity.
    public var tiles: [TileMove]
}

public struct TileMove: Equatable, Sendable {
    /// `collapsed`: a collapsed block in the end view (drawn as a block, never a snapshot); it may enter or stay.
    public enum Kind: Equatable, Sendable { case stay, entering, leaving, collapsed }
    public var window: WindowRef
    public var start: Rect
    public var end: Rect
    public var kind: Kind
}

/// A collapsed window's block (ZOOM-13): the tile it would have, in global top-left points; the window itself is parked.
public struct CollapsedBlock: Equatable, Sendable {
    public var window: WindowRef
    public var rect: Rect

    public init(window: WindowRef, rect: Rect) {
        self.window = window
        self.rect = rect
    }
}

/// The camera (D-A): a zoom command emits one `.cameraMove` and changes nothing; the matching `.cameraSettle` commits the
/// view and returns `planShown()`, so every camera write is saved before parking, parked once and written only on change.
extension Arranger {
    public var zoomEnabled: Bool { camera.enabled }

    /// The committed view on that display's shown desk.
    public func view(on displayUUID: String) -> ViewTarget {
        guard let display = displays.first(where: { $0.uuid == displayUUID }) else { return .home }
        return camera.views[Self.key(display)] ?? .home
    }

    /// The committed view of `key`. When its node is gone: the deepest node of its stored path still in the tree, else home.
    func resolvedView(for key: DeskKey) -> ViewTarget {
        guard camera.enabled, case .node(let id)? = camera.views[key], let tree = world[key]?.tree else { return .home }
        if tree.node(id) != nil { return .node(id) }
        return camera.paths[key]?.last { tree.node($0) != nil }.map { Navigator.target($0, in: tree) } ?? .home
    }

    /// The view a camera command starts from: the pending target, else the committed view. A move pending on a desk no
    /// longer shown (a Space switch) is stale.
    func currentView(_ uuid: String, _ key: DeskKey) -> ViewTarget {
        camera.pending[uuid].flatMap { $0.key == key ? $0.target : nil } ?? resolvedView(for: key)
    }

    /// The view `planShown` plans for `key` (`resolvedView`), committing the fallback when the node is gone.
    mutating func effectiveView(for key: DeskKey, notes: inout [ArrangerEffect]) -> ViewTarget {
        let view = resolvedView(for: key)
        guard view != camera.views[key] ?? .home else { return view }
        commit(view, on: key)
        notes.append(.info("view node gone; showing \(view)"))
        return view
    }

    private mutating func commit(_ view: ViewTarget, on key: DeskKey) {
        camera.views[key] = view == .home ? nil : view
        camera.paths[key] = if case .node(let id) = view, let tree = world[key]?.tree { Navigator.ancestors(of: id, in: tree) } else { nil }
    }

    /// CONTEXT E: a window outside its display's view (the pending target while a move is pending) moves the camera to the
    /// smallest view holding both. A `new` one stays unparked until a move settles on its desk (Pitfall 3).
    mutating func widen(toShow window: WindowRef, new: Bool) -> [ArrangerEffect] {
        guard camera.enabled, pauseReasons.isEmpty, !sessionPaused, windows[window.identity]?.isExcluded == false,
            let key = deskKey(of: window), let display = display(for: key), let tree = world[key]?.tree, let leaf = leafNode(of: window)
        else { return [] }
        let view = currentView(display.uuid, key)
        let target = Navigator.widenTarget(view: view, leaf: leaf, tree: tree)
        guard target != view else { return [] }
        let effects = zoomTo(target, displayUUID: display.uuid)
        if new, effects.contains(where: { if case .cameraMove = $0 { true } else { false } }) { camera.unparkedNew.insert(window.identity) }
        return effects
    }

    mutating func setZoomEnabled(_ on: Bool) -> [ArrangerEffect] {
        camera.enabled = on
        guard !on else { return [] }
        camera.views = [:]
        camera.pending = [:]
        camera.histories = [:]
        camera.paths = [:]
        camera.unparkedNew = []
        camera.collapsible = []  // they float with N1: Phase 3 has no collapsed tiles (Surface 3)
        return replan() + showBlocks([:])  // also when paused, so no block outlives zoom
    }

    /// D-A, ZOOM-13: with zoom on, an edit whose home plan leaves windows without room is accepted by collapsing them.
    /// The collapsible set grown until `desk`'s home plan leaves nothing unfit, and the windows it adds that get no frame
    /// (collapsed, or parked with no block); nil with zoom off.
    func collapse(_ desk: Desk, area: Rect) throws(LayoutError) -> (set: Set<WindowIdentity>, newly: [WindowRef])? {
        guard camera.enabled else { return nil }
        var set = camera.collapsible
        let mins = learnedMinimums
        // ViewPlan.unfit never holds a member of `set`, so each pass adds one; the window count bounds it.
        while true {
            let plan = try ViewPlanner.plan(desk: desk, view: .home, area: area, gap: gap, mins: mins, collapsible: set)
            guard !plan.unfit.isEmpty else {
                let added = desk.tree.windows.filter { set.contains($0.identity) && !camera.collapsible.contains($0.identity) }
                return (set, added.filter { plan.frames[$0] == nil })
            }
            set.formUnion(plan.unfit.map(\.identity))
        }
    }

    mutating func zoomTo(
        _ target: ViewTarget, displayUUID uuid: String, kind: PendingMove.Kind = .navigate, focus: WindowRef? = nil
    ) -> [ArrangerEffect] {
        func refused(_ reason: String) -> [ArrangerEffect] { [.info("refused zoomTo: \(reason)")] }
        guard camera.enabled else { return [.info("zoom off: zoomTo ignored")] }
        guard pauseReasons.isEmpty, !sessionPaused else { return refused("paused") }
        guard let display = displays.first(where: { $0.uuid == uuid }), let desk = world[Self.key(display)] else {
            return refused("no desk on display")
        }
        let key = Self.key(display)
        if case .node(let id) = target, desk.tree.node(id) == nil { return refused("node not found") }
        var notes: [ArrangerEffect] = []
        _ = effectiveView(for: key, notes: &notes)
        let current = currentView(uuid, key)
        guard target != current else { return notes + refused("already showing") }
        let area = display.visibleFrame, mins = learnedMinimums
        let start: ViewPlan, end: ViewPlan
        do throws(LayoutError) {
            start = try ViewPlanner.plan(desk: desk, view: current, area: area, gap: gap, mins: mins, wanted: wantedFrames, collapsible: camera.collapsible)
            end = try ViewPlanner.plan(desk: desk, view: target, area: area, gap: gap, mins: mins, wanted: wantedFrames, collapsible: camera.collapsible)
        } catch {
            return notes + [.fault("could not plan zoomTo \(target) on \(uuid): \(error)")]
        }
        let before = Self.shown(start, desk), after = Self.shown(end, desk)
        let fromMap = Self.cameraMap(viewRect: Self.viewRect(current, start, area), onto: area)
        let toMap = Self.cameraMap(viewRect: Self.viewRect(target, end, area), onto: area)
        func home(_ window: WindowRef, else rect: Rect) -> Rect {
            start.homeResolution.windowRects[window] ?? desk.desktop.frame(of: window) ?? rect
        }
        var tiles: [TileMove] = []
        let all = Set(before.keys).union(after.keys).union(start.collapsed.keys).union(end.collapsed.keys)
        for window in all where windows[window.identity]?.isExcluded == false {
            let tracked = windows[window.identity]?.frame
            // A collapsed window is where its block is, never at its parked frame.
            let from = start.collapsed[window] ?? before[window].map { tracked ?? $0 }
            let to = end.collapsed[window] ?? after[window]
            var tile: TileMove
            switch (from, to) {
            case let (from?, to?): tile = TileMove(window: window, start: from, end: to, kind: .stay)
            case let (from?, nil): tile = TileMove(window: window, start: from, end: toMap(home(window, else: from)), kind: .leaving)
            case let (nil, to?): tile = TileMove(window: window, start: fromMap(home(window, else: to)), end: to, kind: .entering)
            case (nil, nil): continue
            }
            if end.collapsed[window] != nil { tile.kind = .collapsed }
            tiles.append(tile)
        }
        camera.nextMoveID += 1
        camera.pending[uuid] = PendingMove(id: camera.nextMoveID, key: key, target: target, kind: kind, focus: focus)
        let move = CameraMove(
            id: camera.nextMoveID, displayUUID: uuid, from: current, to: target, tiles: tiles.sorted { $0.window.identity < $1.window.identity })
        return notes + [.cameraMove(move)]
    }

    /// Commits the pending move's view and writes it; an older, repeated or unknown move does nothing.
    mutating func cameraSettle(displayUUID uuid: String, moveID: UInt64) -> [ArrangerEffect] {
        guard let move = camera.pending[uuid], move.id == moveID else { return [] }
        camera.pending[uuid] = nil
        let previous = resolvedView(for: move.key)
        commit(move.target, on: move.key)
        recordHistory(move, leaving: previous, on: uuid)
        if let desk = world[move.key] { camera.unparkedNew = camera.unparkedNew.filter { !desk.contains(WindowRef(identity: $0)) } }
        let effects = planShown()
        guard let focus = move.focus, windows[focus.identity] != nil else { return effects }
        return effects + [.perform([.focus(focus)])]
    }

    /// The history changes only here (D-D), so a retarget never pushes twice.
    private mutating func recordHistory(_ move: PendingMove, leaving previous: ViewTarget, on uuid: String) {
        guard let tree = world[move.key]?.tree else { return }
        var path: [NodeID] = []
        if case .node(let id) = previous { path = Navigator.ancestors(of: id, in: tree) }
        let left = previous == move.target ? nil : ViewEntry(desk: move.key, target: previous, path: path)
        let live = { (entry: ViewEntry) in entry.desk == move.key && Self.exists(entry.target, in: tree) }
        switch move.kind {
        case .navigate: if let left { camera.histories[uuid, default: CameraHistory()].push(left) }
        case .back(let count): camera.histories[uuid, default: CameraHistory()].travelBack(count, leaving: left, live: live)
        case .forward(let count): camera.histories[uuid, default: CameraHistory()].travelForward(count, leaving: left, live: live)
        }
    }

    static func exists(_ target: ViewTarget, in tree: LayoutTree) -> Bool {
        guard case .node(let id) = target else { return true }
        return tree.node(id) != nil
    }

    /// The affine map taking `viewRect` (the view's rect in the home resolution) onto `area` (identity for `.home`).
    public static func cameraMap(viewRect: Rect, onto area: Rect) -> (Rect) -> Rect {
        guard viewRect.width > 0, viewRect.height > 0 else { return { $0 } }
        let sx = area.width / viewRect.width, sy = area.height / viewRect.height
        return { r in
            Rect(x: area.minX + (r.minX - viewRect.minX) * sx, y: area.minY + (r.minY - viewRect.minY) * sy, width: r.width * sx, height: r.height * sy)
        }
    }

    /// shortcut: a node with no home rect (all its windows absent) maps as home; refine if such views become reachable.
    private static func viewRect(_ view: ViewTarget, _ plan: ViewPlan, _ area: Rect) -> Rect {
        guard case .node(let id) = view else { return area }
        return plan.homeResolution.nodeRects[id] ?? area
    }

    /// Every window on screen in `plan`: its planned frame, or a floater's own frame when the plan leaves it in place.
    private static func shown(_ plan: ViewPlan, _ desk: Desk) -> [WindowRef: Rect] {
        var rects = plan.frames
        let parked = Set(plan.parks)
        for floating in desk.desktop.windows where floating.state == .present && !parked.contains(floating.window) && rects[floating.window] == nil {
            rects[floating.window] = floating.frame
        }
        return rects
    }
}

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

    public init() {}
}

public struct PendingMove: Equatable, Sendable {
    public var id: UInt64
    public var key: DeskKey
    public var target: ViewTarget
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
    public enum Kind: Equatable, Sendable { case stay, entering, leaving }
    public var window: WindowRef
    public var start: Rect
    public var end: Rect
    public var kind: Kind
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

    /// The view `planShown` plans for `key`: the committed one, or home when its node is gone (04-03 refines this with
    /// ancestor paths).
    mutating func effectiveView(for key: DeskKey, notes: inout [ArrangerEffect]) -> ViewTarget {
        guard camera.enabled, case .node(let id)? = camera.views[key] else { return .home }
        if world[key]?.tree.node(id) != nil { return .node(id) }
        camera.views[key] = nil
        notes.append(.info("view node gone; showing home"))
        return .home
    }

    mutating func setZoomEnabled(_ on: Bool) -> [ArrangerEffect] {
        camera.enabled = on
        guard !on else { return [] }
        camera.views = [:]
        camera.pending = [:]
        return replan()
    }

    mutating func zoomTo(_ target: ViewTarget, displayUUID uuid: String) -> [ArrangerEffect] {
        func refused(_ reason: String) -> [ArrangerEffect] { [.info("refused zoomTo: \(reason)")] }
        guard camera.enabled else { return [.info("zoom off: zoomTo ignored")] }
        guard pauseReasons.isEmpty, !sessionPaused else { return refused("paused") }
        guard let display = displays.first(where: { $0.uuid == uuid }), let desk = world[Self.key(display)] else {
            return refused("no desk on display")
        }
        let key = Self.key(display)
        if case .node(let id) = target, desk.tree.node(id) == nil { return refused("node not found") }
        var notes: [ArrangerEffect] = []
        // A move pending on a desk no longer shown (a Space switch) is stale.
        let current = camera.pending[uuid].flatMap { $0.key == key ? $0.target : nil } ?? effectiveView(for: key, notes: &notes)
        guard target != current else { return notes + refused("already showing") }
        let area = display.visibleFrame, mins = minimums
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
        for window in Set(before.keys).union(after.keys) where windows[window.identity]?.isExcluded == false {
            let tracked = windows[window.identity]?.frame
            switch (before[window], after[window]) {
            case let (from?, to?): tiles.append(TileMove(window: window, start: tracked ?? from, end: to, kind: .stay))
            case let (from?, nil): tiles.append(TileMove(window: window, start: tracked ?? from, end: toMap(home(window, else: from)), kind: .leaving))
            case let (nil, to?): tiles.append(TileMove(window: window, start: fromMap(home(window, else: to)), end: to, kind: .entering))
            case (nil, nil): break
            }
        }
        camera.nextMoveID += 1
        camera.pending[uuid] = PendingMove(id: camera.nextMoveID, key: key, target: target)
        let move = CameraMove(
            id: camera.nextMoveID, displayUUID: uuid, from: current, to: target, tiles: tiles.sorted { $0.window.identity < $1.window.identity })
        return notes + [.cameraMove(move)]
    }

    /// Commits the pending move's view and writes it; an older, repeated or unknown move does nothing.
    mutating func cameraSettle(displayUUID uuid: String, moveID: UInt64) -> [ArrangerEffect] {
        guard let move = camera.pending[uuid], move.id == moveID else { return [] }
        camera.pending[uuid] = nil
        camera.views[move.key] = move.target == .home ? nil : move.target
        return planShown()
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

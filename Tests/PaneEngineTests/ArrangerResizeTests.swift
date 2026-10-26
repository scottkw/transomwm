import PaneEngine
import PaneModel
import Testing

private let pid: Int32 = 900
private let bundleID = "com.example.arranger"
private let visible = Rect(x: 0, y: 25, width: 1440, height: 875)
private let display = DisplayInfo(uuid: "main", frame: Rect(x: 0, y: 0, width: 1440, height: 900), visibleFrame: visible, currentSpaceID: nil)
private let key = DeskKey(displayUUID: "main", spaceID: nil)
private let gap = 8.0

private func ref(_ id: UInt32) -> WindowRef {
    WindowRef(identity: WindowIdentity(windowID: id, pid: pid, bundleID: bundleID))
}

private let a = ref(1), b = ref(2), c = ref(3), f = ref(4)
private let floatingFrame = Rect(x: 1000, y: 400, width: 300, height: 200)

private func leaf(_ desk: Desk, _ window: WindowRef) throws(LayoutError) -> NodeID {
    guard let id = desk.tree.leaf(containing: window) else { throw .windowNotFound(window) }
    return id
}

/// H[a, b, Desktop]
private func row(_ desk: inout Desk, _ ids: inout IDSource) throws(LayoutError) {
    try desk.tree.insert(a, at: .left, of: .desktop, ids: &ids)
    try desk.tree.insert(b, at: .right, of: try leaf(desk, a), ids: &ids)
}

/// V[H[a, b], Desktop]
private func corner(_ desk: inout Desk, _ ids: inout IDSource) throws(LayoutError) {
    try desk.tree.insert(a, at: .top, of: .desktop, ids: &ids)
    try desk.tree.insert(b, at: .right, of: try leaf(desk, a), ids: &ids)
}

private func plan(_ arranger: Arranger, mins: [WindowRef: Size] = [:]) throws -> FramePlan {
    try Planner.plan(desk: try #require(arranger.world[key]), area: visible, gap: gap, mins: mins)
}

/// An Arranger whose main desk holds `build`'s layout, every docked window already at its tile and f floating.
private func arranger(minimums: [WindowRef: Size] = [:], _ build: (inout Desk, inout IDSource) throws(LayoutError) -> Void) throws -> Arranger {
    var world = World()
    var history = UndoHistory()
    try world.addDesk(key)
    try world.edit(key, history: &history, build)
    var arranger = Arranger(gap: gap)
    _ = arranger.handle(.restore(world, homeFrames: [:]), now: .now)
    let somewhere = Rect(x: 200, y: 200, width: 400, height: 300)
    let infos = [a, b, c].filter { world[key]?.tree.state(of: $0) != nil }.map {
        WindowInfo(window: $0, frame: somewhere, state: .present, displayUUID: "main", learnedMinimum: minimums[$0])
    } + [WindowInfo(window: f, frame: floatingFrame, state: .present, displayUUID: "main")]
    _ = arranger.handle(.inventory(WindowInventory(displays: [display], windows: infos, initialRefreshComplete: true)), now: .now)
    // Each docked window's write comes back exactly.
    for (window, tile) in try plan(arranger, mins: minimums).frames {
        _ = arranger.handle(.event(.frameApplied(window, requested: tile, actual: tile)), now: .now)
        _ = arranger.handle(.event(.windowMoved(window, tile)), now: .now)
    }
    return arranger
}

private func pointer(_ kind: PointerEvent.Kind, _ x: Double, _ y: Double, press: WindowRef? = nil) -> ArrangerInput {
    .pointer(PointerEvent(kind: kind, location: Point(x: x, y: y), pressWindow: press))
}

/// Presses `window` at `grab`, moves the pointer by (dx, dy) and reports `frame` from the drag poll.
private func resize(_ arranger: inout Arranger, _ window: WindowRef, grab: Point, by dx: Double, _ dy: Double, to frame: Rect) -> [ArrangerEffect] {
    var effects = arranger.handle(pointer(.down, grab.x, grab.y, press: window), now: .now)
    effects += arranger.handle(pointer(.dragged, grab.x + dx, grab.y + dy), now: .now)
    effects += arranger.handle(.dragFrame(window.identity, frame), now: .now)
    return effects
}

private func near(_ x: Double, _ y: Double) -> Bool { abs(x - y) <= 1 }

/// D-07: dragging a docked window's own edge moves its split boundary; mouse-up commits one undo step.
@Suite struct ArrangerResizeTests {
    @Test func draggingTheInnerRightEdgeMovesTheBoundaryAndCommitsOnce() throws {
        var arranger = try arranger(row)
        let before = try plan(arranger)
        let ta = try #require(before.frames[a]), tb = try #require(before.frames[b])
        let grown = Rect(x: ta.x, y: ta.y, width: ta.width + 100, height: ta.height)
        let during = resize(&arranger, a, grab: Point(x: ta.maxX - 1, y: ta.midY), by: 100, 0, to: grown)
        let live = setFrames(during)
        #expect(live[a] == nil, "the dragged window was written")
        let lb = try #require(live[b], "b did not follow: \(during)")
        #expect(near(lb.minX, tb.minX + 100) && near(lb.maxX, tb.maxX))
        #expect(arranger.history.depth(for: key) == 0, "the drag itself is an undo step")  // a restore starts with no history

        let up = arranger.handle(pointer(.up, ta.maxX + 99, ta.midY), now: .now)
        #expect(arranger.history.depth(for: key) == 1)
        let after = try plan(arranger)
        let na = try #require(after.frames[a]), nb = try #require(after.frames[b])
        #expect(near(na.width, ta.width + 100) && na.minX == ta.minX)
        #expect(near(nb.minX, tb.minX + 100) && nb.maxX == tb.maxX)
        #expect(after.desktopRect == before.desktopRect)
        #expect(setFrames(up)[a].map { near($0.width, na.width) } ?? true, "a was not settled into its tile")
        #expect(arranger.drag == nil)
    }

    @Test func anOuterEdgeSnapsBackWithNoUndoStep() throws {
        var arranger = try arranger(row)
        let ta = try #require(try plan(arranger).frames[a])
        let wider = Rect(x: ta.x - 50, y: ta.y, width: ta.width + 50, height: ta.height)
        let during = resize(&arranger, a, grab: Point(x: ta.minX + 1, y: ta.midY), by: -50, 0, to: wider)
        #expect(setFrames(during).isEmpty, "an outer edge moved something: \(during)")
        let up = arranger.handle(pointer(.up, ta.minX - 49, ta.midY), now: .now)
        #expect(setFrames(up)[a] == ta)
        #expect(arranger.history.depth(for: key) == 0)
    }

    @Test func aCornerDragMovesBothBoundariesInOneEdit() throws {
        var arranger = try arranger(corner)
        let before = try plan(arranger)
        let ta = try #require(before.frames[a])
        let grown = Rect(x: ta.x, y: ta.y, width: ta.width + 100, height: ta.height + 50)
        _ = resize(&arranger, a, grab: Point(x: ta.maxX - 1, y: ta.maxY - 1), by: 100, 50, to: grown)
        _ = arranger.handle(pointer(.up, ta.maxX + 99, ta.maxY + 49), now: .now)
        #expect(arranger.history.depth(for: key) == 1)
        let na = try #require(try plan(arranger).frames[a])
        #expect(near(na.width, ta.width + 100) && near(na.height, ta.height + 50), "\(ta) became \(na)")
    }

    @Test func aResizeStopsAtTheNeighboursMinimum() throws {
        let start = try plan(try arranger(row))
        let tb = try #require(start.frames[b])
        let minimum = Size(width: tb.width - 30, height: 100)
        var arranger = try arranger(minimums: [b: minimum], row)
        let before = try plan(arranger, mins: [b: minimum])
        let ta = try #require(before.frames[a])
        let grown = Rect(x: ta.x, y: ta.y, width: ta.width + 100, height: ta.height)
        let live = setFrames(resize(&arranger, a, grab: Point(x: ta.maxX - 1, y: ta.midY), by: 100, 0, to: grown))
        #expect(live[b].map { near($0.width, minimum.width) } == true, "b went below its minimum: \(live)")
        _ = arranger.handle(pointer(.up, ta.maxX + 99, ta.midY), now: .now)
        let after = try plan(arranger, mins: [b: minimum])
        let na = try #require(after.frames[a]), nb = try #require(after.frames[b])
        #expect(near(nb.width, minimum.width))
        #expect(near(na.width, ta.width + 30))
        #expect(after.desktopRect == before.desktopRect, "the Desktop paid for the resize")
        // The stored weights say what the screen shows: the next drag back moves the boundary at once.
        let back = Rect(x: na.x, y: na.y, width: na.width - 20, height: na.height)
        let again = setFrames(resize(&arranger, a, grab: Point(x: na.maxX - 1, y: na.midY), by: -20, 0, to: back))
        #expect(again[b].map { near($0.width, minimum.width + 20) } == true, "dead zone: \(again)")
    }

    @Test func aFloatingWindowsResizeIsRecordedAsAFact() throws {
        var arranger = try arranger(row)
        let bigger = Rect(x: floatingFrame.x, y: floatingFrame.y, width: floatingFrame.width + 60, height: floatingFrame.height + 40)
        _ = resize(&arranger, f, grab: Point(x: floatingFrame.maxX - 1, y: floatingFrame.maxY - 1), by: 60, 40, to: bigger)
        let up = arranger.handle(pointer(.up, floatingFrame.maxX + 59, floatingFrame.maxY + 39), now: .now)
        #expect(arranger.world[key]?.desktop.frame(of: f) == bigger)
        #expect(setFrames(up)[f] == nil)
        #expect(arranger.history.depth(for: key) == 0)
    }

    @Test func aTitleBarDoubleClickNeverStartsAResize() throws {
        var arranger = try arranger(row)
        let ta = try #require(try plan(arranger).frames[a])
        let title = Point(x: ta.midX, y: ta.minY + 10)
        _ = arranger.handle(pointer(.down, title.x, title.y, press: a), now: .now)
        _ = arranger.handle(pointer(.up, title.x, title.y), now: .now)
        _ = arranger.handle(pointer(.down, title.x, title.y, press: a), now: .now)
        // The zoom lands while the second press is down: no travel, so no session kind.
        _ = arranger.handle(.event(.windowResized(a, visible)), now: .now)
        #expect(arranger.drag?.kind == nil)
        let up = arranger.handle(pointer(.up, title.x, title.y), now: .now)
        #expect(arranger.history.depth(for: key) == 0)
        #expect(setFrames(up)[a] == ta, "not put back after the zoom: \(up)")
    }
}

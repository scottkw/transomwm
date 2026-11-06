import TransomEngine
import TransomModel
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

/// H[a, b, c]: c takes the place the Desktop tile had, so a and b keep a sibling past them (8.1.1 D-01).
private func row(_ desk: inout Desk, _ ids: inout IDSource) throws(LayoutError) {
    try desk.tree.applyDrop(.layoutEdge(.right), window: a, ids: &ids)
    try desk.tree.insert(b, at: .right, of: try leaf(desk, a), ids: &ids)
    try desk.tree.applyDrop(.layoutEdge(.right), window: c, ids: &ids)
}

/// V[H[a, b], c]
private func corner(_ desk: inout Desk, _ ids: inout IDSource) throws(LayoutError) {
    try desk.tree.applyDrop(.layoutEdge(.bottom), window: a, ids: &ids)
    try desk.tree.insert(b, at: .right, of: try leaf(desk, a), ids: &ids)
    try desk.tree.applyDrop(.layoutEdge(.bottom), window: c, ids: &ids)
}

private func plan(_ arranger: Arranger, mins: [WindowRef: Size] = [:]) throws -> FramePlan {
    try Planner.plan(desk: try #require(arranger.world[key]), area: visible, gap: gap, mins: mins)
}

/// An Arranger whose main desk holds `build`'s layout, every docked window already at its tile and f floating.
private func arranger(
    minimums: [WindowRef: Size] = [:], absent: [WindowRef] = [], _ build: (inout Desk, inout IDSource) throws(LayoutError) -> Void
) throws -> Arranger {
    var world = World()
    var history = UndoHistory()
    try world.addDesk(key)
    try world.edit(key, history: &history, build)
    var arranger = Arranger(gap: gap)
    _ = arranger.handle(.restore(world, homeFrames: [:]), now: .now)
    let somewhere = Rect(x: 200, y: 200, width: 400, height: 300)
    let infos = [a, b, c].filter { world[key]?.tree.state(of: $0) != nil }.map {
        WindowInfo(window: $0, frame: somewhere, state: absent.contains($0) ? .absent : .present, displayUUID: "main", learnedMinimum: minimums[$0])
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
        #expect(after.frames[c] == before.frames[c])
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
        #expect(after.frames[c] == before.frames[c], "c paid for the resize")
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

private func gapHandles(_ effects: [ArrangerEffect]) -> [[GapHandle]] {
    effects.compactMap { if case .gapHandles(let handles, "main") = $0 { handles } else { nil } }
}

/// The handle between children `first` and `second` of the root split, or of the split holding `parentOf`.
private func handle(_ arranger: Arranger, _ first: Int, _ second: Int, parentOf window: WindowRef? = nil) throws -> GapHandle {
    let desk = try #require(arranger.world[key])
    let split = try window.map { try #require(desk.tree.parent(of: try leaf(desk, $0))) } ?? desk.tree.root
    let found = GapHandles.handles(tree: desk.tree, resolution: try plan(arranger).resolution, gap: gap)
    return try #require(found.first { $0.split == split && $0.first == first && $0.second == second })
}

/// TILE-05, D-07, Pitfall 9, UI-SPEC Surface 3: dragging a gap resizes both sides live and commits once on mouse-up.
extension ArrangerResizeTests {
    @Test func theHandlesFollowEveryPlanAndGoUnderFourPoints() throws {
        var arranger = try arranger(row)
        let wider = arranger.handle(.gap(12), now: .now)
        let desk = try #require(arranger.world[key])
        let expected = GapHandles.handles(
            tree: desk.tree, resolution: try Planner.plan(desk: desk, area: visible, gap: 12, mins: [:]).resolution, gap: 12)
        #expect(expected.count == 2)
        #expect(gapHandles(wider) == [expected])
        #expect(gapHandles(arranger.handle(.gap(2), now: .now)) == [[]])
        #expect(gapHandles(arranger.handle(.gap(4), now: .now)).first?.count == 2)
    }

    @Test func aGapDragResizesBothSidesLiveAndCommitsOnMouseUp() throws {
        var arranger = try arranger(row)
        let before = try plan(arranger)
        let ta = try #require(before.frames[a]), tb = try #require(before.frames[b])
        let h = try handle(arranger, 0, 1)
        let live = arranger.handle(.gapDrag(h, delta: 50, ended: false), now: .now)
        let frames = setFrames(live)
        #expect(frames[a].map { near($0.width, ta.width + 50) } == true, "a did not follow: \(live)")
        #expect(frames[b].map { near($0.minX, tb.minX + 50) && $0.maxX == tb.maxX } == true, "b did not follow: \(live)")
        #expect(gapHandles(live).first?.first { $0.split == h.split && $0.first == 0 }.map { near($0.rect.minX, h.rect.minX + 50) } == true)
        #expect(arranger.history.depth(for: key) == 0)
        #expect(try plan(arranger) == before, "the World changed before mouse-up")

        _ = arranger.handle(.gapDrag(h, delta: 50, ended: true), now: .now)
        #expect(arranger.history.depth(for: key) == 1)
        let na = try #require(try plan(arranger).frames[a])
        #expect(near(na.width, ta.width + 50))
    }

    @Test func aGapNextToAMinimisedSiblingMovesWeightOnlyBetweenTheVisibleOnes() throws {
        var arranger = try arranger(absent: [b], row)
        let desk = try #require(arranger.world[key])
        guard case .split(_, _, let weights)? = desk.tree.node(try #require(desk.tree.root)) else {
            Issue.record("no root split")
            return
        }
        let h = try handle(arranger, 0, 2)
        _ = arranger.handle(.gapDrag(h, delta: 40, ended: true), now: .now)
        let after = try #require(arranger.world[key])
        guard case .split(_, _, let changed)? = after.tree.node(try #require(after.tree.root)) else {
            Issue.record("no root split")
            return
        }
        #expect(changed[1] == weights[1], "the minimised window's share moved")
        #expect(changed[0] > weights[0] && changed[2] < weights[2])
    }

    @Test func handlesHideWhilePausedDuringAWindowDragAndOnASpaceChange() throws {
        var paused = try arranger(row)
        #expect(gapHandles(paused.handle(.setPaused(.user, true), now: .now)) == [[]])
        let h = try handle(paused, 0, 1)
        #expect(setFrames(paused.handle(.gapDrag(h, delta: 50, ended: true), now: .now)).isEmpty)
        #expect(paused.history.depth(for: key) == 0)
        #expect(gapHandles(paused.handle(.setPaused(.user, false), now: .now)).first?.count == 2, "not back after Resume")

        var dragging = try arranger(row)
        let grab = Point(x: floatingFrame.midX, y: floatingFrame.minY + 10)
        var effects = dragging.handle(pointer(.down, grab.x, grab.y, press: f), now: .now)
        effects += dragging.handle(pointer(.dragged, grab.x - 10, grab.y), now: .now)
        effects += dragging.handle(.dragFrame(f.identity, Rect(x: floatingFrame.x - 10, y: floatingFrame.y, width: floatingFrame.width, height: floatingFrame.height)), now: .now)
        #expect(dragging.isDragging)
        #expect(gapHandles(effects) == [[]])

        var moving = try arranger(row)
        #expect(gapHandles(moving.handle(.event(.spaceChanged(displayUUID: "main", spaceID: 7)), now: .now)).first == [])
    }
}

/// G-03-3 H1: a gap whose growing side is held at a minimum above its weight share still moves by the drag.
extension ArrangerResizeTests {
    @Test func aGapNextToAPinnedSideMovesThatGapAndNoOther() throws {
        let mins = [a: Size(width: 700, height: 100)]
        var arranger = try arranger(minimums: mins, row)
        let before = try plan(arranger, mins: mins)
        let ta = try #require(before.frames[a]), tb = try #require(before.frames[b]), tc = try #require(before.frames[c])
        #expect(near(ta.width, 700), "a is not pinned: \(ta)")
        _ = arranger.handle(.gapDrag(try handle(arranger, 0, 1), delta: 50, ended: true), now: .now)
        #expect(arranger.history.depth(for: key) == 1)
        let after = try plan(arranger, mins: mins)
        let na = try #require(after.frames[a]), nb = try #require(after.frames[b])
        #expect(near(na.width, ta.width + 50), "\(ta) became \(na)")
        #expect(near(nb.minX, tb.minX + 50) && near(nb.maxX, tb.maxX), "\(tb) became \(nb)")
        let nc = try #require(after.frames[c])
        #expect(near(nc.minX, tc.minX) && near(nc.width, tc.width), "c moved: \(tc) became \(nc)")
    }

    @Test func aTwoChildGapWithAPinnedGrowingSideIsNotFrozen() throws {
        let mins = [a: Size(width: 1000, height: 100)]
        var arranger = try arranger(minimums: mins, corner)
        let before = try plan(arranger, mins: mins)
        let ta = try #require(before.frames[a]), tb = try #require(before.frames[b])
        #expect(near(ta.width, 1000), "a is not pinned: \(ta)")
        _ = arranger.handle(.gapDrag(try handle(arranger, 0, 1, parentOf: a), delta: 50, ended: true), now: .now)
        #expect(arranger.history.depth(for: key) == 1)
        let after = try plan(arranger, mins: mins)
        let na = try #require(after.frames[a]), nb = try #require(after.frames[b])
        #expect(near(na.width, ta.width + 50) && near(nb.width, tb.width - 50) && near(nb.maxX, tb.maxX), "\(ta) \(tb) became \(na) \(nb)")
    }

    @Test func aDragIntoThePinnedSidesOwnMinimumMovesNothing() throws {
        let mins = [a: Size(width: 1000, height: 100)]
        var arranger = try arranger(minimums: mins, corner)
        let before = try plan(arranger, mins: mins)
        let effects = arranger.handle(.gapDrag(try handle(arranger, 0, 1, parentOf: a), delta: -50, ended: true), now: .now)
        #expect(arranger.history.depth(for: key) == 0)
        #expect(setFrames(effects).isEmpty, "something moved: \(effects)")
        #expect(try plan(arranger, mins: mins).frames == before.frames)
    }

    @Test func theReBaseAloneIsNoEdit() throws {
        let mins = [a: Size(width: 700, height: 100)]
        var arranger = try arranger(minimums: mins, row)
        let before = try plan(arranger, mins: mins)
        let effects = arranger.handle(.gapDrag(try handle(arranger, 0, 1), delta: 0.4, ended: true), now: .now)
        #expect(arranger.history.depth(for: key) == 0)
        #expect(setFrames(effects).isEmpty, "something moved: \(effects)")
        #expect(try plan(arranger, mins: mins).frames == before.frames)
    }
}

/// G-03-3 H2: until mouse-up every replan plans the live gap move, so a mid-drag event never writes the pre-drag desk.
extension ArrangerResizeTests {
    /// A live +50 drag of the a|b gap of `row`: the pre-drag plan, the live frames and the handle.
    private func liveDrag(_ arranger: inout Arranger) throws -> (before: FramePlan, live: [WindowRef: Rect], handle: GapHandle) {
        let before = try plan(arranger)
        let h = try handle(arranger, 0, 1)
        let live = setFrames(arranger.handle(.gapDrag(h, delta: 50, ended: false), now: .now))
        #expect(live[a] != nil && live[b] != nil, "the drag moved nothing: \(live)")
        return (before, live, h)
    }

    /// No pre-drag tile and no pre-drag handle is sent; whatever is written is the live frame.
    private func expectLive(_ effects: [ArrangerEffect], _ drag: (before: FramePlan, live: [WindowRef: Rect], handle: GapHandle)) {
        let frames = setFrames(effects)
        for window in [a, b] {
            #expect(frames[window] != drag.before.frames[window], "\(window) went back to its pre-drag tile: \(effects)")
            if let frame = frames[window] { #expect(frame == drag.live[window], "\(window) left its live tile: \(frame)") }
        }
        for handles in gapHandles(effects) {
            let moved = handles.first { $0.split == drag.handle.split && $0.first == 0 }
            #expect(moved.map { near($0.rect.minX, drag.handle.rect.minX + 50) } ?? true, "the handle went back: \(handles)")
        }
    }

    @Test func aWindowChangeMidDragKeepsTheLiveLayout() throws {
        var arranger = try arranger(row)
        let drag = try liveDrag(&arranger)
        let info = WindowInfo(window: b, frame: try #require(drag.live[b]), state: .present, displayUUID: "main")
        expectLive(arranger.handle(.event(.windowChanged(info)), now: .now), drag)

        _ = arranger.handle(.gapDrag(drag.handle, delta: 50, ended: true), now: .now)
        #expect(arranger.history.depth(for: key) == 1)
        let committed = try plan(arranger)
        #expect(committed.frames[a] == drag.live[a] && committed.frames[b] == drag.live[b], "mouse-up committed something else")
    }

    @Test func anOffPlanFrameAndACorrectionTickMidDragKeepTheLiveLayout() throws {
        var arranger = try arranger(row)
        let drag = try liveDrag(&arranger)
        let ta = try #require(drag.before.frames[a])
        let start = ContinuousClock.now
        let stale = Rect(x: ta.x, y: ta.y, width: ta.width + 30, height: ta.height)
        expectLive(arranger.handle(.event(.windowResized(a, stale)), now: start), drag)
        let staler = Rect(x: ta.x, y: ta.y, width: ta.width + 20, height: ta.height)
        expectLive(arranger.handle(.event(.windowResized(a, staler)), now: start + .milliseconds(100)), drag)
        expectLive(arranger.handle(.tick, now: start + .seconds(2)), drag)

        _ = arranger.handle(.gapDrag(drag.handle, delta: 50, ended: true), now: start + .seconds(2))
        #expect(arranger.history.depth(for: key) == 1)
        #expect(try plan(arranger).frames[a] == drag.live[a])
    }

    @Test func anEndedEventWhilePausedClearsTheLiveMove() throws {
        var arranger = try arranger(row)
        let drag = try liveDrag(&arranger)
        _ = arranger.handle(.setPaused(.user, true), now: .now)
        #expect(setFrames(arranger.handle(.gapDrag(drag.handle, delta: 50, ended: true), now: .now)).isEmpty)
        #expect(arranger.history.depth(for: key) == 0)
        let resumed = setFrames(arranger.handle(.setPaused(.user, false), now: .now))
        #expect(try plan(arranger) == drag.before)
        #expect(resumed[a] == drag.before.frames[a] && resumed[b] == drag.before.frames[b], "the stale live move was applied: \(resumed)")
    }

    /// WR-01: a window left without room mid-drag floats once, for real, with one notice; later drag events give none.
    @Test func aWindowThatLosesItsRoomMidDragFloatsOnceWithOneNotice() throws {
        var arranger = try arranger(row)
        let drag = try liveDrag(&arranger)
        let info = WindowInfo(
            window: a, frame: try #require(drag.live[a]), state: .present, displayUUID: "main", learnedMinimum: Size(width: 1420, height: 100))
        let lost = arranger.handle(.event(.windowChanged(info)), now: .now)
        let notices: [Notice] = lost.compactMap { if case .notice(let notice) = $0 { notice } else { nil } }
        #expect(notices == [.lostRoom([a])])
        #expect(arranger.world[key]?.desktop.contains(a) == true, "the float was undone with the live move")
        let later = arranger.handle(.gapDrag(drag.handle, delta: 60, ended: false), now: .now) + arranger.handle(.tick, now: .now + .seconds(2))
            + arranger.handle(.gapDrag(drag.handle, delta: 60, ended: true), now: .now + .seconds(2))
        #expect(!later.contains { if case .notice = $0 { true } else { false } }, "\(later)")
    }

    @Test func aLiveMoveWhoseSplitIsGoneIsDropped() throws {
        var arranger = try arranger(corner)
        let h = try handle(arranger, 0, 1, parentOf: a)
        #expect(!setFrames(arranger.handle(.gapDrag(h, delta: 50, ended: false), now: .now)).isEmpty)
        let closed = arranger.handle(.event(.windowDestroyed(a)), now: .now)
        #expect(!closed.contains { if case .fault = $0 { true } else { false } }, "\(closed)")
        #expect(setFrames(closed)[b] == (try plan(arranger).frames[b]))
        let later = arranger.handle(.tick, now: .now + .seconds(2))
        #expect(!later.contains { if case .fault = $0 { true } else { false } }, "\(later)")
    }
}

/// [a .5 | empty .5]: a at the left half, the right half empty (8.1.1 D-16).
private func leftHalf(_ desk: inout Desk, _ ids: inout IDSource) throws(LayoutError) {
    try desk.tree.insertFourth(.panel(a), states: [a.identity: .present], slot: .firstHalf, axis: .horizontal, ids: &ids)
}

extension ArrangerResizeTests {
    /// 8.1.1 D-16, E7: the gap between a docked window and an empty area has a handle, and dragging it 100 pt right grows
    /// the window into the empty area in one undo step.
    @Test func aGapHandleGrowsAWindowIntoAnEmptyArea() throws {
        var arranger = try arranger(leftHalf)
        let before = try plan(arranger)
        let ta = try #require(before.frames[a])
        let h = try handle(arranger, 0, 1)
        let empty = try #require(before.resolution.nodeRects.first { arranger.world[key]?.tree.node($0.key) == .spacer }?.value)

        _ = arranger.handle(.gapDrag(h, delta: 100, ended: true), now: .now)

        #expect(arranger.history.depth(for: key) == 1)
        let after = try plan(arranger)
        let na = try #require(after.frames[a])
        #expect(near(na.width, ta.width + 100) && na.minX == ta.minX)
        let shrunk = try #require(after.resolution.nodeRects.first { arranger.world[key]?.tree.node($0.key) == .spacer }?.value)
        #expect(near(shrunk.width, empty.width - 100) && shrunk.maxX == empty.maxX)
    }
}

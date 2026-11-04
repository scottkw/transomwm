import TransomEngine
import TransomModel
import TransomTestSupport
import Testing

private let dragPID: Int32 = 900
private let dragBundle = "com.example.arranger"
private let area = Rect(x: 0, y: 25, width: 1440, height: 875)
private let mainKey = DeskKey(displayUUID: "main", spaceID: nil)

private func window(_ id: UInt32) -> WindowRef {
    WindowRef(identity: WindowIdentity(windowID: id, pid: dragPID, bundleID: dragBundle))
}

private let a = window(1), f = window(2), b = window(3)
private let frameA = Rect(x: 40, y: 80, width: 320, height: 232)
private let frameB = Rect(x: 730, y: 400, width: 150, height: 120)
/// Small, at the bottom right, clear of the tiles once a and b dock.
private let smallF = Rect(x: 1250, y: 700, width: 150, height: 100)

private func shifted(_ rect: Rect, _ dx: Double, _ dy: Double = 0) -> Rect {
    Rect(x: rect.x + dx, y: rect.y + dy, width: rect.width, height: rect.height)
}

private func pointer(_ kind: PointerEvent.Kind, _ x: Double, _ y: Double, _ modifiers: Modifiers = [], press: WindowRef? = nil) -> ArrangerInput {
    .pointer(PointerEvent(kind: kind, location: Point(x: x, y: y), modifiers: modifiers, pressWindow: press))
}

private func grab(_ frame: Rect) -> Point { Point(x: frame.midX, y: frame.minY + 10) }

/// Presses `window`'s title bar, drags 10 pt right (the session starts), then on to `dx`, `dy` from the press, the frame
/// following the pointer.
private func drag(
    _ harness: inout Harness, _ window: WindowRef, from frame: Rect, by dx: Double, _ dy: Double = 0, _ modifiers: Modifiers = []
) async -> [ArrangerEffect] {
    let start = grab(frame)
    var effects = await harness.send(pointer(.down, start.x, start.y, modifiers, press: window))
    effects += await harness.send(pointer(.dragged, start.x + 10, start.y, modifiers))
    effects += await harness.send(.dragFrame(window.identity, shifted(frame, 10)))
    effects += await move(&harness, window, from: frame, by: dx, dy, modifiers)
    return effects
}

/// The pointer and the frame on to `dx`, `dy` from the press.
private func move(
    _ harness: inout Harness, _ window: WindowRef, from frame: Rect, by dx: Double, _ dy: Double = 0, _ modifiers: Modifiers = []
) async -> [ArrangerEffect] {
    let start = grab(frame)
    var effects = await harness.send(pointer(.dragged, start.x + dx, start.y + dy, modifiers))
    effects += await harness.send(.dragFrame(window.identity, shifted(frame, dx, dy)))
    return effects
}

private func up(_ harness: inout Harness, from frame: Rect, by dx: Double, _ dy: Double = 0, _ modifiers: Modifiers = []) async -> [ArrangerEffect] {
    let start = grab(frame)
    return await harness.send(pointer(.up, start.x + dx, start.y + dy, modifiers))
}

private func previews(_ effects: [ArrangerEffect]) -> [PreviewState] {
    effects.compactMap { if case .preview(let state?, _) = $0 { state } else { nil } }
}

private func announced(_ effects: [ArrangerEffect]) -> [String] {
    effects.compactMap { if case .announce(let text) = $0 { text } else { nil } }
}

/// [a | b | Desktop] with f floating clear of both tiles, in `mode`, and the plan of that desk.
private func docked(_ mode: DragToDockMode = .holdOption) async throws -> (Harness, FramePlan) {
    var harness = await Harness.started(frames: [1: frameA, 2: smallF, 3: frameB])
    await harness.send(.command(.dock, focused: a))
    await harness.send(.command(.dock, focused: b))
    await harness.send(.dragToDock(mode))
    let plan = try Planner.plan(desk: try #require(harness.arranger.world[mainKey]), area: area, gap: 8, mins: [:])
    return (harness, plan)
}

/// How far from b's press the pointer must go to sit over the Desktop tile's centre.
private func toDesktop(_ plan: FramePlan, from frame: Rect) throws -> (dx: Double, dy: Double) {
    let desktop = try #require(plan.desktopRect)
    return (desktop.midX - grab(frame).x, desktop.midY - grab(frame).y)
}

/// TILE-22: Hold ⌥'s plain drag, its 16 pt rule (D-08, D-08a), and Automatically mode unchanged (D-07).
@Suite struct ArrangerHoldOptionTests {
    @Test func aPlainDragFloatsADockedWindowInsideTheDwell() async throws {
        var (harness, plan) = try await docked()
        let rb = try #require(plan.frames[b])
        let to = try toDesktop(plan, from: rb)
        let during = await drag(&harness, b, from: rb, by: to.dx, to.dy)
        let depth = harness.arranger.history.depth(for: mainKey)

        let released = await up(&harness, from: rb, by: to.dx, to.dy)

        let desk = try #require(harness.arranger.world[mainKey])
        #expect(desk.tree.state(of: b) == nil)
        #expect(desk.desktop.frame(of: b) == shifted(rb, to.dx, to.dy))
        #expect(harness.arranger.history.depth(for: mainKey) == depth + 1)
        #expect(announced(released) == [FourthCopy.floating])
        #expect(previews(during + released).isEmpty, "regions on a plain drag")
        // The neighbour reflows into what b left.
        let after = try Planner.plan(desk: desk, area: area, gap: 8, mins: [:])
        #expect(after.frames[a] != plan.frames[a] || after.desktopRect != plan.desktopRect)
    }

    @Test func aPlainDragPastTheDwellDrawsNothingAndGivesTheSameResult() async throws {
        var (harness, plan) = try await docked()
        let rb = try #require(plan.frames[b])
        let to = try toDesktop(plan, from: rb)
        _ = await drag(&harness, b, from: rb, by: to.dx, to.dy)
        harness.now += .milliseconds(150)
        #expect(previews(await harness.send(.tick)).isEmpty)

        let released = await up(&harness, from: rb, by: to.dx, to.dy)

        #expect(harness.arranger.world[mainKey]?.desktop.frame(of: b) == shifted(rb, to.dx, to.dy))
        #expect(announced(released) == [FourthCopy.floating])
    }

    @Test func releasedUnder16PointsADockedWindowSnapsBack() async throws {
        var (harness, plan) = try await docked()
        let rb = try #require(plan.frames[b])
        _ = await drag(&harness, b, from: rb, by: 15)
        harness.now += .milliseconds(150)
        #expect(previews(await harness.send(.tick)) == [.snapBack(rb, label: nil)])
        let depth = harness.arranger.history.depth(for: mainKey)

        let released = await up(&harness, from: rb, by: 15)

        #expect(harness.arranger.world[mainKey]?.tree.state(of: b) != nil)
        #expect(harness.arranger.history.depth(for: mainKey) == depth)
        #expect(announced(released).isEmpty)
        #expect(setFrames(released)[b] == rb)
    }

    @Test func releasedAt17PointsADockedWindowFloats() async throws {
        var (harness, plan) = try await docked()
        let rb = try #require(plan.frames[b])
        _ = await drag(&harness, b, from: rb, by: 17)
        let released = await up(&harness, from: rb, by: 17)
        #expect(harness.arranger.world[mainKey]?.tree.state(of: b) == nil)
        #expect(announced(released) == [FourthCopy.floating])
    }

    /// CONTEXT risk 3: the tile it leaves is no reason to stay.
    @Test func a30PointDragThatEndsOverItsOwnTileFloats() async throws {
        var (harness, plan) = try await docked()
        let rb = try #require(plan.frames[b])
        _ = await drag(&harness, b, from: rb, by: 0, 30)
        try #require(rb.contains(Point(x: grab(rb).x, y: grab(rb).y + 30)))
        _ = await up(&harness, from: rb, by: 0, 30)
        let desk = try #require(harness.arranger.world[mainKey])
        #expect(desk.tree.state(of: b) == nil)
        #expect(desk.desktop.contains(b))
    }

    /// UI-SPEC Surface 2: the neighbour reflows into what the window left, and the release frame crosses it.
    @Test func aPlainDragThatWouldCrossATileClampsAndAnnounces() async throws {
        var (harness, plan) = try await docked()
        let rb = try #require(plan.frames[b])
        _ = await drag(&harness, b, from: rb, by: 20)
        harness.now += .milliseconds(150)
        let tick = await harness.send(.tick)
        guard case .clamp = previews(tick).first else {
            Issue.record("no clamp ghost: \(tick)")
            return
        }
        let released = await up(&harness, from: rb, by: 20)
        let desk = try #require(harness.arranger.world[mainKey])
        let desktop = try #require(try Planner.plan(desk: desk, area: area, gap: 8, mins: [:]).desktopRect)
        let frame = try #require(desk.desktop.frame(of: b))
        #expect(desk.tree.state(of: b) == nil)
        #expect(frame.minX >= desktop.minX && frame.maxX <= desktop.maxX, "\(frame) is outside \(desktop)")
        #expect(announced(released) == [FourthCopy.floating])
    }

    /// Travel is the distance from the press, not the farthest point reached.
    @Test func outPast16AndBackTo10SnapsBack() async throws {
        var (harness, plan) = try await docked()
        let rb = try #require(plan.frames[b])
        _ = await drag(&harness, b, from: rb, by: 40)
        _ = await move(&harness, b, from: rb, by: 10)
        let depth = harness.arranger.history.depth(for: mainKey)
        let released = await up(&harness, from: rb, by: 10)
        #expect(harness.arranger.world[mainKey]?.tree.state(of: b) != nil)
        #expect(harness.arranger.history.depth(for: mainKey) == depth)
        #expect(setFrames(released)[b] == rb)
    }

    @Test func aPlainDragOfAFloatingWindowJustMovesIt() async throws {
        var (harness, _) = try await docked()
        let depth = harness.arranger.history.depth(for: mainKey)
        // Far enough over the Desktop tile that the regions would show in Automatically mode, and under 16 pt also moves.
        for dx in [-5.0, -60.0] {
            let from = try #require(harness.arranger.world[mainKey]?.desktop.frame(of: f))
            let during = await drag(&harness, f, from: from, by: dx)
            harness.now += .milliseconds(150)
            let tick = await harness.send(.tick)
            let released = await up(&harness, from: from, by: dx)
            #expect(previews(during + tick + released).isEmpty)
            #expect(announced(released).isEmpty)
            #expect(harness.arranger.world[mainKey]?.desktop.frame(of: f) == shifted(from, dx))
            #expect(harness.arranger.history.depth(for: mainKey) == depth)
        }
    }

    @Test func aShiftDragInHoldOptionFloatsPast3PointsAndAnnounces() async throws {
        var (harness, plan) = try await docked()
        let rb = try #require(plan.frames[b])
        let down = grab(rb)
        await harness.send(pointer(.down, down.x, down.y, [.shift], press: b))
        await harness.send(pointer(.dragged, down.x + 5, down.y, [.shift]))
        await harness.send(.dragFrame(b.identity, shifted(rb, 5)))
        harness.now += .milliseconds(150)
        await harness.send(.tick)
        let released = await up(&harness, from: rb, by: 5, 0, [.shift])
        #expect(harness.arranger.world[mainKey]?.tree.state(of: b) == nil)
        #expect(announced(released) == [FourthCopy.floating])
    }

    @Test func automaticallyAPlainDragOverTheDesktopCentreSnapsBackSilently() async throws {
        var (harness, plan) = try await docked(.automatic)
        let rb = try #require(plan.frames[b])
        let to = try toDesktop(plan, from: rb)
        _ = await drag(&harness, b, from: rb, by: to.dx, to.dy)
        let depth = harness.arranger.history.depth(for: mainKey)
        let released = await up(&harness, from: rb, by: to.dx, to.dy)
        #expect(harness.arranger.world[mainKey]?.tree.state(of: b) != nil)
        #expect(harness.arranger.history.depth(for: mainKey) == depth)
        #expect(announced(released).isEmpty)
        #expect(setFrames(released)[b] == rb)
    }

    @Test func automaticallyAShiftDragFloatsWithNoAnnouncement() async throws {
        var (harness, plan) = try await docked(.automatic)
        let rb = try #require(plan.frames[b])
        let to = try toDesktop(plan, from: rb)
        _ = await drag(&harness, b, from: rb, by: to.dx, to.dy, [.shift])
        harness.now += .milliseconds(150)
        await harness.send(.tick)
        let released = await up(&harness, from: rb, by: to.dx, to.dy, [.shift])
        #expect(harness.arranger.world[mainKey]?.tree.state(of: b) == nil)
        #expect(announced(released).isEmpty)
    }
}

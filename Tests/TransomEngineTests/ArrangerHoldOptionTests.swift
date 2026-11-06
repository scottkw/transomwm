@testable import TransomEngine
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

    /// UI-SPEC Surface 2: the neighbour reflows into what the window left, and the release frame crosses it. D-05: the
    /// window floats at its release frame; the clamp ghost still shows until 08.1.1-08 retires it.
    @Test func aPlainDragThatWouldCrossATileFloatsAtItsReleaseFrameAndAnnounces() async throws {
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
        #expect(desk.tree.state(of: b) == nil)
        #expect(desk.desktop.frame(of: b) == shifted(rb, 20))
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

    // MARK: ⌥ during a Hold ⌥ drag (D-09)

    @Test func optionPressedMidDragShowsTheRegionsAndDocks() async throws {
        var (harness, plan) = try await docked()
        let desktop = try #require(plan.desktopRect)
        let band = Point(x: desktop.minX + 5, y: desktop.midY)
        let dx = band.x - grab(smallF).x, dy = band.y - grab(smallF).y
        _ = await drag(&harness, f, from: smallF, by: dx, dy)
        await harness.send(pointer(.flagsChanged, band.x, band.y, [.option]))
        harness.now += .milliseconds(150)
        let tick = await harness.send(.tick)
        guard case .dock(let frame)? = previews(tick).first else {
            Issue.record("no dock preview: \(tick)")
            return
        }
        let depth = harness.arranger.history.depth(for: mainKey)

        let released = await harness.send(pointer(.up, band.x, band.y, [.option]))

        #expect(setFrames(released)[f] == frame)
        #expect(harness.arranger.world[mainKey]?.tree.state(of: f) != nil)
        #expect(harness.arranger.history.depth(for: mainKey) == depth + 1)
    }

    @Test func optionPressedWithTheDwellNotElapsedIsAMiss() async throws {
        var (harness, plan) = try await docked()
        let rb = try #require(plan.frames[b])
        let to = try toDesktop(plan, from: rb)
        _ = await drag(&harness, b, from: rb, by: to.dx, to.dy)
        await harness.send(pointer(.flagsChanged, grab(rb).x + to.dx, grab(rb).y + to.dy, [.option]))
        let depth = harness.arranger.history.depth(for: mainKey)
        let released = await up(&harness, from: rb, by: to.dx, to.dy, [.option])
        #expect(setFrames(released)[b] == rb, "the docked window did not snap back")
        #expect(harness.arranger.world[mainKey]?.tree.state(of: b) != nil)
        #expect(harness.arranger.history.depth(for: mainKey) == depth)

        _ = await drag(&harness, f, from: smallF, by: -60)
        await harness.send(pointer(.flagsChanged, grab(smallF).x - 60, grab(smallF).y, [.option]))
        await harness.send(pointer(.up, grab(smallF).x - 60, grab(smallF).y, [.option]))
        #expect(harness.arranger.world[mainKey]?.desktop.frame(of: f) == shifted(smallF, -60))
    }

    @Test func optionReleasedMidDragWithdrawsThePreviewAndTheReleaseIsPlainAtOnce() async throws {
        var (harness, plan) = try await docked()
        let rb = try #require(plan.frames[b]), desktop = try #require(plan.desktopRect)
        let band = Point(x: desktop.maxX - 5, y: desktop.midY)
        let dx = band.x - grab(rb).x, dy = band.y - grab(rb).y
        _ = await drag(&harness, b, from: rb, by: dx, dy, [.option])
        harness.now += .milliseconds(150)
        guard case .dock? = previews(await harness.send(.tick)).first else {
            Issue.record("no dock preview with ⌥ held")
            return
        }

        let flags = await harness.send(pointer(.flagsChanged, band.x, band.y))
        #expect(flags.contains(.preview(nil, displayUUID: "main")))
        let released = await harness.send(pointer(.up, band.x, band.y))

        #expect(harness.arranger.world[mainKey]?.tree.state(of: b) == nil, "the release was not the plain drag's")
        #expect(announced(released) == [FourthCopy.floating])
    }

    // MARK: The tap's ⌥ strip (D-07a)

    @Test func theStripIsOffUntilAPressIsClassifiedAsAMove() async throws {
        var (harness, _) = try await docked()
        #expect(harness.arranger.dragOptionStrip == .off)
        await harness.send(pointer(.down, grab(smallF).x, grab(smallF).y, press: f))
        #expect(harness.arranger.dragOptionStrip == .off)
        await harness.send(pointer(.dragged, grab(smallF).x - 10, grab(smallF).y))
        await harness.send(.dragFrame(f.identity, shifted(smallF, -10)))
        #expect(harness.arranger.dragOptionStrip == .always)
        await harness.send(pointer(.up, grab(smallF).x - 10, grab(smallF).y))
        #expect(harness.arranger.dragOptionStrip == .off)
    }

    @Test func automaticallyTheStripNeedsControl() async throws {
        var (harness, _) = try await docked(.automatic)
        _ = await drag(&harness, f, from: smallF, by: -60)
        #expect(harness.arranger.dragOptionStrip == .withControl)
    }

    @Test func aResizeSessionHasNoStrip() async throws {
        var (harness, plan) = try await docked()
        let rb = try #require(plan.frames[b])
        await harness.send(pointer(.down, rb.maxX, rb.midY, press: b))
        await harness.send(pointer(.dragged, rb.maxX + 10, rb.midY))
        await harness.send(.dragFrame(b.identity, Rect(x: rb.x, y: rb.y, width: rb.width + 10, height: rb.height)))
        #expect(harness.arranger.dragOptionStrip == .off)
    }

    @Test func aPauseThatEndsTheDragTurnsTheStripOff() async throws {
        var (harness, _) = try await docked()
        _ = await drag(&harness, f, from: smallF, by: -60)
        #expect(harness.arranger.dragOptionStrip == .always)
        await harness.send(.setPaused(.stageManager, true))
        await harness.send(pointer(.dragged, grab(smallF).x - 70, grab(smallF).y))
        #expect(harness.arranger.dragOptionStrip == .off)
    }

    /// WR-04: a session switch loses the mouse-up, and nothing else ends the session until the next press.
    @Test func aSessionSwitchEndsTheDragAndTheStrip() async throws {
        var (harness, _) = try await docked()
        _ = await drag(&harness, f, from: smallF, by: -60)
        #expect(harness.arranger.dragOptionStrip == .always)

        await harness.send(.event(.sessionPaused(true)))

        #expect(harness.arranger.drag == nil)
        #expect(harness.arranger.dragOptionStrip == .off)
    }

    @Test func aMoveSessionAfterALostMouseUpAsksForTheStripAgain() async throws {
        var (harness, _) = try await docked()
        _ = await drag(&harness, f, from: smallF, by: -60)
        #expect(harness.arranger.dragOptionStrip == .always)
        let frame = try #require(harness.arranger.windows[f.identity]?.frame)
        // No mouse-up: the next press abandons session A.
        await harness.send(pointer(.down, grab(frame).x, grab(frame).y, press: f))
        #expect(harness.arranger.dragOptionStrip == .off)
        await harness.send(pointer(.dragged, grab(frame).x - 10, grab(frame).y))
        await harness.send(.dragFrame(f.identity, shifted(frame, -10)))
        #expect(harness.arranger.dragOptionStrip == .always)
    }
}

// MARK: The precedence table (UI-SPEC Surface 2, D-08, D-09, D-10)

extension ArrangerHoldOptionTests {
    enum Place: Sendable { case desktopCentre, desktopBand, otherPanel }
    enum Outcome: Sendable { case floats, stays, swaps, docks, snapsBack }
}

/// A docked b dragged over `Place` and held past the dwell. ⌃ joins these rows with the fourths.
private let dockedDrops: [(DragToDockMode, Modifiers, ArrangerHoldOptionTests.Place, ArrangerHoldOptionTests.Outcome)] = [
    // Row 1: ⇧ first, with anything.
    (.automatic, [.shift], .desktopCentre, .floats), (.holdOption, [.shift], .desktopCentre, .floats),
    (.automatic, [.shift, .command], .otherPanel, .floats), (.holdOption, [.shift, .command], .otherPanel, .floats),
    (.automatic, [.shift, .option], .desktopBand, .floats), (.holdOption, [.shift, .option], .desktopBand, .floats),
    // Row 4: ⌘ over another docked panel.
    (.automatic, [.command], .otherPanel, .swaps), (.holdOption, [.command], .otherPanel, .swaps),
    (.holdOption, [.command, .option], .otherPanel, .swaps),
    // Row 5: Automatically is Phase 3, with ⌘ and ⌥ having no say here.
    (.automatic, [], .desktopBand, .docks), (.automatic, [], .desktopCentre, .snapsBack),
    (.automatic, [.command], .desktopBand, .docks), (.automatic, [.command], .desktopCentre, .snapsBack),
    (.automatic, [.option], .desktopBand, .docks), (.automatic, [.option], .desktopCentre, .snapsBack),
    // Row 6: ⌥ in Hold ⌥ mode acts as Automatically, also with ⌘ and no swap target.
    (.holdOption, [.option], .desktopBand, .docks), (.holdOption, [.option], .desktopCentre, .snapsBack),
    (.holdOption, [.command, .option], .desktopBand, .docks), (.holdOption, [.command, .option], .desktopCentre, .snapsBack),
    // Row 7: ⌘ with no swap target never pulls a window out.
    (.holdOption, [.command], .desktopCentre, .snapsBack), (.holdOption, [.command], .desktopBand, .snapsBack),
    // Row 8: the plain drag.
    (.holdOption, [], .desktopCentre, .floats), (.holdOption, [], .desktopBand, .floats), (.holdOption, [], .otherPanel, .floats),
]

/// A floating f dragged over `Place` and held past the dwell.
private let floatingDrops: [(DragToDockMode, Modifiers, ArrangerHoldOptionTests.Place, ArrangerHoldOptionTests.Outcome)] = [
    (.automatic, [], .desktopCentre, .stays), (.automatic, [], .desktopBand, .docks),
    (.automatic, [.command], .desktopBand, .docks), (.automatic, [.shift], .desktopBand, .stays),
    (.holdOption, [.option], .desktopCentre, .stays), (.holdOption, [.option], .desktopBand, .docks),
    (.holdOption, [.command, .option], .desktopBand, .docks), (.holdOption, [.shift], .desktopBand, .stays),
    (.holdOption, [], .desktopCentre, .stays), (.holdOption, [], .desktopBand, .stays),
    (.holdOption, [.command], .desktopCentre, .stays), (.holdOption, [.command], .desktopBand, .stays),
]

private let modes: [DragToDockMode] = [.automatic, .holdOption]

private func point(_ place: ArrangerHoldOptionTests.Place, _ plan: FramePlan) throws -> Point {
    let desktop = try #require(plan.desktopRect), ra = try #require(plan.frames[a])
    return switch place {
    case .desktopCentre: Point(x: desktop.midX, y: desktop.midY)
    case .desktopBand: Point(x: desktop.maxX - 5, y: desktop.midY)
    case .otherPanel: Point(x: ra.midX, y: ra.midY)
    }
}

extension ArrangerHoldOptionTests {
    @Test(arguments: dockedDrops)
    func aDockedWindowsDrop(mode: DragToDockMode, held: Modifiers, over place: Place, outcome: Outcome) async throws {
        var (harness, plan) = try await docked(mode)
        let rb = try #require(plan.frames[b])
        let to = try point(place, plan)
        let dx = to.x - grab(rb).x, dy = to.y - grab(rb).y
        _ = await drag(&harness, b, from: rb, by: dx, dy, held)
        harness.now += .milliseconds(150)
        await harness.send(.tick)
        let depth = harness.arranger.history.depth(for: mainKey)

        let released = await up(&harness, from: rb, by: dx, dy, held)

        let desk = try #require(harness.arranger.world[mainKey])
        switch outcome {
        case .floats:
            #expect(desk.tree.state(of: b) == nil && desk.desktop.contains(b), "b did not float")
            #expect(harness.arranger.history.depth(for: mainKey) == depth + 1)
        case .swaps:
            #expect(desk.tree.windows == [b, a], "no swap: \(desk.tree.windows)")
            #expect(harness.arranger.history.depth(for: mainKey) == depth + 1)
        case .docks:
            #expect(desk.tree.state(of: b) != nil, "b did not stay docked")
            #expect(harness.arranger.history.depth(for: mainKey) == depth + 1, "no dock happened")
        case .snapsBack, .stays:
            #expect(desk.tree.state(of: b) != nil, "b left its tile")
            #expect(setFrames(released)[b] == rb, "b did not snap back")
            #expect(harness.arranger.history.depth(for: mainKey) == depth)
            #expect(announced(released).isEmpty)
        }
    }

    @Test(arguments: floatingDrops)
    func aFloatingWindowsDrop(mode: DragToDockMode, held: Modifiers, over place: Place, outcome: Outcome) async throws {
        var (harness, plan) = try await docked(mode)
        let to = try point(place, plan)
        let dx = to.x - grab(smallF).x, dy = to.y - grab(smallF).y
        _ = await drag(&harness, f, from: smallF, by: dx, dy, held)
        harness.now += .milliseconds(150)
        await harness.send(.tick)
        let depth = harness.arranger.history.depth(for: mainKey)

        _ = await up(&harness, from: smallF, by: dx, dy, held)

        let desk = try #require(harness.arranger.world[mainKey])
        if outcome == .docks {
            #expect(desk.tree.state(of: f) != nil, "f did not dock")
            #expect(harness.arranger.history.depth(for: mainKey) == depth + 1)
        } else {
            #expect(desk.desktop.contains(f), "f left the Desktop tile")
            #expect(harness.arranger.history.depth(for: mainKey) == depth)
        }
    }

    // MARK: ⌘ with no swap target (rows 7 and 8)

    @Test func commandWithNoSwapTargetShowsTheSnapBackAndNeverPullsOut() async throws {
        var (harness, plan) = try await docked()
        let rb = try #require(plan.frames[b])
        let to = try toDesktop(plan, from: rb)
        _ = await drag(&harness, b, from: rb, by: to.dx, to.dy, [.command])
        harness.now += .milliseconds(150)
        #expect(previews(await harness.send(.tick)) == [.snapBack(rb, label: nil)])
        let depth = harness.arranger.history.depth(for: mainKey)

        let released = await up(&harness, from: rb, by: to.dx, to.dy, [.command])

        #expect(harness.arranger.world[mainKey]?.tree.state(of: b) != nil)
        #expect(harness.arranger.history.depth(for: mainKey) == depth)
        #expect(announced(released).isEmpty, "⌘ said Floating")
        #expect(setFrames(released)[b] == rb)
    }

    @Test func commandOnAFloatingWindowIsThePlainDrag() async throws {
        var (harness, _) = try await docked()
        let during = await drag(&harness, f, from: smallF, by: -60, 0, [.command])
        harness.now += .milliseconds(150)
        let tick = await harness.send(.tick)
        let released = await up(&harness, from: smallF, by: -60, 0, [.command])
        #expect(previews(during + tick + released).isEmpty)
        #expect(harness.arranger.world[mainKey]?.desktop.frame(of: f) == shifted(smallF, -60))
    }

    // MARK: The plain drag's refusals

    @Test func aPlainDragOfAWindowTooBigForTheDesktopIsBlockedAndSnapsBack() throws {
        // [[a | b] ; Desktop]: undocking a leaves [b ; Desktop], and b's 300 pt plus a's 600 pt do not fit in 875.
        var tree = LayoutTree.withDesktop()
        var ids = IDSource()
        try tree.insert(a, at: .top, of: .desktop, ids: &ids)
        try tree.insert(b, at: .right, of: try #require(tree.leaf(containing: a)), ids: &ids)
        let world = try World(ids: ids, desks: [mainKey: Desk(tree: tree)])
        let mins = [a: Size(width: 100, height: 600), b: Size(width: 100, height: 300)]
        let start = ContinuousClock.now
        var arranger = Arranger()
        _ = arranger.handle(.restore(world, homeFrames: [:]), now: start)
        let infos = [info(1, frame: frameA, minimum: mins[a]), info(3, frame: frameB, minimum: mins[b])]
        _ = arranger.handle(.inventory(WindowInventory(displays: [mainDisplay], windows: infos, initialRefreshComplete: true)), now: start)
        _ = arranger.handle(.dragToDock(.holdOption), now: start)
        let restored = try #require(arranger.world[mainKey])
        let ra = try #require(try Planner.plan(desk: restored, area: area, gap: 8, mins: mins).frames[a])
        let from = try #require(arranger.windows[a.identity]).frame
        let press = grab(from), to = Point(x: 700, y: 800)

        _ = arranger.handle(pointer(.down, press.x, press.y, press: a), now: start)
        _ = arranger.handle(pointer(.dragged, to.x, to.y), now: start)
        _ = arranger.handle(.dragFrame(a.identity, shifted(from, to.x - press.x, to.y - press.y)), now: start)
        let tick = arranger.handle(.tick, now: start + .milliseconds(150))
        let released = arranger.handle(pointer(.up, to.x, to.y), now: start + .milliseconds(200))

        #expect(previews(tick).contains { if case .blocked = $0 { true } else { false } }, "tick gave \(tick)")
        #expect(announced(released) == ["Not enough room to dock here"])
        #expect(arranger.world[mainKey]?.tree.state(of: a) == .present)
        #expect(setFrames(released)[a] == ra)
    }

    // MARK: Group dwell (D-09)

    @Test func withNoOptionAWindowHeldOnADockedCentreNeverGroups() async throws {
        var (harness, plan) = try await docked()
        let ra = try #require(plan.frames[a]), rb = try #require(plan.frames[b])
        let dx = rb.midX - grab(ra).x, dy = rb.midY - grab(ra).y
        var effects = await drag(&harness, a, from: ra, by: dx, dy)
        harness.now += DragSession.groupDwell
        effects += await harness.send(.tick)
        effects += await up(&harness, from: ra, by: dx, dy)
        #expect(groupPreviews(effects).isEmpty)
        let desk = try #require(harness.arranger.world[mainKey])
        #expect(desk.tree.node(try #require(desk.tree.leaf(containing: b))) == .panel(b), "b grew a group")
        #expect(desk.desktop.contains(a), "the result was not the plain drag's")
    }

    @Test func withOptionAWindowHeldOnADockedCentreGroups() async throws {
        var (harness, plan) = try await docked()
        let ra = try #require(plan.frames[a]), rb = try #require(plan.frames[b])
        let dx = rb.midX - grab(ra).x, dy = rb.midY - grab(ra).y
        _ = await drag(&harness, a, from: ra, by: dx, dy, [.option])
        harness.now += DragSession.groupDwell
        #expect(!groupPreviews(await harness.send(.tick)).isEmpty, "no Group preview with ⌥")
        _ = await up(&harness, from: ra, by: dx, dy, [.option])
        let tree = try #require(harness.arranger.world[mainKey]?.tree)
        #expect(tree.node(try #require(tree.leaf(containing: b))) == .tabs(windows: [b, a], selected: 1))
    }

    /// On the Desktop tile a floating window's centre is the target (Phase 7 D-02).
    @Test(arguments: [(Modifiers(), false), (Modifiers.option, true)])
    func aWindowHeldOnAFloatingCentreGroupsOnlyWithOption(held: Modifiers, groups: Bool) async throws {
        var harness = await Harness.started(frames: [1: frameA, 2: smallF, 3: frameB])
        await harness.send(.dragToDock(.holdOption))
        let dx = frameA.midX - grab(smallF).x, dy = frameA.midY - grab(smallF).y
        _ = await drag(&harness, f, from: smallF, by: dx, dy, held)
        harness.now += DragSession.groupDwell
        let tick = await harness.send(.tick)
        #expect(groupPreviews(tick).isEmpty != groups, "tick gave \(tick)")
        _ = await up(&harness, from: smallF, by: dx, dy, held)
        #expect(harness.arranger.world[mainKey]?.desktop.groups.isEmpty != groups)
    }

    // MARK: Tear-off (D-09)

    @Test func withNoOptionATornTabIgnoresARegionAndFloatsWithNoDwell() throws {
        let start = ContinuousClock.now
        var (arranger, group, _, content) = try holdOptionGroup(at: start)  // [a | [b, f]], f selected
        let ra = try tile(arranger, a)
        let to = Point(x: ra.minX + 0.1 * ra.width, y: ra.midY)
        let expected = Planner.clamp(landing(arranger, f, content: content, at: to), into: try desktopRect(arranger))
        _ = try tear(&arranger, f, of: group, to: to, at: start)
        let depth = arranger.history.depth(for: mainKey)

        let released = arranger.handle(pointer(.up, to.x, to.y), now: start)

        let desk = try #require(arranger.world[mainKey])
        #expect(desk.desktop.frame(of: f) == expected)
        #expect(desk.tree.node(group.node) == .panel(b))
        #expect(arranger.history.depth(for: mainKey) == depth + 1)
        #expect(released.contains(.tabAnnouncement(.movedOut(dissolved: true))))
    }

    @Test func withNoOptionATornTabShowsItsLandingFrameNotADockPreview() throws {
        let start = ContinuousClock.now
        var (arranger, group, _, content) = try holdOptionGroup(at: start)
        let ra = try tile(arranger, a)
        let to = Point(x: ra.minX + 0.1 * ra.width, y: ra.midY)
        let expected = Planner.clamp(landing(arranger, f, content: content, at: to), into: try desktopRect(arranger))
        _ = try tear(&arranger, f, of: group, to: to, at: start)
        let tick = arranger.handle(.tick, now: start + DragSession.dwell)
        #expect(previews(tick) == [.clamp(expected)], "tick gave \(tick)")
    }

    @Test func withNoOptionATornTabBackOverItsStripShowsNothingAndCancels() throws {
        let start = ContinuousClock.now
        var (arranger, group, _, _) = try holdOptionGroup(at: start)
        let ra = try tile(arranger, a), strip = try stripRect(arranger, group)
        _ = try tear(&arranger, f, of: group, to: Point(x: ra.midX, y: ra.midY), at: start)
        _ = arranger.handle(pointer(.dragged, strip.midX, strip.midY), now: start)
        let before = arranger.world
        let tick = arranger.handle(.tick, now: start + DragSession.dwell)
        #expect(previews(tick).isEmpty, "tick gave \(tick)")

        _ = arranger.handle(pointer(.up, strip.midX, strip.midY), now: start + .milliseconds(200))

        #expect(arranger.world == before)
        #expect(arranger.world[mainKey]?.tree.node(group.node) == .tabs(windows: [b, f], selected: 1))
    }

    @Test(arguments: [true, false])
    func withOptionATornTabDocksOnARegion(fromThePress: Bool) throws {
        let start = ContinuousClock.now
        var (arranger, group, _, _) = try holdOptionGroup(at: start)
        let ra = try tile(arranger, a)
        let to = Point(x: ra.minX + 0.1 * ra.width, y: ra.midY)
        _ = try tear(&arranger, f, of: group, to: to, fromThePress ? [.option] : [], at: start)
        if !fromThePress { _ = arranger.handle(pointer(.flagsChanged, to.x, to.y, [.option]), now: start) }
        let tick = arranger.handle(.tick, now: start + DragSession.dwell)
        #expect(previews(tick).contains { if case .dock = $0 { true } else { false } }, "tick gave \(tick)")

        _ = arranger.handle(pointer(.up, to.x, to.y, [.option]), now: start + .milliseconds(200))

        let tree = try #require(arranger.world[mainKey]?.tree)
        #expect(tree.node(try #require(tree.leaf(containing: f))) == .panel(f), "f did not dock as its own tile")
        #expect(tree.node(group.node) == .panel(b))
    }

    // MARK: A selected member's whole-group drag (D-09)

    @Test func withNoOptionTheWholeGroupFloatsFrom16Points() async throws {
        var (harness, _, content) = try await dockedGroup()
        let during = await drag(&harness, f, from: content, by: 300)
        let depth = harness.arranger.history.depth(for: mainKey)

        let released = await up(&harness, from: content, by: 300)

        let group = try #require(harness.arranger.world[mainKey]?.desktop.groups.first, "the group did not float")
        #expect(group.members == [b, f] && group.selected == 1)
        #expect(group.frame == TabBand.frame(ofContent: shifted(content, 300)))
        #expect(harness.arranger.world[mainKey]?.tree.windows == [a])
        #expect(harness.arranger.history.depth(for: mainKey) == depth + 1)
        #expect(announced(released) == [FourthCopy.floating])
        #expect(previews(during + released).isEmpty)
    }

    @Test func withNoOptionTheWholeGroupSnapsBackUnder16Points() async throws {
        var (harness, leaf, content) = try await dockedGroup()
        _ = await drag(&harness, f, from: content, by: 15)
        let depth = harness.arranger.history.depth(for: mainKey)

        let released = await up(&harness, from: content, by: 15)

        #expect(harness.arranger.world[mainKey]?.tree.node(leaf) == .tabs(windows: [b, f], selected: 1))
        #expect(harness.arranger.history.depth(for: mainKey) == depth)
        #expect(setFrames(released)[f] == content)
        #expect(announced(released).isEmpty)
    }

    @Test func withOptionTheWholeGroupDocksOnARegion() async throws {
        var (harness, _, content) = try await dockedGroup()
        let desk = try #require(harness.arranger.world[mainKey])
        let ra = try #require(try Planner.plan(desk: desk, area: area, gap: 8, mins: [:]).frames[a])
        let dx = ra.minX + 0.1 * ra.width - grab(content).x, dy = ra.midY - grab(content).y
        _ = await drag(&harness, f, from: content, by: dx, dy, [.option])
        harness.now += DragSession.dwell
        #expect(previews(await harness.send(.tick)).contains { if case .dock = $0 { true } else { false } })

        _ = await up(&harness, from: content, by: dx, dy, [.option])

        let tree = try #require(harness.arranger.world[mainKey]?.tree)
        #expect(tree.windows == [b, f, a], "the group did not move left of a: \(tree.windows)")
        #expect(tree.node(try #require(tree.leaf(containing: f))) == .tabs(windows: [b, f], selected: 1))
    }

    // MARK: What the option doesn't touch

    @Test(arguments: modes)
    func aPressWithNoTravelAndADoubleClickChangeNothing(mode: DragToDockMode) async throws {
        var (harness, plan) = try await docked(mode)
        let rb = try #require(plan.frames[b]), press = grab(rb)
        let before = harness.arranger.world
        var effects: [ArrangerEffect] = []
        for _ in 0..<2 {
            effects += await harness.send(pointer(.down, press.x, press.y, press: b))
            effects += await harness.send(pointer(.up, press.x, press.y))
        }
        #expect(harness.arranger.world == before)
        #expect(previews(effects).isEmpty && announced(effects).isEmpty)
        #expect(setFrames(effects).isEmpty)
    }

    @Test func aResizeDragIsTheSameInBothModes() async throws {
        func resized(_ mode: DragToDockMode) async throws -> (LayoutTree, [WindowRef: Rect], Bool) {
            var (harness, plan) = try await docked(mode)
            let ra = try #require(plan.frames[a])
            let before = harness.arranger.world[mainKey]?.tree
            await harness.send(pointer(.down, ra.maxX - 1, ra.midY, press: a))
            await harness.send(pointer(.dragged, ra.maxX + 39, ra.midY))
            await harness.send(.dragFrame(a.identity, Rect(x: ra.x, y: ra.y, width: ra.width + 40, height: ra.height)))
            let released = await harness.send(pointer(.up, ra.maxX + 39, ra.midY))
            let tree = try #require(harness.arranger.world[mainKey]?.tree)
            return (tree, setFrames(released), tree != before)
        }
        let automatic = try await resized(.automatic), hold = try await resized(.holdOption)
        #expect(automatic.2, "the resize moved no boundary")
        #expect(hold.0 == automatic.0)
        #expect(hold.1 == automatic.1)
        #expect(hold.0.state(of: a) != nil, "a resize pulled a window out")
    }

    /// D-10: docking and floating by keyboard don't read the mode.
    @Test func theKeyboardActsTheSameInBothModes() async throws {
        func run(_ mode: DragToDockMode) async throws -> [LayoutTree] {
            var (harness, _) = try await docked(mode)
            var trees: [LayoutTree] = []
            for command in [Command.dock, .float] {
                let effects = await harness.send(.command(command, focused: f))
                #expect(announced(effects).isEmpty)
                trees.append(try #require(harness.arranger.world[mainKey]?.tree))
            }
            #expect(harness.arranger.world[mainKey]?.desktop.contains(f) == true)
            return trees
        }
        let trees = try await run(.holdOption)
        #expect(trees[0].state(of: f) != nil, "⌃⌥⌘D did not dock in Hold ⌥ mode")
        #expect(trees == (try await run(.automatic)))
    }

    @Test(arguments: modes)
    func aPausedDragGetsNoSession(mode: DragToDockMode) async throws {
        var (harness, _) = try await docked(mode)
        await harness.send(.setPaused(.user, true))
        var effects = await drag(&harness, f, from: smallF, by: -60)
        harness.now += .milliseconds(150)
        effects += await harness.send(.tick)
        effects += await up(&harness, from: smallF, by: -60)
        #expect(harness.arranger.drag == nil)
        #expect(previews(effects).isEmpty)
        #expect(!effects.contains(.pollDragFrame(f)))
    }
}

// MARK: Group and tear-off helpers, as in ArrangerTabsTests, where they are private

private let mainDisplay = DisplayInfo(uuid: "main", frame: Rect(x: 0, y: 0, width: 1440, height: 900), visibleFrame: area, currentSpaceID: nil)

private func info(_ id: UInt32, frame: Rect, minimum: Size? = nil) -> WindowInfo {
    WindowInfo(window: window(id), frame: frame, state: .present, displayUUID: "main", kind: .dockable, isExcluded: false, learnedMinimum: minimum)
}

private func groupPreviews(_ effects: [ArrangerEffect]) -> [PreviewState] {
    previews(effects).filter { if case .group = $0 { true } else { false } }
}

private func tile(_ arranger: Arranger, _ window: WindowRef) throws -> Rect {
    let desk = try #require(arranger.world[mainKey])
    return try #require(try Planner.plan(desk: desk, area: area, gap: 8, mins: [:]).frames[window])
}

private func desktopRect(_ arranger: Arranger) throws -> Rect {
    let desk = try #require(arranger.world[mainKey])
    return try #require(try Planner.plan(desk: desk, area: area, gap: 8, mins: [:]).desktopRect)
}

/// [a | [b, f]], f selected, on an Arranger with no window system, in Hold ⌥ mode.
private func holdOptionGroup(at now: ContinuousClock.Instant) throws -> (Arranger, GroupKey, frame: Rect, content: Rect) {
    var arranger = Arranger()
    let infos = [info(1, frame: frameA), info(2, frame: smallF), info(3, frame: frameB)]
    _ = arranger.handle(.inventory(WindowInventory(displays: [mainDisplay], windows: infos, initialRefreshComplete: true)), now: now)
    _ = arranger.handle(.command(.dock, focused: a), now: now)
    _ = arranger.handle(.command(.dock, focused: b), now: now)
    let leaf = try #require(arranger.world[mainKey]?.tree.leaf(containing: b))
    try arranger.world.edit(mainKey, history: &arranger.history) { desk, _ throws(LayoutError) in
        try desk.desktop.remove(f)
        try desk.tree.group(f, into: leaf)
    }
    _ = arranger.handle(.gap(8), now: now)  // re-plans
    _ = arranger.handle(.dragToDock(.holdOption), now: now)
    let plan = try Planner.plan(desk: try #require(arranger.world[mainKey]), area: area, gap: 8, mins: [:])
    let frame = try #require(plan.resolution.nodeRects[leaf])
    return (arranger, GroupKey(desk: mainKey, node: leaf), frame, TabBand.content(of: frame))
}

/// The strip shown for `group` on the main display.
private func stripRect(_ arranger: Arranger, _ group: GroupKey) throws -> Rect {
    try #require(arranger.tabs.shownStrips["main"]?.first { $0.group == group }?.frame, "no strip shown for \(group)")
}

/// Presses `member`'s tab at the strip's centre, drags 2 pt inside the strip, then out to `point`.
private func tear(
    _ arranger: inout Arranger, _ member: WindowRef, of group: GroupKey, to point: Point, _ modifiers: Modifiers = [],
    at now: ContinuousClock.Instant
) throws -> [ArrangerEffect] {
    let strip = try stripRect(arranger, group)
    let press = PointerEvent(kind: .down, location: Point(x: strip.midX, y: strip.midY), modifiers: modifiers, pressTab: member)
    var effects = arranger.handle(.pointer(press), now: now)
    effects += arranger.handle(pointer(.dragged, strip.midX + 2, strip.midY, modifiers), now: now)
    effects += arranger.handle(pointer(.dragged, point.x, point.y, modifiers), now: now)
    return effects
}

/// The frame a tear-off of `member` lands at with the pointer at `point`, before the clamp.
private func landing(_ arranger: Arranger, _ member: WindowRef, content: Rect, at point: Point) -> Rect {
    let wanted = arranger.wantedFrames[member.identity]
    let width = wanted?.width ?? content.width, height = wanted?.height ?? content.height
    return Rect(x: point.x - width / 2, y: point.y - 12, width: width, height: height)
}

/// [a | [b, f]], f selected, formed in Automatically by a held drag, then in Hold ⌥ mode.
private func dockedGroup() async throws -> (Harness, leaf: NodeID, content: Rect) {
    var (harness, plan) = try await docked(.automatic)
    let rb = try #require(plan.frames[b])
    let dx = rb.midX - grab(smallF).x, dy = rb.midY - grab(smallF).y
    _ = await drag(&harness, f, from: smallF, by: dx, dy)
    harness.now += DragSession.groupDwell
    await harness.send(.tick)
    await harness.send(pointer(.up, rb.midX, rb.midY))
    await harness.send(.dragToDock(.holdOption))
    let desk = try #require(harness.arranger.world[mainKey])
    let leaf = try #require(desk.tree.leaf(containing: f))
    try #require(desk.tree.node(leaf) == .tabs(windows: [b, f], selected: 1), "f did not group with b")
    let content = try #require(try Planner.plan(desk: desk, area: area, gap: 8, mins: [:]).frames[f])
    try #require(await harness.frame(f) == content)
    return (harness, leaf, content)
}

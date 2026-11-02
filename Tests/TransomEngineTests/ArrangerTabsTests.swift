@testable import TransomEngine
import TransomModel
import TransomTestSupport
import Testing

private let area = Rect(x: 0, y: 25, width: 1440, height: 875)
private let mainKey = DeskKey(displayUUID: "main", spaceID: nil)
private let mainDisplay = DisplayInfo(uuid: "main", frame: Rect(x: 0, y: 0, width: 1440, height: 900), visibleFrame: area, currentSpaceID: nil)

private func window(_ id: UInt32) -> WindowRef {
    WindowRef(identity: WindowIdentity(windowID: id, pid: 900, bundleID: "com.example.arranger"))
}

private let a = window(1), b = window(3), f = window(2)
private let frameA = Rect(x: 40, y: 80, width: 320, height: 232)
private let frameB = Rect(x: 730, y: 400, width: 150, height: 120)
/// Small, at the bottom right, clear of the tiles once a and b dock.
private let smallF = Rect(x: 1250, y: 700, width: 150, height: 100)

private func pointer(_ kind: PointerEvent.Kind, _ x: Double, _ y: Double, _ modifiers: Modifiers = [], press: WindowRef? = nil) -> ArrangerInput {
    .pointer(PointerEvent(kind: kind, location: Point(x: x, y: y), modifiers: modifiers, pressWindow: press))
}

private func shifted(_ rect: Rect, _ dx: Double, _ dy: Double = 0) -> Rect {
    Rect(x: rect.x + dx, y: rect.y + dy, width: rect.width, height: rect.height)
}

private func centre(_ rect: Rect) -> Point { Point(x: rect.midX, y: rect.midY) }

private func previews(_ effects: [ArrangerEffect]) -> [PreviewState] {
    effects.compactMap { if case .preview(let state?, _) = $0 { state } else { nil } }
}

private func parks(_ effects: [ArrangerEffect]) -> [WindowCommand] {
    effects.flatMap { effect -> [WindowCommand] in
        guard case .perform(let commands) = effect else { return [] }
        return commands.filter { if case .park = $0 { true } else { false } }
    }
}

/// Presses `window`'s title bar, drags 10 pt right (the session starts), then on to `point`, the frame following.
private func drag(
    _ harness: inout Harness, _ window: WindowRef, from frame: Rect, to point: Point, _ modifiers: Modifiers = []
) async -> [ArrangerEffect] {
    let grab = Point(x: frame.midX, y: frame.minY + 10)
    var effects = await harness.send(pointer(.down, grab.x, grab.y, modifiers, press: window))
    effects += await harness.send(pointer(.dragged, grab.x + 10, grab.y, modifiers))
    effects += await harness.send(.dragFrame(window.identity, shifted(frame, 10)))
    effects += await harness.send(pointer(.dragged, point.x, point.y, modifiers))
    effects += await harness.send(.dragFrame(window.identity, shifted(frame, point.x - grab.x, point.y - grab.y)))
    return effects
}

/// [a | b | Desktop] with f floating clear of both tiles, and the plan of that desk.
private func docked() async throws -> (Harness, FramePlan) {
    var harness = await Harness.started(frames: [1: frameA, 2: smallF, 3: frameB])
    await harness.send(.command(.dock, focused: a))
    await harness.send(.command(.dock, focused: b))
    let plan = try Planner.plan(desk: try #require(harness.arranger.world[mainKey]), area: area, gap: 8, mins: [:])
    let ra = try #require(plan.frames[a]), rb = try #require(plan.frames[b])
    #expect(abs(rb.minX - ra.maxX - 8) < 0.5, "a and b are not side by side: \(ra) \(rb)")
    return (harness, plan)
}

/// The group frame a centre drop of `window` on `target`'s leaf gives on the main desk.
private func groupFrame(_ arranger: Arranger, _ window: WindowRef, on target: WindowRef, mins: [WindowRef: Size] = [:]) throws -> Rect {
    var desk = try #require(arranger.world[mainKey])
    var ids = arranger.world.ids
    let leaf = try #require(desk.tree.leaf(containing: target))
    if desk.desktop.contains(window) { try desk.desktop.remove(window) } else { try desk.tree.remove(window) }
    try desk.tree.applyDrop(.tile(leaf, .center), window: window, ids: &ids)
    return try #require(try Planner.plan(desk: desk, area: area, gap: 8, mins: mins).resolution.nodeRects[leaf])
}

/// TABS-01, D-01 to D-04, D-07: a centre held for 400 ms groups on release, through the pure Arranger and the fake.
@Suite struct ArrangerTabsTests {
    @Test func aReleaseInACentreBeforeTheGroupDwellIsTheMissWithNoBeep() async throws {
        var (harness, plan) = try await docked()
        let ra = try #require(plan.frames[a]), rb = try #require(plan.frames[b])
        _ = await drag(&harness, a, from: ra, to: centre(rb))
        harness.now += .milliseconds(150)
        #expect(previews(await harness.send(.tick)) == [.snapBack(ra, label: nil)])
        harness.now += .milliseconds(249)
        let tick = await harness.send(.tick)
        #expect(previews(tick).isEmpty, "a preview changed before 400 ms: \(tick)")
        let depth = harness.arranger.history.depth(for: mainKey)

        let up = await harness.send(pointer(.up, rb.midX, rb.midY))
        #expect(!up.contains(.beep))
        #expect(setFrames(up)[a] == ra, "a was not put back")
        #expect(harness.arranger.history.depth(for: mainKey) == depth)
        let desk = try #require(harness.arranger.world[mainKey])
        #expect(desk.tree.node(try #require(desk.tree.leaf(containing: b))) == .panel(b))
    }

    @Test func aCentreHeldFor400msGroupsWithTheDraggedWindowSelected() async throws {
        var (harness, plan) = try await docked()
        let ra = try #require(plan.frames[a]), rb = try #require(plan.frames[b])
        let during = await drag(&harness, a, from: ra, to: centre(rb))
        #expect(during.contains { if case .wake = $0 { true } else { false } })
        let frame = try groupFrame(harness.arranger, a, on: b)
        harness.now += .milliseconds(400)
        let tick = await harness.send(.tick)
        #expect(
            previews(tick) == [.group(frame: frame, strip: TabBand.strip(of: frame), label: "Group as tabs")], "tick gave \(tick)")
        let depth = harness.arranger.history.depth(for: mainKey)
        let leaf = try #require(harness.arranger.world[mainKey]?.tree.leaf(containing: b))

        let up = await harness.send(pointer(.up, rb.midX, rb.midY))
        let content = TabBand.content(of: frame)
        #expect(harness.arranger.world[mainKey]?.tree.node(leaf) == .tabs(windows: [b, a], selected: 1))
        #expect(harness.arranger.history.depth(for: mainKey) == depth + 1, "grouping is not one undo step")
        #expect(up.contains(.tabAnnouncement(.grouped(tabs: 2))))
        #expect(!up.contains(.beep))
        // Exactly one member is written into the tile; the other parks at the content size (D-07, Pitfall 1).
        let written = setFrames(up).filter { $0.key == a || $0.key == b }
        #expect(written == [a: content], "group writes: \(written)")
        #expect(parks(up) == [.park(b, displayUUID: "main", size: Size(width: content.width, height: content.height))])
        #expect(await harness.frame(a) == content)
        let parked = try #require(await harness.frame(b))
        #expect(parked.width == content.width && parked.height == content.height)
        #expect(harness.arranger.isParked(b))
    }

    @Test func undoAfterGroupingReturnsBothWindowsToTheirTiles() async throws {
        var (harness, plan) = try await docked()
        let ra = try #require(plan.frames[a]), rb = try #require(plan.frames[b])
        _ = await drag(&harness, a, from: ra, to: centre(rb))
        harness.now += .milliseconds(400)
        await harness.send(.tick)
        await harness.send(pointer(.up, rb.midX, rb.midY))

        await harness.send(.command(.undo, focused: a))
        #expect(await harness.frame(a) == ra)
        #expect(await harness.frame(b) == rb)
        #expect(!harness.arranger.isParked(b))
    }

    @Test func theGroupDeadlineWakesTheEngine() async throws {
        var (harness, plan) = try await docked()
        let ra = try #require(plan.frames[a]), rb = try #require(plan.frames[b])
        _ = await drag(&harness, a, from: ra, to: centre(rb))
        harness.now += .milliseconds(150)
        let tick = await harness.send(.tick)
        #expect(tick.contains(.wake(at: harness.now + .milliseconds(250))), "no wake at the group deadline: \(tick)")
    }
}

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

private func pointer(
    _ kind: PointerEvent.Kind, _ x: Double, _ y: Double, _ modifiers: Modifiers = [], press: WindowRef? = nil, stacking: [WindowRef]? = nil
) -> ArrangerInput {
    .pointer(PointerEvent(
        kind: kind, location: Point(x: x, y: y), modifiers: modifiers, pressWindow: press, stacking: stacking?.map(\.identity)))
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
/// `stacking` is the press's front-to-back order from the shell (8.1.1 D-18).
private func drag(
    _ harness: inout Harness, _ window: WindowRef, from frame: Rect, to point: Point, _ modifiers: Modifiers = [],
    stacking: [WindowRef]? = nil
) async -> [ArrangerEffect] {
    let grab = Point(x: frame.midX, y: frame.minY + 10)
    var effects = await harness.send(pointer(.down, grab.x, grab.y, modifiers, press: window, stacking: stacking))
    effects += await harness.send(pointer(.dragged, grab.x + 10, grab.y, modifiers))
    effects += await harness.send(.dragFrame(window.identity, shifted(frame, 10)))
    effects += await harness.send(pointer(.dragged, point.x, point.y, modifiers))
    effects += await harness.send(.dragFrame(window.identity, shifted(frame, point.x - grab.x, point.y - grab.y)))
    return effects
}

/// [a | b] across the whole visible frame with f floating over b, and the plan of that desk.
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

/// Moves the pointer of a drag that grabbed `frame`'s title bar on to `point`, the frame following.
private func move(_ harness: inout Harness, _ window: WindowRef, from frame: Rect, to point: Point, _ modifiers: Modifiers = []) async -> [ArrangerEffect] {
    let grab = Point(x: frame.midX, y: frame.minY + 10)
    var effects = await harness.send(pointer(.dragged, point.x, point.y, modifiers))
    effects += await harness.send(.dragFrame(window.identity, shifted(frame, point.x - grab.x, point.y - grab.y)))
    return effects
}

/// The same drag on an Arranger with no window system behind it.
private func drag(
    _ arranger: inout Arranger, _ window: WindowRef, from frame: Rect, to point: Point, _ modifiers: Modifiers = [],
    at now: ContinuousClock.Instant
) -> [ArrangerEffect] {
    let grab = Point(x: frame.midX, y: frame.minY + 10)
    var effects = arranger.handle(pointer(.down, grab.x, grab.y, modifiers, press: window), now: now)
    effects += arranger.handle(pointer(.dragged, grab.x + 10, grab.y, modifiers), now: now)
    effects += arranger.handle(.dragFrame(window.identity, shifted(frame, 10)), now: now)
    effects += arranger.handle(pointer(.dragged, point.x, point.y, modifiers), now: now)
    effects += arranger.handle(.dragFrame(window.identity, shifted(frame, point.x - grab.x, point.y - grab.y)), now: now)
    return effects
}

private func info(_ id: UInt32, frame: Rect, minimum: Size? = nil) -> WindowInfo {
    WindowInfo(window: window(id), frame: frame, state: .present, displayUUID: "main", kind: .dockable, isExcluded: false, learnedMinimum: minimum)
}

/// a and b docked side by side by the keyboard on an Arranger with no window system (zoom on or off), `aMinimum` a's
/// learned minimum; returns it with b's tile.
private func bareDocked(aMinimum: Size? = nil, bMinimum: Size? = nil, zoom: Bool = false) throws -> (Arranger, Rect) {
    var arranger = Arranger()
    let infos = [info(1, frame: frameA, minimum: aMinimum), info(3, frame: frameB, minimum: bMinimum)]
    _ = arranger.handle(.inventory(WindowInventory(displays: [mainDisplay], windows: infos, initialRefreshComplete: true)), now: .now)
    if zoom { _ = arranger.handle(.zoomEnabled(true), now: .now) }
    _ = arranger.handle(.command(.dock, focused: a), now: .now)
    _ = arranger.handle(.command(.dock, focused: b), now: .now)
    let desk = try #require(arranger.world[mainKey])
    try #require(desk.tree.state(of: a) == .present && desk.tree.state(of: b) == .present, "a and b did not dock")
    let plan = try Planner.plan(desk: desk, area: area, gap: 8, mins: arranger.minimums)
    let leaf = try #require(desk.tree.leaf(containing: b))
    return (arranger, try #require(plan.resolution.nodeRects[leaf]))
}

/// f dragged onto b's centre, held 400 ms and released: the group [b, f].
private func groupFWithB(_ harness: inout Harness, _ rb: Rect) async {
    _ = await drag(&harness, f, from: smallF, to: centre(rb))
    harness.now += .milliseconds(400)
    await harness.send(.tick)
    await harness.send(pointer(.up, rb.midX, rb.midY))
}

private func groupPreviews(_ effects: [ArrangerEffect]) -> [PreviewState] {
    previews(effects).filter { if case .group = $0 { true } else { false } }
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

/// The UI-SPEC Surface 1 dwell contract: 400 ms within 16 pt, modifiers, exclusions, room and undo.
extension ArrangerTabsTests {
    @Test func aMoveOfMoreThan16ptInsideTheCentreRestartsTheGroupDwell() async throws {
        var (harness, plan) = try await docked()
        let ra = try #require(plan.frames[a]), rb = try #require(plan.frames[b])
        _ = await drag(&harness, a, from: ra, to: centre(rb))
        harness.now += .milliseconds(300)
        _ = await move(&harness, a, from: ra, to: Point(x: rb.midX + 17, y: rb.midY))
        harness.now += .milliseconds(100)
        #expect(groupPreviews(await harness.send(.tick)).isEmpty, "the dwell did not restart after a 17 pt move")
        harness.now += .milliseconds(300)
        #expect(groupPreviews(await harness.send(.tick)).count == 1, "no group 400 ms after the restart")
    }

    @Test func aMoveWithin16ptKeepsTheGroupDwell() async throws {
        var (harness, plan) = try await docked()
        let ra = try #require(plan.frames[a]), rb = try #require(plan.frames[b])
        _ = await drag(&harness, a, from: ra, to: centre(rb))
        harness.now += .milliseconds(300)
        _ = await move(&harness, a, from: ra, to: Point(x: rb.midX + 15, y: rb.midY))
        harness.now += .milliseconds(100)
        #expect(groupPreviews(await harness.send(.tick)).count == 1, "a 15 pt move restarted the dwell")
    }

    @Test func leavingTheCentreCancelsTheDwellAndAReturnNeedsANewOne() async throws {
        var (harness, plan) = try await docked()
        let ra = try #require(plan.frames[a]), rb = try #require(plan.frames[b])
        _ = await drag(&harness, a, from: ra, to: centre(rb))
        harness.now += .milliseconds(200)
        _ = await move(&harness, a, from: ra, to: Point(x: rb.maxX - 5, y: rb.midY))  // b's right edge band
        harness.now += .milliseconds(100)
        _ = await move(&harness, a, from: ra, to: centre(rb))
        harness.now += .milliseconds(100)
        #expect(groupPreviews(await harness.send(.tick)).isEmpty, "the dwell survived leaving the centre")
        harness.now += .milliseconds(300)
        #expect(groupPreviews(await harness.send(.tick)).count == 1)
    }

    @Test func onceShownTheGroupPreviewFollowsThePointerAnywhereInTheCentre() async throws {
        var (harness, plan) = try await docked()
        let ra = try #require(plan.frames[a]), rb = try #require(plan.frames[b])
        _ = await drag(&harness, a, from: ra, to: centre(rb))
        harness.now += .milliseconds(400)
        #expect(groupPreviews(await harness.send(.tick)).count == 1)
        let far = Point(x: rb.minX + rb.width * 0.3, y: rb.minY + rb.height * 0.3)
        let moved = await move(&harness, a, from: ra, to: far)
        #expect(!moved.contains { if case .preview(nil, _) = $0 { true } else { false } }, "the preview was withdrawn: \(moved)")
        await harness.send(pointer(.up, far.x, far.y))
        let leaf = try #require(harness.arranger.world[mainKey]?.tree.leaf(containing: b))
        #expect(harness.arranger.world[mainKey]?.tree.node(leaf) == .tabs(windows: [b, a], selected: 1))
    }

    @Test func shiftBypassesGrouping() async throws {
        var (harness, plan) = try await docked()
        let ra = try #require(plan.frames[a]), rb = try #require(plan.frames[b])
        _ = await drag(&harness, a, from: ra, to: centre(rb), [.shift])
        harness.now += .milliseconds(400)
        #expect(groupPreviews(await harness.send(.tick)).isEmpty)
        await harness.send(pointer(.up, rb.midX, rb.midY, [.shift]))
        let desk = try #require(harness.arranger.world[mainKey])
        // D-05: it floats at its release frame, over b's tile.
        #expect(desk.desktop.frame(of: a) == shifted(ra, rb.midX - ra.midX, rb.midY - ra.minY - 10), "⇧ did not undock at the release frame")
        #expect(desk.tree.node(try #require(desk.tree.leaf(containing: b))) == .panel(b))
    }

    @Test func commandOverAPlainDockedPanelSwapsInsteadOfGrouping() async throws {
        var (harness, plan) = try await docked()
        let ra = try #require(plan.frames[a]), rb = try #require(plan.frames[b])
        _ = await drag(&harness, a, from: ra, to: centre(rb), [.command])
        harness.now += .milliseconds(400)
        let tick = await harness.send(.tick)
        #expect(previews(tick) == [.swap(target: rb, origin: ra)], "tick gave \(tick)")
        let up = await harness.send(pointer(.up, rb.midX, rb.midY, [.command]))
        #expect(up.contains(.announce("Swapped")))
    }

    @Test func commandOverAGroupIsIgnoredAndTheDwellRuns() async throws {
        var (harness, plan) = try await docked()
        let rb = try #require(plan.frames[b])
        await groupFWithB(&harness, rb)
        let leaf = try #require(harness.arranger.world[mainKey]?.tree.leaf(containing: b))
        let now = try Planner.plan(desk: try #require(harness.arranger.world[mainKey]), area: area, gap: 8, mins: [:])
        let group = try #require(now.resolution.nodeRects[leaf]), from = try #require(now.frames[a])
        _ = await drag(&harness, a, from: from, to: centre(TabBand.content(of: group)), [.command])
        harness.now += .milliseconds(400)
        let tick = await harness.send(.tick)
        #expect(groupPreviews(tick).count == 1, "⌘ over a group stopped the dwell: \(tick)")
    }

    /// An excluded or never-dock window leaves the tree when it is reported so (D-29), so its tile is gone before any
    /// drag can see it; `groupable` still refuses one as a defence.
    @Test(arguments: ["own tile", "collapsed target"])
    func excludedCentresNeverGroup(over place: String) async throws {
        let start = ContinuousClock.now
        var (arranger, rb) = try bareDocked(bMinimum: place == "collapsed target" ? Size(width: 1500, height: 100) : nil, zoom: place == "collapsed target")
        let desk = try #require(arranger.world[mainKey])
        let plan = try Planner.plan(desk: desk, area: area, gap: 8, mins: arranger.minimums)
        let leafA = try #require(desk.tree.leaf(containing: a))
        let ra = try #require(plan.resolution.nodeRects[leafA])
        if place == "collapsed target" { try #require(arranger.camera.collapsible.contains(b.identity), "b did not collapse") }
        let point = switch place {
        case "own tile": centre(ra)
        default: centre(rb)
        }
        _ = drag(&arranger, a, from: frameA, to: point, at: start)
        try #require(arranger.drag?.kind == .move, "the drag never started")
        let tick = arranger.handle(.tick, now: start + .milliseconds(400))
        #expect(groupPreviews(tick).isEmpty, "over the \(place) a group preview showed: \(tick)")
        #expect(arranger.drag?.groupDwellEnds == nil, "over the \(place) a group dwell ran")
    }

    @Test func aDropOnAGroupAddsTheWindowAsTheLastSelectedTab() async throws {
        var (harness, plan) = try await docked()
        let ra = try #require(plan.frames[a]), rb = try #require(plan.frames[b])
        await groupFWithB(&harness, rb)
        let leaf = try #require(harness.arranger.world[mainKey]?.tree.leaf(containing: b))
        let now = try Planner.plan(desk: try #require(harness.arranger.world[mainKey]), area: area, gap: 8, mins: [:])
        let group = try #require(now.resolution.nodeRects[leaf])
        let point = centre(TabBand.content(of: group))
        _ = await drag(&harness, a, from: ra, to: point)
        let frame = try groupFrame(harness.arranger, a, on: b)
        harness.now += .milliseconds(400)
        let tick = await harness.send(.tick)
        #expect(previews(tick) == [.group(frame: frame, strip: TabBand.strip(of: frame), label: "Add as a tab")], "tick gave \(tick)")
        let depth = harness.arranger.history.depth(for: mainKey)

        let up = await harness.send(pointer(.up, point.x, point.y))
        #expect(harness.arranger.world[mainKey]?.tree.node(leaf) == .tabs(windows: [b, f, a], selected: 2))
        #expect(up.contains(.tabAnnouncement(.added(tabs: 3))))
        #expect(harness.arranger.history.depth(for: mainKey) == depth + 1, "adding a tab is not one undo step")
        #expect(harness.arranger.isParked(b) && harness.arranger.isParked(f))
    }

    @Test func aGroupWithoutRoomShowsBlockedWithZoomOffAndIsRefused() throws {
        let start = ContinuousClock.now
        let tall = Size(width: 100, height: 840)  // fits a tile, not a content rect (859 − 32)
        var (arranger, rb) = try bareDocked(aMinimum: tall)
        _ = drag(&arranger, a, from: frameA, to: centre(rb), at: start)
        let loose = try groupFrame(arranger, a, on: b)
        let tick = arranger.handle(.tick, now: start + .milliseconds(400))
        #expect(previews(tick).last == .blocked(loose), "tick gave \(tick)")
        let depth = arranger.history.depth(for: mainKey)

        let up = arranger.handle(pointer(.up, rb.midX, rb.midY), now: start + .milliseconds(450))
        #expect(up.contains(.announce("Not enough room to dock here")))
        #expect(!up.contains { if case .tabAnnouncement = $0 { true } else { false } })
        #expect(arranger.history.depth(for: mainKey) == depth)
        let desk = try #require(arranger.world[mainKey])
        #expect(desk.tree.node(try #require(desk.tree.leaf(containing: b))) == .panel(b))
    }

    @Test func aGroupWithoutRoomCollapsesWithZoomOnAndIsAccepted() throws {
        let start = ContinuousClock.now
        let tall = Size(width: 100, height: 840)
        var (arranger, rb) = try bareDocked(aMinimum: tall, zoom: true)
        _ = drag(&arranger, a, from: frameA, to: centre(rb), at: start)
        let loose = try groupFrame(arranger, a, on: b)
        let tick = arranger.handle(.tick, now: start + .milliseconds(400))
        #expect(previews(tick).last == .collapsed(loose, label: CollapseCopy.draggedLabel), "tick gave \(tick)")
        let depth = arranger.history.depth(for: mainKey)

        let up = arranger.handle(pointer(.up, rb.midX, rb.midY), now: start + .milliseconds(450))
        #expect(up.contains(.announce("Docked. Zoom in to see it.")))
        #expect(!up.contains { if case .tabAnnouncement = $0 { true } else { false } }, "two announcements for one drop")
        #expect(arranger.history.depth(for: mainKey) == depth + 1)
        let desk = try #require(arranger.world[mainKey])
        #expect(desk.tree.node(try #require(desk.tree.leaf(containing: b))) == .tabs(windows: [b, a], selected: 1))
    }

    @Test func selectingATabLaterIsNoUndoStep() async throws {
        var (harness, plan) = try await docked()
        let rb = try #require(plan.frames[b])
        await groupFWithB(&harness, rb)
        let depth = harness.arranger.history.depth(for: mainKey)
        try harness.arranger.world.reflow(mainKey) { desk, _ throws(LayoutError) in try desk.tree.selectTab(b) }
        #expect(harness.arranger.history.depth(for: mainKey) == depth)
        #expect(try harness.arranger.world.undo(mainKey, history: &harness.arranger.history) != nil)
        let desk = try #require(harness.arranger.world[mainKey])
        #expect(desk.tree.node(try #require(desk.tree.leaf(containing: b))) == .panel(b), "one undo did not take the group apart")
    }
}

/// a and b docked by the keyboard, then f grouped into b's leaf ([b, f], f selected) on an Arranger with no window
/// system, and planned: f in the content rect, b parked. Returns it with the group's key, frame and content rect.
/// `withA` groups a too ([b, f, a], a selected); `zoom` turns zoom on first.
private func bareGroup(
    at now: ContinuousClock.Instant, withA: Bool = false, zoom: Bool = false, displays: [DisplayInfo] = [mainDisplay],
    floating: [WindowInfo] = []
) throws -> (Arranger, GroupKey, frame: Rect, content: Rect) {
    var arranger = Arranger()
    let infos = [info(1, frame: frameA), info(2, frame: smallF), info(3, frame: frameB)] + floating
    _ = arranger.handle(.inventory(WindowInventory(displays: displays, windows: infos, initialRefreshComplete: true)), now: now)
    if zoom { _ = arranger.handle(.zoomEnabled(true), now: now) }
    _ = arranger.handle(.command(.dock, focused: a), now: now)
    _ = arranger.handle(.command(.dock, focused: b), now: now)
    let leaf = try #require(arranger.world[mainKey]?.tree.leaf(containing: b))
    try arranger.world.edit(mainKey, history: &arranger.history) { desk, _ throws(LayoutError) in
        try desk.desktop.remove(f)
        try desk.tree.group(f, into: leaf)
        if withA {
            try desk.tree.remove(a)
            try desk.tree.group(a, into: leaf)
        }
    }
    _ = arranger.handle(.gap(8), now: now)  // re-plans
    #expect(arranger.isParked(b), "b was not parked")
    let plan = try Planner.plan(desk: try #require(arranger.world[mainKey]), area: area, gap: 8, mins: [:])
    let frame = try #require(plan.resolution.nodeRects[leaf])
    return (arranger, GroupKey(desk: mainKey, node: leaf), frame, TabBand.content(of: frame))
}

private func commands(_ effects: [ArrangerEffect]) -> [WindowCommand] {
    effects.flatMap { effect -> [WindowCommand] in if case .perform(let commands) = effect { commands } else { [] } }
}

private func strips(_ effects: [ArrangerEffect]) -> [[TabStrip]] {
    effects.compactMap { if case .tabStrips(let strips, "main") = $0 { strips } else { nil } }
}

private func selected(_ arranger: Arranger, _ group: GroupKey) -> WindowRef? {
    guard case .tabs(let members, let index)? = arranger.world[mainKey]?.tree.node(group.node) else { return nil }
    return members[index]
}

/// TABS-02, D-04, D-05, D-08: the strip and the reveal-then-park tab switch.
@Suite struct ArrangerTabSelectTests {
    @Test func selectingAHiddenTabWritesAndFocusesItWithoutParkingThePrevious() throws {
        let start = ContinuousClock.now
        var (arranger, group, _, content) = try bareGroup(at: start)
        let effects = arranger.handle(.tab(.select(b, via: .click), ready: true), now: start)
        let sent = commands(effects)
        let write = try #require(sent.firstIndex(of: .setFrame(b, content)), "b was not written into the content rect: \(sent)")
        let focus = try #require(sent.firstIndex(of: .focus(b)), "b was not focused: \(sent)")
        #expect(write < focus, "the focus came before the write")
        #expect(parks(effects).isEmpty, "a member parked before the read-back: \(parks(effects))")
        #expect(effects.contains(.tabAnnouncement(.selected(index: 1, count: 2))))
        #expect(effects.contains(.raiseStrip(group)))
        #expect(effects.contains(.wake(at: start + .seconds(1))), "no wake at the reveal deadline")
        #expect(selected(arranger, group) == b)
    }

    @Test func aReadBackWithin2ptParksThePreviousAtTheContentSize() throws {
        let start = ContinuousClock.now
        var (arranger, _, _, content) = try bareGroup(at: start)
        _ = arranger.handle(.tab(.select(b, via: .click), ready: true), now: start)
        let off = Rect(x: content.x + 3, y: content.y, width: content.width, height: content.height)
        #expect(parks(arranger.handle(.event(.frameApplied(b, requested: content, actual: off)), now: start)).isEmpty, "a read-back 3 pt off parked f")
        let near = Rect(x: content.x + 1.5, y: content.y, width: content.width, height: content.height)
        let back = arranger.handle(.event(.frameApplied(b, requested: content, actual: near)), now: start + .milliseconds(40))
        #expect(parks(back) == [.park(f, displayUUID: "main", size: Size(width: content.width, height: content.height))])
        #expect(arranger.isParked(f))
    }

    @Test func noReadBackWithin1sRevertsAndKeepsThePrevious() throws {
        let start = ContinuousClock.now
        var (arranger, group, _, content) = try bareGroup(at: start)
        _ = arranger.handle(.tab(.select(b, via: .click), ready: true), now: start)
        #expect(!arranger.handle(.tick, now: start + .milliseconds(999)).contains(.beep))
        let late = arranger.handle(.tick, now: start + .seconds(1))
        #expect(late.contains(.beep))
        #expect(late.contains(.tabAnnouncement(.couldNotShow(b))))
        #expect(selected(arranger, group) == f, "the selection did not revert")
        #expect(!parks(late).contains { if case .park(f, _, _) = $0 { true } else { false } }, "the previous member parked")
        #expect(parks(late).contains(.park(b, displayUUID: "main", size: Size(width: content.width, height: content.height))))
        #expect(!arranger.isParked(f))
    }

    @Test func clickingTheSelectedTabOnlyFocusesIt() throws {
        let start = ContinuousClock.now
        var (arranger, _, _, _) = try bareGroup(at: start)
        #expect(arranger.handle(.tab(.select(f, via: .click), ready: true), now: start) == [.perform([.focus(f)])])
    }

    @Test func aStripIsSentOnceAndAgainOnlyWhenATitleChanges() throws {
        let start = ContinuousClock.now
        var arranger = try bareGroup(at: start).0
        let leaf = try #require(arranger.world[mainKey]?.tree.leaf(containing: b))
        let desk = try #require(arranger.world[mainKey])
        let frame = try #require(try Planner.plan(desk: desk, area: area, gap: 8, mins: [:]).resolution.nodeRects[leaf])
        let expected = TabStrip(
            group: GroupKey(desk: mainKey, node: leaf), frame: TabBand.strip(of: frame), members: [b, f], titles: ["", ""], selected: 1, floating: false)
        #expect(arranger.tabs.shownStrips["main"] == [expected])
        #expect(strips(arranger.handle(.gap(8), now: start)).isEmpty, "an unchanged replan sent the strip again")
        var renamed = info(2, frame: smallF)
        renamed.window.titleHint = "Notes"
        let changed = strips(arranger.handle(.event(.windowChanged(renamed)), now: start))
        #expect(changed.count == 1 && changed.first?.first?.titles == ["", "Notes"], "a title change gave \(changed)")
    }

    @Test func groupingSendsTheStripAndUngroupingHidesIt() async throws {
        var (harness, plan) = try await docked()
        let rb = try #require(plan.frames[b])
        _ = await drag(&harness, f, from: smallF, to: centre(rb))
        harness.now += .milliseconds(400)
        await harness.send(.tick)
        let up = await harness.send(pointer(.up, rb.midX, rb.midY))
        #expect(strips(up).count == 1 && strips(up).first?.count == 1, "no strip with the group: \(strips(up))")
        let undo = await harness.send(.command(.undo, focused: f))
        #expect(strips(undo) == [[]], "undo did not hide the strip")
    }

    @Test func aTabSwitchOnTheFakeEndsWithTheNewMemberShownAndTheOldParked() async throws {
        var (harness, plan) = try await docked()
        let rb = try #require(plan.frames[b])
        await groupFWithB(&harness, rb)
        let leaf = try #require(harness.arranger.world[mainKey]?.tree.leaf(containing: b))
        let desk = try #require(harness.arranger.world[mainKey])
        let frame = try #require(try Planner.plan(desk: desk, area: area, gap: 8, mins: [:]).resolution.nodeRects[leaf])
        let content = TabBand.content(of: frame)
        await harness.send(.tab(.select(b, via: .click), ready: true))
        #expect(await harness.frame(b) == content)
        let parked = try #require(await harness.frame(f))
        #expect(parked.width == content.width && parked.height == content.height && harness.arranger.isParked(f))
        #expect(harness.arranger.tabs.pendingReveal == nil)
    }

    @Test(arguments: [true, false])
    func aRefusedSelectBeepsAndChangesNothing(paused: Bool) throws {
        let start = ContinuousClock.now
        var (arranger, group, _, _) = try bareGroup(at: start)
        if paused { _ = arranger.handle(.setPaused(.user, true), now: start) }
        let effects = arranger.handle(.tab(.select(b, via: .click), ready: paused), now: start)
        #expect(effects.contains(.beep))
        #expect(effects.contains(.tabAnnouncement(.refused(paused ? .paused : .notReady))))
        #expect(commands(effects).isEmpty)
        #expect(selected(arranger, group) == f)
    }
}

/// D-08 with RESEARCH Open Question 2: a hidden member focused another way becomes the selected tab, with a 1 s
/// per-group suppression against focus fights (Pitfall 6).
@Suite struct ArrangerTabActivationTests {
    @Test func aFocusedHiddenMemberIsSelectedWithoutAnAnnouncement() throws {
        let start = ContinuousClock.now
        var (arranger, group, _, content) = try bareGroup(at: start)
        let effects = arranger.handle(.event(.windowFocused(b)), now: start)
        #expect(selected(arranger, group) == b)
        #expect(commands(effects).contains(.setFrame(b, content)) && commands(effects).contains(.focus(b)), "no reveal: \(effects)")
        #expect(parks(effects).isEmpty, "the previous member parked before the read-back")
        #expect(!effects.contains { if case .tabAnnouncement = $0 { true } else { false } }, "an activation was announced")
        let back = arranger.handle(.event(.frameApplied(b, requested: content, actual: content)), now: start + .milliseconds(30))
        #expect(parks(back).contains { if case .park(f, _, _) = $0 { true } else { false } })
    }

    @Test func aFocusOfTheRevealedWindowIsAnEchoAndSelectsNothing() throws {
        let start = ContinuousClock.now
        var (arranger, group, _, _) = try bareGroup(at: start)
        _ = arranger.handle(.tab(.select(b, via: .click), ready: true), now: start)
        let echo = arranger.handle(.event(.windowFocused(b)), now: start + .seconds(2))
        #expect(commands(echo).isEmpty && !echo.contains { if case .tabAnnouncement = $0 { true } else { false } }, "the echo selected again: \(echo)")
        #expect(selected(arranger, group) == b)
        #expect(arranger.tabs.pendingReveal?.revealed == b, "the echo ended the reveal")
    }

    @Test func aFocusWithin1sOfASelectionChangeDoesNotSwitchTabs() throws {
        let start = ContinuousClock.now
        var (arranger, group, _, content) = try bareGroup(at: start)
        _ = arranger.handle(.tab(.select(b, via: .click), ready: true), now: start)
        _ = arranger.handle(.event(.frameApplied(b, requested: content, actual: content)), now: start + .milliseconds(30))
        _ = arranger.handle(.event(.windowFocused(f)), now: start + .milliseconds(500))
        #expect(selected(arranger, group) == b, "a focus 0.5 s after the selection switched tabs")
        _ = arranger.handle(.event(.windowFocused(f)), now: start + .milliseconds(1100))
        #expect(selected(arranger, group) == f, "a focus 1.1 s after the selection did not switch tabs")
    }

    /// WR-02: ⌘M on the selected member (not Minimize Group) keeps the group on screen with a present neighbour.
    @Test func theSelectedMemberGoingAbsentSelectsAPresentNeighbourAndItsReturnKeepsIt() throws {
        let start = ContinuousClock.now
        var (arranger, group, frame, content) = try bareGroup(at: start, withA: true)  // [b, f, a], a selected
        let absent = arranger.handle(.event(.windowStateChanged(a, .absent)), now: start)
        #expect(selected(arranger, group) == f, "the left neighbour of the last tab was not selected")
        #expect(setFrames(absent)[f] == content, "the neighbour was not written into the content rect: \(absent)")
        #expect(strips(absent).last?.first?.frame == TabBand.strip(of: frame), "the group lost its strip: \(absent)")
        #expect(arranger.tabs.suppressedUntil[group] == nil, "a focus of a member would be ignored")
        let focus = arranger.handle(.event(.windowFocused(b)), now: start + .milliseconds(300))
        #expect(selected(arranger, group) == b && commands(focus).contains(.setFrame(b, content)), "macOS's focus did not show b: \(focus)")
        _ = arranger.handle(.event(.frameApplied(b, requested: content, actual: content)), now: start + .milliseconds(330))
        let back = arranger.handle(.event(.windowStateChanged(a, .present)), now: start + .seconds(5))
        #expect(selected(arranger, group) == b, "the returning member took the selection back")
        #expect(parks(back).contains { if case .park(a, _, _) = $0 { true } else { false } }, "the returning member was not parked: \(back)")
    }

    @Test func theSelectedMemberGoingAbsentPicksTheRightNeighbourFirst() throws {
        let start = ContinuousClock.now
        var (arranger, group, _, _) = try bareGroup(at: start, withA: true)  // [b, f, a]
        try arranger.world.reflow(mainKey) { desk, _ throws(LayoutError) in try desk.tree.selectTab(b) }
        _ = arranger.handle(.event(.windowStateChanged(b, .absent)), now: start)
        #expect(selected(arranger, group) == f)
    }

    @Test func aFocusWithin1sOfAMemberClosingDoesNotSwitchTabs() throws {
        let start = ContinuousClock.now
        var (arranger, group, _, _) = try bareGroup(at: start, withA: true)
        try #require(selected(arranger, group) == a)
        _ = arranger.handle(.event(.windowDestroyed(a)), now: start)
        let after = try #require(selected(arranger, group))
        let other = after == b ? f : b
        _ = arranger.handle(.event(.windowFocused(other)), now: start + .milliseconds(500))
        #expect(selected(arranger, group) == after, "a focus after a close switched tabs")
        _ = arranger.handle(.event(.windowFocused(other)), now: start + .milliseconds(1500))
        #expect(selected(arranger, group) == other)
    }

    @Test func focusingTheSelectedMemberRaisesItsStripAndAReplanNever() throws {
        let start = ContinuousClock.now
        var (arranger, group, _, _) = try bareGroup(at: start)
        let focused = arranger.handle(.event(.windowFocused(f)), now: start)
        #expect(focused.filter { $0 == .raiseStrip(group) }.count == 1, "no single raise on focus: \(focused)")
        #expect(commands(focused).isEmpty, "focusing the selected member wrote a window: \(focused)")
        #expect(!arranger.handle(.gap(8), now: start).contains(.raiseStrip(group)), "an unchanged replan raised the strip")
        #expect(!arranger.handle(.event(.windowFocused(a)), now: start).contains { if case .raiseStrip = $0 { true } else { false } },
            "a window outside the group raised a strip")
    }

    @Test func anActivationRaisesTheStripOnce() throws {
        let start = ContinuousClock.now
        var (arranger, group, _, _) = try bareGroup(at: start)
        let effects = arranger.handle(.event(.windowFocused(b)), now: start)
        #expect(effects.filter { $0 == .raiseStrip(group) }.count == 1, "an activation raised \(effects)")
    }

    @Test func theCameraWidenRunsAfterTheSelectionOnTheGroupsLeaf() throws {
        let start = ContinuousClock.now
        var (arranger, group, _, _) = try bareGroup(at: start, zoom: true)
        let leafA = try #require(arranger.world[mainKey]?.tree.leaf(containing: a))
        let move = arranger.handle(.zoomTo(.node(leafA), displayUUID: "main"), now: start)
        let id = try #require(move.compactMap { if case .cameraMove(let m) = $0 { m.id } else { nil } }.first, "no zoom move: \(move)")
        _ = arranger.handle(.cameraSettle(displayUUID: "main", moveID: id), now: start)
        let effects = arranger.handle(.event(.windowFocused(b)), now: start)
        #expect(selected(arranger, group) == b, "the focused hidden member was not selected")
        let widen = effects.compactMap { if case .cameraMove(let m) = $0 { m } else { nil } }
        #expect(widen.count == 1, "no widen: \(effects)")
        #expect(widen.first?.to != .node(leafA), "the widen stayed on a's leaf")
    }
}

// MARK: Floating groups (07-04)

private let t = window(5), g = window(4)
private let tFrame = Rect(x: 400, y: 200, width: 500, height: 400)
private let gFrame = Rect(x: 950, y: 120, width: 300, height: 200)

/// a, f, g and t floating on the main desk, nothing docked.
private func floaters() async -> Harness {
    await Harness.started(frames: [1: frameA, 2: smallF, 4: gFrame, 5: tFrame])
}

/// f dragged onto t's centre, held 400 ms and released: the floating group [t, f] at t's frame.
private func groupFOntoT(_ harness: inout Harness) async -> [ArrangerEffect] {
    _ = await drag(&harness, f, from: smallF, to: centre(tFrame))
    harness.now += .milliseconds(400)
    await harness.send(.tick)
    return await harness.send(pointer(.up, tFrame.midX, tFrame.midY))
}

/// The plan of the main desk as it is now.
private func docked(_ harness: Harness) throws -> FramePlan {
    try Planner.plan(desk: try #require(harness.arranger.world[mainKey]), area: area, gap: 8, mins: [:])
}

private func floatingGroups(_ harness: Harness) -> [FloatingTabGroup] {
    harness.arranger.world[mainKey]?.desktop.groups ?? []
}

/// D-02, D-03, TABS-05: a centre drop on a floating window makes a floating group at that window's frame.
@Suite struct ArrangerFloatingTabsTests {
    @Test func aFloatingCentreHeld400msPreviewsTheGroupAtTheTargetsFrame() async throws {
        var harness = await floaters()
        _ = await drag(&harness, f, from: smallF, to: centre(tFrame))
        harness.now += .milliseconds(399)
        #expect(groupPreviews(await harness.send(.tick)).isEmpty, "the group preview came before 400 ms")
        harness.now += .milliseconds(1)
        let tick = await harness.send(.tick)
        #expect(previews(tick) == [.group(frame: tFrame, strip: TabBand.strip(of: tFrame), label: "Group as tabs")], "tick gave \(tick)")
    }

    @Test func releaseFormsAFloatingGroupWithOneWriteAndOneSizedPark() async throws {
        var harness = await floaters()
        let depth = harness.arranger.history.depth(for: mainKey)
        let up = await groupFOntoT(&harness)
        let content = TabBand.content(of: tFrame)
        let group = try #require(floatingGroups(harness).first)
        #expect(group.members == [t, f] && group.selected == 1 && group.frame == tFrame)
        #expect(harness.arranger.history.depth(for: mainKey) == depth + 1, "grouping is not one undo step")
        #expect(up.contains(.tabAnnouncement(.grouped(tabs: 2))))
        #expect(setFrames(up).filter { $0.key == f || $0.key == t } == [f: content], "group writes: \(setFrames(up))")
        #expect(parks(up) == [.park(t, displayUUID: "main", size: Size(width: content.width, height: content.height))])
        #expect(await harness.frame(f) == content)
        #expect(harness.arranger.isParked(t))
        let strip = try #require(strips(up).last?.first, "no strip: \(up)")
        #expect(strip.floating && strip.frame == TabBand.strip(of: tFrame) && strip.members == [t, f] && strip.selected == 1)
        #expect(strip.group == GroupKey(desk: mainKey, node: group.id))
        #expect(harness.arranger.isHiddenTab(t) && !harness.arranger.isHiddenTab(f))
    }

    @Test func aFloatingGroupsCentreAddsTheDraggedWindowAsTheLastSelectedTab() async throws {
        var harness = await floaters()
        _ = await groupFOntoT(&harness)
        let content = TabBand.content(of: tFrame)
        _ = await drag(&harness, g, from: gFrame, to: centre(content))
        harness.now += .milliseconds(400)
        let tick = await harness.send(.tick)
        #expect(previews(tick) == [.group(frame: tFrame, strip: TabBand.strip(of: tFrame), label: "Add as a tab")], "tick gave \(tick)")
        let up = await harness.send(pointer(.up, content.midX, content.midY))
        let group = try #require(floatingGroups(harness).first)
        #expect(group.members == [t, f, g] && group.selected == 2)
        #expect(up.contains(.tabAnnouncement(.added(tabs: 3))))
        #expect(setFrames(up).filter { [t, f, g].contains($0.key) } == [g: content])
        #expect(parks(up) == [.park(f, displayUUID: "main", size: Size(width: content.width, height: content.height))])
    }

    /// UI-SPEC discretion 3: a docked tile's centre with no floater over it still groups with the tile.
    @Test func aDockedTilesCentreUnderNoFloaterStillGroupsWithTheTile() async throws {
        var harness = await floaters()
        await harness.send(.command(.dock, focused: a))
        await harness.fake.userMove(5, to: Rect(x: 1000, y: 650, width: 300, height: 200))
        _ = await harness.refresh()
        let ra = try #require(try docked(harness).frames[a])
        let point = Point(x: ra.minX + 0.3 * ra.width, y: ra.midY)  // a's centre zone, clear of every floater
        _ = await drag(&harness, f, from: smallF, to: point)
        harness.now += .milliseconds(400)
        #expect(groupPreviews(await harness.send(.tick)).count == 1)
        await harness.send(pointer(.up, point.x, point.y))
        let desk = try #require(harness.arranger.world[mainKey])
        #expect(desk.tree.leaf(containing: a).flatMap(desk.tree.node) == .tabs(windows: [a, f], selected: 1))
        #expect(floatingGroups(harness).isEmpty)
    }

    /// UI-SPEC discretion 3, RESEARCH A1: a floater's centre in front of a docked tile wins the group dwell over the
    /// tile's own centre beneath.
    @Test func aFrontFloatersCentreGroupsAheadOfTheDockedTileBeneath() async throws {
        var harness = await floaters()
        await harness.send(.command(.dock, focused: a))
        let ra = try #require(try docked(harness).frames[a])
        await harness.fake.userMove(5, to: Rect(x: ra.midX - 150, y: ra.midY - 100, width: 300, height: 200))
        _ = await harness.refresh()
        let target = try #require(harness.arranger.world[mainKey]?.desktop.frame(of: t))
        _ = await drag(&harness, f, from: smallF, to: centre(target))
        harness.now += .milliseconds(400)
        let tick = await harness.send(.tick)
        #expect(previews(tick) == [.group(frame: target, strip: TabBand.strip(of: target), label: "Group as tabs")], "tick gave \(tick)")
        await harness.send(pointer(.up, target.midX, target.midY))
        let group = try #require(floatingGroups(harness).first, "f did not group with t")
        #expect(group.members == [t, f])
        let desk = try #require(harness.arranger.world[mainKey])
        #expect(desk.tree.leaf(containing: a).flatMap(desk.tree.node) == .panel(a), "f grouped with the tile beneath")
    }

    /// WR-03, D-05: a docked window focused after the floater is in front of it, so its tile takes the group, not the
    /// floater the user can't see.
    @Test func aFloaterBehindAFocusedDockedWindowDoesNotGroup() async throws {
        var harness = await floaters()
        await harness.send(.command(.dock, focused: a))
        let ra = try #require(try docked(harness).frames[a])
        await harness.fake.userMove(5, to: Rect(x: ra.midX - 150, y: ra.midY - 100, width: 300, height: 200))
        _ = await harness.refresh()
        await harness.send(.event(.windowFocused(t)))
        await harness.send(.event(.windowFocused(a)))
        let target = try #require(harness.arranger.world[mainKey]?.desktop.frame(of: t))
        _ = await drag(&harness, f, from: smallF, to: centre(target))
        harness.now += .milliseconds(400)
        await harness.send(.tick)
        await harness.send(pointer(.up, target.midX, target.midY))
        #expect(floatingGroups(harness).isEmpty, "f grouped with t, behind a")
        let desk = try #require(harness.arranger.world[mainKey])
        #expect(desk.tree.leaf(containing: a).flatMap(desk.tree.node) == .tabs(windows: [a, f], selected: 1))
    }

    /// 8.1.1 D-18 (UAT 7a): the window server's stacking from the press decides, not focus. The docked window was focused
    /// last and the floater in front of it never was, yet the floater takes the group dwell, in Hold ⌥ (⌥ held) and
    /// Automatically.
    @Test(arguments: [(DragToDockMode.automatic, Modifiers()), (DragToDockMode.holdOption, Modifiers.option)])
    func aFrontFloaterWinsTheDwellOverADockedWindowFocusedLater(mode: DragToDockMode, modifiers: Modifiers) async throws {
        var harness = await floaters()
        await harness.send(.dragToDock(mode))
        await harness.send(.command(.dock, focused: a))
        let ra = try #require(try docked(harness).frames[a])
        await harness.fake.userMove(5, to: Rect(x: ra.midX - 150, y: ra.midY - 100, width: 300, height: 200))
        _ = await harness.refresh()
        await harness.send(.event(.windowFocused(a)))
        let target = try #require(harness.arranger.world[mainKey]?.desktop.frame(of: t))
        _ = await drag(&harness, f, from: smallF, to: centre(target), modifiers, stacking: [f, t, a])
        harness.now += .milliseconds(400)
        let tick = await harness.send(.tick)
        #expect(previews(tick) == [.group(frame: target, strip: TabBand.strip(of: target), label: "Group as tabs")], "tick gave \(tick)")
        await harness.send(pointer(.up, target.midX, target.midY, modifiers))
        let group = try #require(floatingGroups(harness).first, "f did not group with t, in front of a")
        #expect(group.members == [t, f])
        let desk = try #require(harness.arranger.world[mainKey])
        #expect(desk.tree.leaf(containing: a).flatMap(desk.tree.node) == .panel(a), "a's tile changed")
    }

    /// WR-02 (iteration 2): the dragged docked window's own tile is not in front of anything, so a floater over that
    /// tile still takes the group although the dragged window was focused last.
    @Test func aDockedWindowDraggedOntoAFloaterOverItsOwnTileGroups() async throws {
        var harness = await floaters()
        await harness.send(.command(.dock, focused: a))
        let ra = try #require(try docked(harness).frames[a])
        await harness.fake.userMove(5, to: Rect(x: ra.midX - 150, y: ra.midY - 100, width: 300, height: 200))
        _ = await harness.refresh()
        await harness.send(.event(.windowFocused(t)))
        await harness.send(.event(.windowFocused(a)))
        let target = try #require(harness.arranger.world[mainKey]?.desktop.frame(of: t))
        _ = await drag(&harness, a, from: ra, to: centre(target))
        harness.now += .milliseconds(400)
        await harness.send(.tick)
        await harness.send(pointer(.up, target.midX, target.midY))
        let group = try #require(floatingGroups(harness).first, "a did not group with t")
        #expect(group.members == [t, a])
    }

    /// UI-SPEC discretion 3: the rest of a front floater's area gives the docked tile's regions beneath.
    @Test func aFrontFloatersEdgeGivesTheDockedTilesEdgeRegionBeneath() async throws {
        var harness = await floaters()
        await harness.send(.command(.dock, focused: a))
        let ra = try #require(try docked(harness).frames[a])
        await harness.fake.userMove(5, to: Rect(x: ra.minX + 20, y: ra.midY - 100, width: 400, height: 200))
        _ = await harness.refresh()
        let point = Point(x: ra.minX + 40, y: ra.midY)  // t's left edge band and a's left edge region
        _ = await drag(&harness, f, from: smallF, to: point)
        harness.now += DragSession.dwell
        let tick = await harness.send(.tick)
        #expect(previews(tick).contains { if case .dock = $0 { true } else { false } }, "tick gave \(tick)")
        await harness.send(pointer(.up, point.x, point.y))
        #expect(harness.arranger.world[mainKey]?.tree.windows == [f, a])
        #expect(floatingGroups(harness).isEmpty)
    }

    /// UI-SPEC Surface 5: the selected member of a group drags the whole group, and groups never merge.
    @Test func aWholeGroupOverAFloatersCentreNeverGroups() async throws {
        var harness = await floaters()
        _ = await groupFOntoT(&harness)
        let content = TabBand.content(of: tFrame)
        _ = await drag(&harness, f, from: content, to: centre(gFrame))
        harness.now += .milliseconds(400)
        #expect(groupPreviews(await harness.send(.tick)).isEmpty)
        await harness.send(pointer(.up, gFrame.midX, gFrame.midY))
        #expect(harness.arranger.tabGroup(holding: f)?.members == [t, f])
        #expect(harness.arranger.tabGroup(holding: g) == nil, "the groups merged")
    }

    @Test func aFloatersEdgeBandFormsNothing() async throws {
        var harness = await floaters()
        let edge = Point(x: tFrame.minX + 20, y: tFrame.midY)
        _ = await drag(&harness, f, from: smallF, to: edge)
        harness.now += .milliseconds(400)
        #expect(groupPreviews(await harness.send(.tick)).isEmpty)
        await harness.send(pointer(.up, edge.x, edge.y))
        #expect(floatingGroups(harness).isEmpty)
    }

    @Test func undoAfterAFloatingGroupRestoresBothFloaters() async throws {
        var harness = await floaters()
        _ = await groupFOntoT(&harness)
        await harness.send(.command(.undo, focused: f))
        #expect(floatingGroups(harness).isEmpty)
        #expect(await harness.frame(t) == tFrame)
        #expect(await harness.frame(f) == smallF)
        #expect(!harness.arranger.isParked(t))
        #expect(harness.arranger.world[mainKey]?.desktop.frame(of: t) == tFrame)
    }

    @Test func aDockedWindowDroppedOnAFloaterGroupsOnTheDesktop() async throws {
        var harness = await floaters()
        await harness.send(.command(.dock, focused: a))
        let plan = try Planner.plan(desk: try #require(harness.arranger.world[mainKey]), area: area, gap: 8, mins: [:])
        let ra = try #require(plan.frames[a])
        // t is in front of a's own tile: the floater's centre wins (UI-SPEC discretion 3).
        let target = try #require(harness.arranger.world[mainKey]?.desktop.frame(of: t))
        _ = await drag(&harness, a, from: ra, to: centre(target))
        harness.now += .milliseconds(400)
        await harness.send(.tick)
        await harness.send(pointer(.up, target.midX, target.midY))
        let group = try #require(floatingGroups(harness).first)
        #expect(group.members == [t, a])
        #expect(harness.arranger.world[mainKey]?.tree.state(of: a) == nil, "a is still docked")
    }
}

/// The Planner side of floating groups: the selected member never planned (D-05), hidden members parked once at the content size.
@Suite struct FloatingGroupPlannerTests {
    private func groupedDesk() throws -> Desk {
        var desk = Desk()
        var ids = IDSource()
        try desk.tree.applyDrop(.layoutEdge(.right), window: a, ids: &ids)
        try desk.desktop.add(t, frame: tFrame)
        try desk.desktop.group(id: try ids.make(), target: t, adding: f)
        return desk
    }

    @Test func hiddenMembersParkAtTheContentSize() throws {
        let plan = try Planner.plan(desk: try groupedDesk(), area: area, gap: 8, mins: [:])
        let content = TabBand.content(of: tFrame)
        #expect(plan.parks == [t])
        #expect(plan.parkSizes[t] == Size(width: content.width, height: content.height))
        #expect(plan.frames[t] == nil)
    }

    /// D-05: a floating group over a docked tile stays where it is, strip and all.
    @Test func aFloatingGroupOverATileIsNeverMoved() throws {
        let plan = try Planner.plan(desk: try groupedDesk(), area: area, gap: 8, mins: [:])
        let tile = try #require(plan.frames[a])
        try #require(tFrame.overlaps(tile), "the group is clear of a's tile")
        #expect(plan.frames[f] == nil && plan.frames[t] == nil)
    }
}

/// A window of another app (TABS-05).
private func otherApp(_ id: UInt32, frame: Rect) -> WindowInfo {
    WindowInfo(
        window: WindowRef(identity: WindowIdentity(windowID: id, pid: 901, bundleID: "com.example.other")), frame: frame, state: .present,
        displayUUID: "main", kind: .dockable, isExcluded: false, learnedMinimum: nil)
}

/// f and t floating, then grouped as [t, f] (f selected) at t's frame on an Arranger with no window system, planned
/// (f written into the content rect and read back there, t parked). Returns it with the group's key and content rect.
private func bareFloatingGroup(at now: ContinuousClock.Instant, fMinimum: Size? = nil) throws -> (Arranger, GroupKey, content: Rect) {
    var arranger = Arranger()
    let infos = [info(2, frame: smallF, minimum: fMinimum), info(5, frame: tFrame)]
    _ = arranger.handle(.inventory(WindowInventory(displays: [mainDisplay], windows: infos, initialRefreshComplete: true)), now: now)
    var id = NodeID(raw: 0)
    try arranger.world.edit(mainKey, history: &arranger.history) { desk, ids throws(LayoutError) in
        id = try ids.make()
        try desk.desktop.remove(f)
        try desk.desktop.group(id: id, target: t, adding: f)
    }
    arranger.wantedFrames[f.identity] = nil  // as the drop commit leaves it
    let content = TabBand.content(of: tFrame)
    let planned = arranger.handle(.gap(8), now: now)
    #expect(commands(planned).contains(.setFrame(f, content)), "f was not written into the content rect: \(planned)")
    #expect(arranger.isParked(t), "t was not parked")
    _ = arranger.handle(.event(.windowMoved(f, content)), now: now)  // f's echo
    return (arranger, GroupKey(desk: mainKey, node: id), content)
}

private func floatingSelected(_ arranger: Arranger, _ group: GroupKey) -> WindowRef? {
    arranger.world[mainKey]?.desktop.groups.first { $0.id == group.node }.map { $0.members[$0.selected] }
}

/// TABS-05, D-08, Pitfall 5: a floating group moves by its selected window and switches tabs like a docked one.
@Suite struct ArrangerFloatingGroupBehaviourTests {
    @Test func movingTheSelectedMemberMovesTheWholeGroup() throws {
        let start = ContinuousClock.now
        var (arranger, group, _) = try bareFloatingGroup(at: start)
        let moved = Rect(x: 200, y: 300, width: 450, height: 350)
        let effects = arranger.handle(.event(.windowMoved(f, moved)), now: start + .seconds(2))
        let layer = try #require(arranger.world[mainKey]?.desktop)
        #expect(layer.groups.first?.frame == TabBand.frame(ofContent: moved))
        #expect(layer.frame(of: f) == moved && layer.frame(of: t) == moved, "the members did not follow")
        #expect(arranger.wantedFrames[f.identity] == moved)
        #expect(setFrames(effects)[t] == nil, "the hidden member was written")
        let strip = try #require(strips(effects).last?.first, "the strip did not follow: \(effects)")
        #expect(strip.group == group && strip.frame == TabBand.strip(of: TabBand.frame(ofContent: moved)))
    }

    @Test func aHiddenMembersFrameReportsChangeNothing() throws {
        let start = ContinuousClock.now
        var (arranger, _, content) = try bareFloatingGroup(at: start)
        let before = arranger.world
        let stray = Rect(x: 20, y: 40, width: 300, height: 200)
        #expect(arranger.handle(.event(.windowMoved(t, stray)), now: start).isEmpty)
        #expect(arranger.handle(.event(.windowResized(t, stray)), now: start).isEmpty)
        #expect(arranger.world == before)
        // A previous member still covering the content rect during a reveal is not parked yet: its late report is ignored too.
        _ = arranger.handle(.tab(.select(t, via: .click), ready: true), now: start)
        #expect(!arranger.isParked(f))
        let late = arranger.handle(.event(.windowMoved(f, stray)), now: start + .milliseconds(10))
        #expect(commands(late).isEmpty, "the cover's report was answered: \(late)")
        #expect(arranger.world[mainKey]?.desktop.groups.first?.frame == tFrame, "a hidden member's report moved the group")
        #expect(arranger.world[mainKey]?.desktop.frame(of: t) == content)
    }

    @Test func selectingAHiddenTabRevealsThenParksThePrevious() throws {
        let start = ContinuousClock.now
        var (arranger, group, content) = try bareFloatingGroup(at: start)
        let depth = arranger.history.depth(for: mainKey)
        let effects = arranger.handle(.tab(.select(t, via: .click), ready: true), now: start)
        let sent = commands(effects)
        let write = try #require(sent.firstIndex(of: .setFrame(t, content)), "t was not written into the content rect: \(sent)")
        let focus = try #require(sent.firstIndex(of: .focus(t)), "t was not focused: \(sent)")
        #expect(write < focus)
        #expect(parks(effects).isEmpty, "f parked before the read-back")
        #expect(effects.contains(.raiseStrip(group)) && effects.contains(.tabAnnouncement(.selected(index: 1, count: 2))))
        #expect(floatingSelected(arranger, group) == t)
        #expect(arranger.history.depth(for: mainKey) == depth, "a tab switch made an undo step")
        let back = arranger.handle(.event(.frameApplied(t, requested: content, actual: content)), now: start + .milliseconds(40))
        #expect(parks(back) == [.park(f, displayUUID: "main", size: Size(width: content.width, height: content.height))])
    }

    @Test func aFocusedHiddenMemberIsSelectedWithTheSuppressionRules() throws {
        let start = ContinuousClock.now
        var (arranger, group, content) = try bareFloatingGroup(at: start)
        let effects = arranger.handle(.event(.windowFocused(t)), now: start)
        #expect(floatingSelected(arranger, group) == t)
        #expect(commands(effects).contains(.setFrame(t, content)) && commands(effects).contains(.focus(t)), "no reveal: \(effects)")
        #expect(!effects.contains { if case .tabAnnouncement = $0 { true } else { false } }, "an activation was announced")
        _ = arranger.handle(.event(.frameApplied(t, requested: content, actual: content)), now: start + .milliseconds(30))
        _ = arranger.handle(.event(.windowFocused(f)), now: start + .milliseconds(500))
        #expect(floatingSelected(arranger, group) == t, "a focus 0.5 s after the selection switched tabs")
        _ = arranger.handle(.event(.windowFocused(f)), now: start + .milliseconds(1100))
        #expect(floatingSelected(arranger, group) == f, "a focus 1.1 s after the selection did not switch tabs")
    }

    @Test func aSurvivorOfADissolvedGroupTakesTheWholeFrame() throws {
        let start = ContinuousClock.now
        var (arranger, _, _) = try bareFloatingGroup(at: start)
        let moved = Rect(x: 200, y: 300, width: 450, height: 350)
        _ = arranger.handle(.event(.windowMoved(f, moved)), now: start + .seconds(2))
        _ = arranger.handle(.event(.windowMoved(f, moved)), now: start + .seconds(2))
        let closed = arranger.handle(.event(.windowDestroyed(t)), now: start + .seconds(3))
        #expect(arranger.world[mainKey]?.desktop.groups.isEmpty == true)
        #expect(arranger.world[mainKey]?.desktop.frame(of: f) == TabBand.frame(ofContent: moved))
        #expect(setFrames(closed)[f] == TabBand.frame(ofContent: moved), "the band did not return to the survivor: \(closed)")
        #expect(strips(closed) == [[]], "the dissolved group kept its strip")
    }

    @Test func membersFromDifferentAppsGroupDockedAndFloating() throws {
        let start = ContinuousClock.now
        var arranger = Arranger()
        let x = otherApp(7, frame: Rect(x: 100, y: 500, width: 300, height: 200)), y = otherApp(8, frame: gFrame)
        let infos = [info(1, frame: frameA), info(5, frame: tFrame), x, y]
        _ = arranger.handle(.inventory(WindowInventory(displays: [mainDisplay], windows: infos, initialRefreshComplete: true)), now: start)
        _ = arranger.handle(.command(.dock, focused: a), now: start)
        let leaf = try #require(arranger.world[mainKey]?.tree.leaf(containing: a))
        try arranger.world.edit(mainKey, history: &arranger.history) { desk, ids throws(LayoutError) in
            try desk.desktop.remove(x.window)
            try desk.tree.group(x.window, into: leaf)
            try desk.desktop.remove(y.window)
            try desk.desktop.group(id: try ids.make(), target: t, adding: y.window)
        }
        arranger.wantedFrames[y.window.identity] = nil  // as the drop commit leaves it
        let effects = arranger.handle(.gap(8), now: start)
        let written = Set(setFrames(effects).keys), parked = Set(parks(effects).compactMap { if case .park(let w, _, _) = $0 { w } else { nil } })
        for (shown, hidden) in [(x.window, a), (y.window, t)] {
            #expect(written.contains(shown) && !written.contains(hidden), "\(shown) / \(hidden) writes: \(written)")
            #expect(parked.contains(hidden) && !parked.contains(shown), "\(shown) / \(hidden) parks: \(parked)")
        }
    }
}

/// a docked alone, filling the visible frame, t and f floating over it, both focused (t last), then grouped as [t, f]
/// with f selected.
private func dockedBesideFloatingGroup(at now: ContinuousClock.Instant) throws -> (Arranger, GroupKey) {
    var arranger = Arranger()
    let infos = [info(1, frame: frameA), info(2, frame: smallF), info(5, frame: tFrame)]
    _ = arranger.handle(.inventory(WindowInventory(displays: [mainDisplay], windows: infos, initialRefreshComplete: true)), now: now)
    _ = arranger.handle(.command(.dock, focused: a), now: now)
    _ = arranger.handle(.event(.windowFocused(f)), now: now)
    _ = arranger.handle(.event(.windowFocused(t)), now: now)
    var id = NodeID(raw: 0)
    try arranger.world.edit(mainKey, history: &arranger.history) { desk, ids throws(LayoutError) in
        id = try ids.make()
        try desk.desktop.remove(f)
        try desk.desktop.group(id: id, target: t, adding: f)
    }
    arranger.wantedFrames[f.identity] = nil  // as the drop commit leaves it
    _ = arranger.handle(.gap(8), now: now)
    try #require(arranger.focusOrder.first == t.identity, "t is not the most recently focused")
    return (arranger, GroupKey(desk: mainKey, node: id))
}

/// UI-SPEC Surface 3 "What the user never sees": hidden members stay out of focus moves.
/// 08.1.1 Surface 2: no floating window is a Focus target at all, so a move from the only tile beeps.
@Suite struct FloatingGroupVisibilityTests {
    @Test func aFocusMoveNeverPicksAFloatingGroupMember() throws {
        let start = ContinuousClock.now
        var (arranger, _) = try dockedBesideFloatingGroup(at: start)
        let effects = arranger.handle(.command(.focus(.right), focused: a), now: start)
        #expect(effects == [.beep], "the focus move gave \(effects)")
    }

    @Test func isHiddenTabIsTrueExactlyForNonSelectedMembers() throws {
        let start = ContinuousClock.now
        let (floating, _) = try dockedBesideFloatingGroup(at: start)
        #expect(floating.isHiddenTab(t) && !floating.isHiddenTab(f) && !floating.isHiddenTab(a))
        let (docked, _, _, _) = try bareGroup(at: start)
        #expect(docked.isHiddenTab(b) && !docked.isHiddenTab(f) && !docked.isHiddenTab(a))
        #expect(!docked.isHiddenTab(window(99)), "an unknown window is hidden")
    }
}

// MARK: Close Group and Minimize Group (07-05)

private func closes(_ effects: [ArrangerEffect]) -> [WindowRef] {
    commands(effects).compactMap { if case .close(let window) = $0 { window } else { nil } }
}

/// Runs Close Group on a bare Arranger: every close press is answered by the window's destruction and every reveal by
/// its read-back. Returns the windows in the order they were pressed, each checked to be the shown, read-back member.
private func runCloseGroup(_ arranger: inout Arranger, _ group: GroupKey, content: Rect, at now: ContinuousClock.Instant) -> [WindowRef] {
    var effects = arranger.handle(.tab(.closeGroup(group), ready: true), now: now), pressed: [WindowRef] = []
    for _ in 0..<12 {
        if let close = closes(effects).first {
            #expect(!arranger.isHiddenTab(close) && arranger.tabs.pendingReveal == nil, "\(close) was closed while hidden or not yet shown")
            pressed.append(close)
            effects = arranger.handle(.event(.windowDestroyed(close)), now: now)
        } else if let revealed = arranger.tabs.pendingReveal?.revealed, commands(effects).contains(.setFrame(revealed, content)) {
            effects = arranger.handle(.event(.frameApplied(revealed, requested: content, actual: content)), now: now)
        } else {
            break
        }
    }
    return pressed
}

/// TABS-03, D-06: Close Group closes the members one at a time with the app's own close; it stops at one still open.
@Suite struct ArrangerCloseGroupTests {
    @Test func closeGroupClosesTheSelectedFirstThenStripOrderShowingEachHiddenMemberFirst() throws {
        let start = ContinuousClock.now
        var (arranger, group, _, content) = try bareGroup(at: start, withA: true)  // [b, f, a], a selected
        #expect(runCloseGroup(&arranger, group, content: content, at: start) == [a, b, f])
        #expect(arranger.tabs.closeQueue == nil)
        #expect(arranger.world[mainKey]?.tree.windows.isEmpty == true)
    }

    @Test func aMemberStillOpenAfterTheConfirmationStopsTheQueueAndASecondClickResumesWithIt() throws {
        let start = ContinuousClock.now
        var (arranger, group, _, _) = try bareGroup(at: start, withA: true)
        let first = arranger.handle(.tab(.closeGroup(group), ready: true), now: start)
        #expect(closes(first) == [a])
        #expect(first.contains(.wake(at: start + Arranger.closeConfirmation)), "no wake at the close deadline: \(first)")
        #expect(!arranger.handle(.tick, now: start + .milliseconds(999)).contains(.checkClosePrompt(a)))
        #expect(arranger.handle(.tick, now: start + Arranger.closeConfirmation).contains(.checkClosePrompt(a)))
        let stop = arranger.handle(.closePrompt(a, showing: false), now: start + Arranger.closeConfirmation)
        #expect(stop.contains(.tabAnnouncement(.didNotClose(a))))
        #expect(closes(stop).isEmpty)
        #expect(selected(arranger, group) == a, "the window that stopped Close Group is not the one shown")
        #expect(arranger.tabs.closeQueue == nil)
        #expect(closes(arranger.handle(.tab(.closeGroup(group), ready: true), now: start + .seconds(5))) == [a])
    }

    /// D-06 (2026-11-02): a save prompt keeps Close Group waiting; Save or Don't Save closes the window and the rest
    /// close; Cancel leaves it open and stops the queue.
    @Test func aMemberShowingAPromptWaitsPastTheDeadlineAndTheRestCloseOnceItCloses() throws {
        let start = ContinuousClock.now
        var (arranger, group, _, content) = try bareGroup(at: start, withA: true)  // [b, f, a], a selected
        _ = arranger.handle(.tab(.closeGroup(group), ready: true), now: start)
        var now = start + Arranger.closeConfirmation
        #expect(arranger.handle(.tick, now: now) == [.checkClosePrompt(a), .wake(at: now + Arranger.closeConfirmation)])
        // The prompt stays up for a minute: checked again every poll, never stopped.
        for _ in 0..<120 {
            let waiting = arranger.handle(.closePrompt(a, showing: true), now: now)
            #expect(waiting.contains(.wake(at: now + Arranger.closePromptPoll)) && announcements(waiting).isEmpty)
            now = now + Arranger.closePromptPoll
            #expect(arranger.handle(.tick, now: now).contains(.checkClosePrompt(a)))
        }
        // Don't Save: the sheet is gone before Transom confirms the close; it gets one more confirmation to close.
        let gone = arranger.handle(.closePrompt(a, showing: false), now: now)
        #expect(announcements(gone).isEmpty && arranger.tabs.closeQueue?.current == a)
        var effects = arranger.handle(.event(.windowDestroyed(a)), now: now + .milliseconds(300)), pressed: [WindowRef] = []
        for _ in 0..<6 {
            if let close = closes(effects).first {
                pressed.append(close)
                effects = arranger.handle(.event(.windowDestroyed(close)), now: now)
            } else if let revealed = arranger.tabs.pendingReveal?.revealed {
                effects = arranger.handle(.event(.frameApplied(revealed, requested: content, actual: content)), now: now)
            } else {
                break
            }
        }
        #expect(pressed == [b, f])
        #expect(arranger.tabs.closeQueue == nil && arranger.world[mainKey]?.tree.windows.isEmpty == true)
    }

    @Test func aPromptCanceledWithTheWindowOpenStopsTheQueue() throws {
        let start = ContinuousClock.now
        var (arranger, group, _, _) = try bareGroup(at: start, withA: true)
        _ = arranger.handle(.tab(.closeGroup(group), ready: true), now: start)
        var now = start + Arranger.closeConfirmation
        _ = arranger.handle(.tick, now: now)
        _ = arranger.handle(.closePrompt(a, showing: true), now: now)
        now = now + Arranger.closePromptPoll
        _ = arranger.handle(.tick, now: now)
        // Cancel: the sheet goes and the window stays. One more confirmation, then a check with no sheet stops it.
        #expect(announcements(arranger.handle(.closePrompt(a, showing: false), now: now)).isEmpty)
        now = now + Arranger.closeConfirmation
        #expect(arranger.handle(.tick, now: now).contains(.checkClosePrompt(a)))
        let stop = arranger.handle(.closePrompt(a, showing: false), now: now)
        #expect(announcements(stop) == [.didNotClose(a)] && closes(stop).isEmpty)
        #expect(stop.contains(.info("group \(group.node): close stopped at \(a), its prompt was canceled")))
        #expect(arranger.tabs.closeQueue == nil && arranger.world[mainKey]?.contains(b) == true)
    }

    @Test func aCheckNeverAnsweredStopsAfterAnotherConfirmation() throws {
        let start = ContinuousClock.now
        var (arranger, group, _, _) = try bareGroup(at: start, withA: true)
        _ = arranger.handle(.tab(.closeGroup(group), ready: true), now: start)
        _ = arranger.handle(.tick, now: start + Arranger.closeConfirmation)
        let stop = arranger.handle(.tick, now: start + Arranger.closeConfirmation * 2)
        #expect(announcements(stop) == [.didNotClose(a)] && arranger.tabs.closeQueue == nil)
        #expect(arranger.handle(.closePrompt(a, showing: true), now: start + .seconds(3)).isEmpty, "a late answer was used")
    }

    @Test func aMemberMovedOutWhileAPromptShowsStopsTheQueue() throws {
        let start = ContinuousClock.now
        var (arranger, group, _, _) = try bareGroup(at: start, withA: true)  // [b, f, a], a selected
        _ = arranger.handle(.tab(.closeGroup(group), ready: true), now: start)
        _ = arranger.handle(.tick, now: start + Arranger.closeConfirmation)
        _ = arranger.handle(.closePrompt(a, showing: true), now: start + Arranger.closeConfirmation)
        _ = arranger.handle(.tab(.moveOut(b, via: .menu), ready: true), now: start + .seconds(2))
        let next = arranger.handle(.tick, now: start + .seconds(2))  // the prompt's next check
        #expect(next.contains(.info("group \(group.node): close stopped, the group changed")) && arranger.tabs.closeQueue == nil)
        #expect(closes(arranger.handle(.event(.windowDestroyed(a)), now: start + .seconds(3))).isEmpty, "a moved-out window was closed")
    }

    @Test func aSecondClickWhileClosingSendsNothingMore() throws {
        let start = ContinuousClock.now
        var (arranger, group, _, _) = try bareGroup(at: start, withA: true)
        _ = arranger.handle(.tab(.closeGroup(group), ready: true), now: start)
        #expect(closes(arranger.handle(.tab(.closeGroup(group), ready: true), now: start + .milliseconds(100))).isEmpty)
    }

    @Test(arguments: [true, false])
    func aRefusedCloseGroupBeepsAndSendsNothing(paused: Bool) throws {
        let start = ContinuousClock.now
        var (arranger, group, _, _) = try bareGroup(at: start)
        if paused { _ = arranger.handle(.setPaused(.user, true), now: start) }
        let effects = arranger.handle(.tab(.closeGroup(group), ready: paused), now: start)
        #expect(effects.contains(.beep) && effects.contains(.tabAnnouncement(.refused(paused ? .paused : .notReady))))
        #expect(commands(effects).isEmpty)
    }

    @Test func onTheFakeEveryMemberCloses() async throws {
        var (harness, plan) = try await docked()
        await groupFWithB(&harness, try #require(plan.frames[b]))
        let leaf = try #require(harness.arranger.world[mainKey]?.tree.leaf(containing: b))
        await harness.send(.tab(.closeGroup(GroupKey(desk: mainKey, node: leaf)), ready: true))
        let open = await harness.fake.windows.filter { $0.value.axValid }.keys.sorted()
        #expect(open == [1], "members still open: \(open)")
        #expect(harness.arranger.world[mainKey]?.contains(b) == false && harness.arranger.world[mainKey]?.contains(f) == false)
        #expect(harness.arranger.tabs.closeQueue == nil)
    }

    @Test func anExcludedMembersCloseNeverReachesTheSystem() async throws {
        var (harness, plan) = try await docked()
        await groupFWithB(&harness, try #require(plan.frames[b]))
        let leaf = try #require(harness.arranger.world[mainKey]?.tree.leaf(containing: b))
        await harness.fake.setExcluded(["com.example.arranger"])
        await harness.send(.tab(.closeGroup(GroupKey(desk: mainKey, node: leaf)), ready: true))
        #expect(await harness.fake.dropped.contains(.close(f)), "the close was not dropped")
        #expect(await harness.fake.windows[2]?.axValid == true, "the excluded window closed")
    }
}

/// TABS-03, D-06, D-07, Pitfall 6: Minimize Group minimises the selected member only and comes back with the same tab.
@Suite struct ArrangerMinimizeGroupTests {
    @Test func minimizeGroupMinimisesOnlyTheSelectedMemberAndParksNothing() throws {
        let start = ContinuousClock.now
        var (arranger, group, _, _) = try bareGroup(at: start)  // [b, f], f selected, b parked
        let effects = arranger.handle(.tab(.minimizeGroup(group), ready: true), now: start)
        #expect(commands(effects) == [.minimize(f)])
        #expect(effects.contains(.info("group \(group.node): minimized")))
        #expect(arranger.tabs.suppressedUntil[group] == start + Arranger.focusSuppression)
    }

    @Test func onceTheSelectedMemberIsAbsentTheGroupHasNoStripAndTheHiddenMemberStaysParked() throws {
        let start = ContinuousClock.now
        var (arranger, group, _, _) = try bareGroup(at: start)
        _ = arranger.handle(.tab(.minimizeGroup(group), ready: true), now: start)
        let absent = arranger.handle(.event(.windowStateChanged(f, .absent)), now: start + .milliseconds(200))
        #expect(strips(absent) == [[]], "the strip did not go: \(strips(absent))")
        // The group takes no part, so the engine plans no park for b, but nothing moves it off its park either.
        #expect(!commands(absent).contains { $0.window == b }, "the hidden member was moved: \(commands(absent))")
        #expect(selected(arranger, group) == f)
        let slot = try Planner.plan(desk: try #require(arranger.world[mainKey]), area: area, gap: 8, mins: [:])
        #expect(slot.frames[f] == nil && slot.frames[b] == nil, "an absent group was planned on screen")
    }

    @Test func macOSFocusingTheHiddenMemberAfterTheMinimiseDoesNotBringTheGroupBack() throws {
        let start = ContinuousClock.now
        var (arranger, group, _, _) = try bareGroup(at: start)
        _ = arranger.handle(.event(.windowFocused(a)), now: start)  // a, docked beside the group, is on screen
        _ = arranger.handle(.event(.windowFocused(f)), now: start)
        _ = arranger.handle(.tab(.minimizeGroup(group), ready: true), now: start)
        _ = arranger.handle(.event(.windowStateChanged(f, .absent)), now: start + .milliseconds(200))
        #expect(selected(arranger, group) == f, "Minimize Group's absence moved the selection")
        let focus = arranger.handle(.event(.windowFocused(b)), now: start + .milliseconds(700))
        #expect(selected(arranger, group) == f, "the same-app focus switched tabs")
        // WR-02: the parked b must not stay the key window; the last window on screen gets focus back.
        #expect(commands(focus) == [.focus(a)], "focus was not handed back: \(commands(focus))")
    }

    @Test func withNoWindowOnScreenToFocusTheFocusedHiddenMemberIsMinimisedWithTheGroup() throws {
        let start = ContinuousClock.now
        var (arranger, group, _, _) = try bareGroup(at: start)
        _ = arranger.handle(.tab(.minimizeGroup(group), ready: true), now: start)
        _ = arranger.handle(.event(.windowStateChanged(f, .absent)), now: start + .milliseconds(200))
        let focus = arranger.handle(.event(.windowFocused(b)), now: start + .milliseconds(700))
        #expect(commands(focus) == [.minimize(b)], "the parked key window was left: \(commands(focus))")
        _ = arranger.handle(.event(.windowStateChanged(b, .absent)), now: start + .milliseconds(900))
        #expect(selected(arranger, group) == f, "the group changed its selected tab")
        let back = arranger.handle(.event(.windowStateChanged(f, .present)), now: start + .seconds(5))
        #expect(selected(arranger, group) == f && setFrames(back)[f] != nil, "restoring the selected member did not bring the group back: \(back)")
    }

    @Test func restoringTheSelectedMemberBringsTheGroupBackWithTheSameTab() throws {
        let start = ContinuousClock.now
        var (arranger, group, frame, content) = try bareGroup(at: start)
        _ = arranger.handle(.tab(.minimizeGroup(group), ready: true), now: start)
        _ = arranger.handle(.event(.windowStateChanged(f, .absent)), now: start)
        let back = arranger.handle(.event(.windowStateChanged(f, .present)), now: start + .seconds(5))
        let strip = try #require(strips(back).first?.first, "no strip on restore: \(back)")
        #expect(strip.group == group && strip.selected == 1 && strip.members == [b, f] && strip.frame == TabBand.strip(of: frame))
        let plan = try Planner.plan(desk: try #require(arranger.world[mainKey]), area: area, gap: 8, mins: [:])
        #expect(plan.frames[f] == content)
        #expect(arranger.isParked(b))
    }
}

/// D-12: members closing by any route (⌘W, the app quitting) keep the group consistent.
@Suite struct ArrangerTabMemberCloseTests {
    @Test func theSelectedMemberClosingSelectsTheRightNeighbourInTheContentRect() throws {
        let start = ContinuousClock.now
        var (arranger, group, _, content) = try bareGroup(at: start, withA: true)  // [b, f, a], a selected
        _ = arranger.handle(.tab(.select(f, via: .click), ready: true), now: start)
        _ = arranger.handle(.event(.frameApplied(f, requested: content, actual: content)), now: start)
        try #require(selected(arranger, group) == f && arranger.isParked(a))
        let closed = arranger.handle(.event(.windowDestroyed(f)), now: start + .seconds(2))
        #expect(selected(arranger, group) == a)
        #expect(commands(closed).contains(.setFrame(a, content)), "a was not written into the content rect: \(commands(closed))")
        #expect(!parks(closed).contains { $0.window == a })
        #expect(!closed.contains { if case .tabAnnouncement = $0 { true } else { false } }, "a neighbour selection was announced")
    }

    @Test func theLastMemberClosingSelectsTheLeftNeighbour() throws {
        let start = ContinuousClock.now
        var (arranger, group, _, content) = try bareGroup(at: start, withA: true)
        let closed = arranger.handle(.event(.windowDestroyed(a)), now: start)
        #expect(selected(arranger, group) == f)
        #expect(commands(closed).contains(.setFrame(f, content)), "f was not written into the content rect: \(commands(closed))")
    }

    @Test func aHiddenMemberClosingOnlyDropsItsTab() throws {
        let start = ContinuousClock.now
        var (arranger, group, frame, _) = try bareGroup(at: start, withA: true)
        let closed = arranger.handle(.event(.windowStateChanged(b, .closed)), now: start)
        let strip = try #require(strips(closed).first?.first, "the strip was not sent again: \(closed)")
        #expect(strip.members == [f, a] && strip.selected == 1 && strip.frame == TabBand.strip(of: frame))
        #expect(!commands(closed).contains { $0.window == a }, "the selected member was moved: \(commands(closed))")
        #expect(!closed.contains(.tabAnnouncement(.ended)))
        #expect(selected(arranger, group) == a)
    }

    @Test func aDockedGroupLeftWithOneMemberDissolvesIntoAPlainTileUnderTheSameNode() throws {
        let start = ContinuousClock.now
        var (arranger, group, frame, _) = try bareGroup(at: start)  // [b, f], f selected
        let closed = arranger.handle(.event(.windowDestroyed(f)), now: start)
        #expect(arranger.world[mainKey]?.tree.node(group.node) == .panel(b))
        #expect(setFrames(closed)[b] == frame, "b did not take the whole group frame: \(closed)")
        #expect(strips(closed) == [[]])
        #expect(closed.contains(.tabAnnouncement(.ended)))
        #expect(closed.contains(.info("group \(group.node): dissolved, \(b) keeps the tile")))
    }

    @Test func aFloatingGroupLeftWithOneMemberDissolvesIntoAFloater() throws {
        let start = ContinuousClock.now
        var (arranger, group, _) = try bareFloatingGroup(at: start)  // [t, f], f selected
        let closed = arranger.handle(.event(.windowDestroyed(t)), now: start + .seconds(1))
        #expect(closed.contains(.tabAnnouncement(.ended)))
        #expect(closed.contains(.info("group \(group.node): dissolved, \(f) keeps the frame")))
    }

    @Test func closeGroupDoesNotAnnounceTheDissolveOnTheWay() throws {
        let start = ContinuousClock.now
        var (arranger, group, _, _) = try bareGroup(at: start)
        var effects = arranger.handle(.tab(.closeGroup(group), ready: true), now: start), all = effects
        for _ in 0..<4 {
            guard let close = closes(effects).first else { break }
            effects = arranger.handle(.event(.windowDestroyed(close)), now: start)
            all += effects
        }
        #expect(arranger.world[mainKey]?.tree.windows == [a], "not every member closed: \(all)")
        #expect(!all.contains(.tabAnnouncement(.ended)), "Close Group announced the dissolve")
    }
}

private func floatingGroup(_ arranger: Arranger) -> FloatingTabGroup? { arranger.world[mainKey]?.desktop.groups.first }

/// TABS-03, D-06, UI-SPEC Surface 5: Float Group / Dock Group and every path that moves a group's window move the whole group.
@Suite struct ArrangerWholeGroupTests {
    @Test func floatGroupFloatsTheWholeDockedGroupInOneUndoStep() throws {
        let start = ContinuousClock.now
        var (arranger, group, _, tileContent) = try bareGroup(at: start)  // [b, f], f selected, b parked
        _ = arranger.handle(.event(.windowMoved(f, tileContent)), now: start)  // f's echo
        let depth = arranger.history.depth(for: mainKey)
        let effects = arranger.handle(.tab(.toggleGroupFloat(group), ready: true), now: start)
        let floated = try #require(floatingGroup(arranger), "no floating group: \(effects)")
        #expect(floated.members == [b, f] && floated.selected == 1)
        #expect(arranger.world[mainKey]?.tree.windows == [a], "the group's tile did not close")
        #expect(arranger.history.depth(for: mainKey) == depth + 1, "Float Group is not one undo step")
        let content = TabBand.content(of: floated.frame)
        #expect(setFrames(effects).filter { $0.key != a } == [f: content], "group writes: \(setFrames(effects))")
        #expect(parks(effects) == [.park(b, displayUUID: "main", size: Size(width: content.width, height: content.height))])
        let strip = try #require(strips(effects).last?.first, "no strip: \(effects)")
        #expect(strip.floating && strip.frame == TabBand.strip(of: floated.frame) && strip.members == [b, f] && strip.selected == 1)
        #expect(effects.contains(.info("group \(group.node): floated")))
        _ = arranger.handle(.command(.undo, focused: f), now: start + .seconds(1))
        #expect(arranger.world[mainKey]?.tree.node(group.node) == .tabs(windows: [b, f], selected: 1), "Undo did not restore the docked leaf")
        #expect(floatingGroup(arranger) == nil)
    }

    @Test func dockGroupDocksTheWholeFloatingGroupAsOneLeafAtItsCentre() throws {
        let start = ContinuousClock.now
        var (arranger, group, _) = try bareFloatingGroup(at: start)  // [t, f] at tFrame, f selected
        let depth = arranger.history.depth(for: mainKey)
        let effects = arranger.handle(.tab(.toggleGroupFloat(group), ready: true), now: start + .seconds(1))
        let desk = try #require(arranger.world[mainKey])
        let leaf = try #require(desk.tree.leaf(containing: f), "the group did not dock: \(effects)")
        #expect(desk.tree.node(leaf) == .tabs(windows: [t, f], selected: 1))
        #expect(desk.desktop.groups.isEmpty && desk.desktop.windows.isEmpty)
        // Nothing else is docked: the group becomes the first tile and fills the visible frame (D-08).
        #expect(desk.tree.root == leaf)
        #expect(arranger.history.depth(for: mainKey) == depth + 1)
        #expect(effects.contains(.info("group \(group.node): docked")))
        _ = arranger.handle(.command(.undo, focused: f), now: start + .seconds(2))
        #expect(arranger.world[mainKey]?.desktop.groups.first?.members == [t, f], "Undo did not restore the floating group")
    }

    @Test func dockGroupWithNoRoomFlashesBlockedAndChangesNothing() throws {
        let start = ContinuousClock.now
        var (arranger, group, _) = try bareFloatingGroup(at: start, fMinimum: Size(width: 300, height: 860))
        let before = arranger.world, depth = arranger.history.depth(for: mainKey)
        let effects = arranger.handle(.tab(.toggleGroupFloat(group), ready: true), now: start + .seconds(1))
        #expect(effects.contains(.beep) && effects.contains(.announce(Arranger.noRoom)), "not refused: \(effects)")
        #expect(effects.contains { if case .flashBlocked = $0 { true } else { false } })
        #expect(arranger.world == before && arranger.history.depth(for: mainKey) == depth)
    }

    @Test func floatAndDockWindowOnAMemberMoveTheWholeGroup() throws {
        let start = ContinuousClock.now
        var (arranger, group, _, _) = try bareGroup(at: start)  // [b, f] docked, f selected
        _ = arranger.handle(.command(.float, focused: f), now: start)
        let floated = try #require(floatingGroup(arranger), "Float Window tore f out")
        #expect(floated.members == [b, f] && floated.selected == 1)
        #expect(arranger.world[mainKey]?.tree.node(group.node) == nil)
        _ = arranger.handle(.command(.dock, focused: f), now: start + .seconds(1))
        let desk = try #require(arranger.world[mainKey])
        #expect(desk.tree.leaf(containing: b) == desk.tree.leaf(containing: f) && desk.tree.leaf(containing: f) != nil, "Dock Window docked one member")
        #expect(desk.desktop.groups.isEmpty)
    }

    @Test func theGreenButtonOnTheSelectedMemberTogglesTheWholeGroup() throws {
        let start = ContinuousClock.now
        var (arranger, _, _, _) = try bareGroup(at: start)
        _ = arranger.handle(.greenButton(f), now: start)
        #expect(floatingGroup(arranger)?.members == [b, f], "the green button did not float the group")
        _ = arranger.handle(.greenButton(f), now: start + .seconds(1))
        let desk = try #require(arranger.world[mainKey])
        #expect(floatingGroup(arranger) == nil)
        #expect(desk.tree.node(try #require(desk.tree.leaf(containing: f))) == .tabs(windows: [b, f], selected: 1))
    }

    @Test func arrangeAllDocksAFloatingGroupAsOneLeaf() throws {
        let start = ContinuousClock.now
        var (arranger, _, _) = try bareFloatingGroup(at: start)
        let effects = arranger.handle(.command(.arrangeAll, focused: f), now: start + .seconds(1))
        let desk = try #require(arranger.world[mainKey])
        #expect(desk.tree.node(try #require(desk.tree.leaf(containing: t))) == .tabs(windows: [t, f], selected: 1))
        #expect(desk.desktop.groups.isEmpty)
        #expect(!effects.contains { if case .notice = $0 { true } else { false } }, "the group was counted as leftovers: \(effects)")
    }

    @Test func floatAllFloatsADockedGroupAsOneGroupCountedOnce() throws {
        let start = ContinuousClock.now
        var (arranger, _, frame, _) = try bareGroup(at: start)  // [a | [b, f]]
        let effects = arranger.handle(.command(.floatAll, focused: a), now: start)
        #expect(effects.contains(.notice(.floatedAll(count: 2))), "a and the group are not two: \(effects)")
        let floated = try #require(floatingGroup(arranger))
        #expect(floated.members == [b, f] && floated.selected == 1)
        #expect(floated.frame.width == frame.width && floated.frame.height == frame.height, "the group frame is not its tile rect")
        #expect(arranger.world[mainKey]?.tree.windows.isEmpty == true)
    }

    @Test func rehomingTheSelectedMemberMovesTheWholeGroupAndAHiddenMembersReportIsIgnored() throws {
        let start = ContinuousClock.now
        let side = DisplayInfo(
            uuid: "side", frame: Rect(x: 1440, y: 0, width: 1280, height: 800), visibleFrame: Rect(x: 1440, y: 25, width: 1280, height: 775),
            currentSpaceID: nil)
        var (arranger, group, _, _) = try bareGroup(at: start, displays: [mainDisplay, side])
        let sideKey = DeskKey(displayUUID: "side", spaceID: nil)
        let away = Rect(x: 1600, y: 200, width: 400, height: 300)
        let hidden = WindowInfo(window: b, frame: away, state: .present, displayUUID: "side", kind: .dockable, isExcluded: false)
        _ = arranger.handle(.event(.windowChanged(hidden)), now: start)
        #expect(arranger.world[mainKey]?.tree.node(group.node) == .tabs(windows: [b, f], selected: 1), "a hidden member's report moved something")
        var moved = hidden
        moved.window = f
        _ = arranger.handle(.event(.windowChanged(moved)), now: start + .seconds(1))
        #expect(arranger.world[mainKey]?.contains(b) == false && arranger.world[mainKey]?.contains(f) == false)
        let there = try #require(arranger.world[sideKey]?.desktop.groups.first, "the group did not follow f")
        #expect(there.members == [b, f] && there.selected == 1 && there.frame == TabBand.frame(ofContent: away))
    }

    @Test func treeCommandsActOnTheGroupsLeafAndFocusLandsOnTheSelectedTab() throws {
        let start = ContinuousClock.now
        var (arranger, group, _, _) = try bareGroup(at: start)  // [a | [b, f]]
        #expect(commands(arranger.handle(.command(.focus(.right), focused: a), now: start)) == [.focus(f)])
        let grown = arranger.handle(.command(.growTile, focused: f), now: start)
        #expect(!grown.contains(.beep), "Grow refused: \(grown)")
        #expect(arranger.world[mainKey]?.tree.node(group.node) == .tabs(windows: [b, f], selected: 1))
        _ = arranger.handle(.command(.moveOrSnap(.left), focused: f), now: start)
        let desk = try #require(arranger.world[mainKey])
        let leaf = try #require(desk.tree.leaf(containing: f))
        #expect(desk.tree.node(leaf) == .tabs(windows: [b, f], selected: 1), "Move tore the group apart")
        #expect(desk.tree.windows.first == b, "the group did not move left of a: \(desk.tree.windows)")
        _ = arranger.handle(.event(.windowFocused(a)), now: start)
        _ = arranger.handle(.event(.windowFocused(f)), now: start)
        _ = arranger.handle(.command(.swapPrevious, focused: f), now: start)
        #expect(arranger.world[mainKey]?.tree.windows == [a, b, f], "Swap did not exchange the group and a")
    }

    @Test func snapOnAFloatingGroupMemberSnapsTheGroupFrame() throws {
        let start = ContinuousClock.now
        var (arranger, _, _) = try bareFloatingGroup(at: start)
        _ = arranger.handle(.command(.snap(.leftHalf), focused: f), now: start + .seconds(1))
        let group = try #require(floatingGroup(arranger))
        let expected = Snap.frame(.leftHalf, window: tFrame, area: area, gap: 8)
        #expect(group.frame == expected, "the group frame did not snap: \(group.frame)")
        #expect(arranger.world[mainKey]?.desktop.frame(of: f) == TabBand.content(of: expected))
    }

    @Test(arguments: [true, false])
    func aRefusedFloatGroupBeepsAndChangesNothing(paused: Bool) throws {
        let start = ContinuousClock.now
        var (arranger, group, _, _) = try bareGroup(at: start)
        if paused { _ = arranger.handle(.setPaused(.user, true), now: start) }
        let before = arranger.world
        let effects = arranger.handle(.tab(.toggleGroupFloat(group), ready: paused), now: start)
        #expect(effects.contains(.beep) && effects.contains(.tabAnnouncement(.refused(paused ? .paused : .notReady))))
        #expect(arranger.world == before)
    }
}

/// [a | [b, f]] on the fake, f selected; returns the group leaf, a's tile and the group's content rect.
private func dockedGroup() async throws -> (Harness, leaf: NodeID, ra: Rect, content: Rect) {
    var (harness, plan) = try await docked()
    let ra = try #require(plan.frames[a])
    await groupFWithB(&harness, try #require(plan.frames[b]))
    let desk = try #require(harness.arranger.world[mainKey])
    let leaf = try #require(desk.tree.leaf(containing: f))
    try #require(desk.tree.node(leaf) == .tabs(windows: [b, f], selected: 1), "f did not group with b")
    let content = try #require(try Planner.plan(desk: desk, area: area, gap: 8, mins: [:]).frames[f])
    try #require(await harness.frame(f) == content)
    return (harness, leaf, ra, content)
}

/// The group frame the group leaf `leaf` of the main desk gets docked on `edge` of `target`.
private func groupDocked(_ arranger: Arranger, _ leaf: NodeID, at edge: Edge, of target: NodeID) throws -> Rect {
    var desk = try #require(arranger.world[mainKey])
    var ids = arranger.world.ids
    let taken = try desk.tree.removeLeaf(leaf)
    try desk.tree.insertLeaf(taken.node, states: taken.states, at: edge, of: target, ids: &ids)
    let moved = try #require(desk.tree.leaf(containing: f))
    return try #require(try Planner.plan(desk: desk, area: area, gap: 8, mins: [:]).resolution.nodeRects[moved])
}

/// UI-SPEC Surface 5: a title-bar drag of the selected member moves the whole group.
@Suite struct ArrangerWholeGroupDragTests {
    @Test func anEdgeBandPreviewsTheGroupFrameAndTheReleaseMovesTheWholeLeaf() async throws {
        var (harness, leaf, ra, content) = try await dockedGroup()
        let aLeaf = try #require(harness.arranger.world[mainKey]?.tree.leaf(containing: a))
        let expected = try groupDocked(harness.arranger, leaf, at: .left, of: aLeaf)
        let point = Point(x: ra.minX + 0.1 * ra.width, y: ra.midY)
        _ = await drag(&harness, f, from: content, to: point)
        harness.now += DragSession.dwell
        let tick = await harness.send(.tick)
        #expect(previews(tick) == [.dock(expected)], "tick gave \(tick)")
        let depth = harness.arranger.history.depth(for: mainKey)
        await harness.send(pointer(.up, point.x, point.y))
        let desk = try #require(harness.arranger.world[mainKey])
        #expect(desk.tree.windows == [b, f, a], "the group did not move left of a: \(desk.tree.windows)")
        #expect(desk.tree.node(try #require(desk.tree.leaf(containing: f))) == .tabs(windows: [b, f], selected: 1))
        #expect(harness.arranger.history.depth(for: mainKey) == depth + 1, "the move is not one undo step")
    }

    @Test func aShiftDragFloatsTheWholeGroupAtTheReleasePosition() async throws {
        var (harness, _, _, content) = try await dockedGroup()
        let grab = Point(x: content.midX, y: content.minY + 10)
        let point = Point(x: grab.x + 300, y: grab.y)
        _ = await drag(&harness, f, from: content, to: point, [.shift])
        harness.now += DragSession.dwell
        await harness.send(.tick)
        let depth = harness.arranger.history.depth(for: mainKey)
        await harness.send(pointer(.up, point.x, point.y, [.shift]))
        let group = try #require(harness.arranger.world[mainKey]?.desktop.groups.first, "the group did not float")
        #expect(group.members == [b, f] && group.selected == 1)
        #expect(group.frame == TabBand.frame(ofContent: shifted(content, 300)), "group frame \(group.frame)")
        #expect(harness.arranger.world[mainKey]?.tree.windows == [a])
        #expect(harness.arranger.history.depth(for: mainKey) == depth + 1)
    }

    /// D-05 (UI-SPEC Surface 2 row 2): released over a's tile, the group floats at its release group frame, no ghost.
    @Test func aShiftDragFloatsTheWholeGroupOverATileWithNoClamp() async throws {
        var (harness, _, ra, content) = try await dockedGroup()
        let grab = Point(x: content.midX, y: content.minY + 10)
        let point = centre(ra)
        let during = await drag(&harness, f, from: content, to: point, [.shift])
        harness.now += DragSession.dwell
        #expect(previews(during + (await harness.send(.tick))).isEmpty, "a pull-out showed a preview")
        await harness.send(pointer(.up, point.x, point.y, [.shift]))
        let group = try #require(harness.arranger.world[mainKey]?.desktop.groups.first, "the group did not float")
        let outer = TabBand.frame(ofContent: shifted(content, point.x - grab.x, point.y - grab.y))
        #expect(outer.overlaps(ra))
        #expect(group.frame == outer, "group frame \(group.frame)")
    }

    @Test func aCommandDragSwapsTheGroupWithAPlainPanel() async throws {
        var (harness, leaf, ra, content) = try await dockedGroup()
        let desk = try #require(harness.arranger.world[mainKey])
        let frame = try #require(try Planner.plan(desk: desk, area: area, gap: 8, mins: [:]).resolution.nodeRects[leaf])
        _ = await drag(&harness, f, from: content, to: centre(ra), [.command])
        harness.now += DragSession.dwell
        let tick = await harness.send(.tick)
        #expect(previews(tick) == [.swap(target: ra, origin: frame)], "tick gave \(tick)")
        let up = await harness.send(pointer(.up, ra.midX, ra.midY, [.command]))
        #expect(harness.arranger.world[mainKey]?.tree.windows == [b, f, a], "the group and a did not swap")
        #expect(up.contains(.announce(Arranger.swapped)))
    }

    @Test func aCommandDragOverAnotherGroupNeverSwaps() throws {
        let start = ContinuousClock.now
        var arranger = Arranger()
        let infos = [info(1, frame: frameA), info(2, frame: smallF), info(3, frame: frameB), info(4, frame: gFrame)]
        _ = arranger.handle(.inventory(WindowInventory(displays: [mainDisplay], windows: infos, initialRefreshComplete: true)), now: start)
        _ = arranger.handle(.command(.dock, focused: a), now: start)
        _ = arranger.handle(.command(.dock, focused: b), now: start)
        let aLeaf = try #require(arranger.world[mainKey]?.tree.leaf(containing: a))
        let bLeaf = try #require(arranger.world[mainKey]?.tree.leaf(containing: b))
        try arranger.world.edit(mainKey, history: &arranger.history) { desk, _ throws(LayoutError) in
            try desk.desktop.remove(f)
            try desk.tree.group(f, into: bLeaf)
            try desk.desktop.remove(g)
            try desk.tree.group(g, into: aLeaf)
        }
        _ = arranger.handle(.gap(8), now: start)
        let grouped = try #require(arranger.world[mainKey])
        let plan = try Planner.plan(desk: grouped, area: area, gap: 8, mins: [:])
        let content = try #require(plan.frames[f]), aContent = try #require(plan.frames[g])
        _ = arranger.handle(.event(.windowMoved(f, content)), now: start)
        let before = arranger.world[mainKey]?.tree
        var effects = drag(&arranger, f, from: content, to: centre(aContent), [.command], at: start)
        effects += arranger.handle(.tick, now: start + .milliseconds(450))
        #expect(!previews(effects).contains { if case .swap = $0 { true } else { false } }, "a swap was offered: \(previews(effects))")
        _ = arranger.handle(pointer(.up, aContent.midX, aContent.midY, [.command]), now: start + .milliseconds(500))
        #expect(arranger.world[mainKey]?.tree == before, "the groups changed")
    }

    @Test func aReleaseWithNoTargetSnapsTheDockedGroupBack() async throws {
        var (harness, leaf, _, content) = try await dockedGroup()
        let point = Point(x: content.midX + 40, y: content.minY + 10)
        _ = await drag(&harness, f, from: content, to: point)
        harness.now += DragSession.dwell
        await harness.send(.tick)
        let up = await harness.send(pointer(.up, point.x, point.y))
        #expect(setFrames(up)[f] == content, "f did not snap back: \(up)")
        #expect(harness.arranger.world[mainKey]?.tree.node(leaf) == .tabs(windows: [b, f], selected: 1))
    }

    @Test func aFloatingGroupMovesWithItsWindowOnAMissAndDocksWholeOnAnEdge() async throws {
        var harness = await floaters()
        _ = await groupFOntoT(&harness)
        let content = TabBand.content(of: tFrame)
        let point = Point(x: content.midX - 100, y: content.minY + 10 + 50)  // on the empty desk, no floater's centre
        _ = await drag(&harness, f, from: content, to: point)
        harness.now += DragSession.dwell
        await harness.send(.tick)
        await harness.send(pointer(.up, point.x, point.y))
        let moved = shifted(content, -100, 50)
        #expect(harness.arranger.world[mainKey]?.desktop.groups.first?.frame == TabBand.frame(ofContent: moved), "the group did not follow")
        // Onto the display's left edge: the whole group docks.
        let edge = Point(x: 10, y: 450)
        _ = await drag(&harness, f, from: moved, to: edge)
        harness.now += DragSession.dwell
        await harness.send(.tick)
        await harness.send(pointer(.up, edge.x, edge.y))
        let desk = try #require(harness.arranger.world[mainKey])
        #expect(desk.desktop.groups.isEmpty)
        #expect(desk.tree.node(try #require(desk.tree.leaf(containing: f))) == .tabs(windows: [t, f], selected: 1), "the group did not dock whole")
    }

    @Test func aCentreNeverGroupsDuringAWholeGroupDrag() async throws {
        var (harness, leaf, ra, content) = try await dockedGroup()
        _ = await drag(&harness, f, from: content, to: centre(ra))
        harness.now += .milliseconds(450)
        let tick = await harness.send(.tick)
        #expect(groupPreviews(tick).isEmpty, "a group preview showed: \(tick)")
        await harness.send(pointer(.up, ra.midX, ra.midY))
        let tree = try #require(harness.arranger.world[mainKey]?.tree)
        #expect(tree.node(leaf) == .tabs(windows: [b, f], selected: 1))
        #expect(tree.node(try #require(tree.leaf(containing: a))) == .panel(a))
    }
}

// MARK: Tear-off (D-10, TABS-04)

private func tabPress(_ member: WindowRef, at point: Point, _ modifiers: Modifiers = []) -> ArrangerInput {
    .pointer(PointerEvent(kind: .down, location: point, modifiers: modifiers, pressTab: member))
}

private func ghosts(_ effects: [ArrangerEffect]) -> [TearOffGhost?] {
    effects.compactMap { if case .tearOffGhost(let ghost) = $0 { ghost } else { nil } }
}

private func announcements(_ effects: [ArrangerEffect]) -> [TabAnnouncement] {
    effects.compactMap { if case .tabAnnouncement(let announcement) = $0 { announcement } else { nil } }
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
    var effects = arranger.handle(tabPress(member, at: centre(strip), modifiers), now: now)
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

/// The torn group's own tile: its centre is no region for its own tab (never a group target), so a release there floats
/// the tab.
private func ownTile(_ arranger: Arranger, _ group: GroupKey) throws -> Rect {
    let desk = try #require(arranger.world[mainKey])
    return try #require(try Planner.plan(desk: desk, area: area, gap: 8, mins: [:]).resolution.nodeRects[group.node])
}

@Suite struct ArrangerTearOffTests {
    @Test func aTabPressWithDragsInsideTheStripStartsNothingAndChangesNothing() throws {
        let start = ContinuousClock.now
        var (arranger, group, _, _) = try bareGroup(at: start)  // [b, f], f selected
        let strip = try stripRect(arranger, group)
        let before = arranger.world
        var effects = arranger.handle(tabPress(b, at: centre(strip)), now: start)
        effects += arranger.handle(pointer(.dragged, strip.midX + 30, strip.midY), now: start)
        #expect(arranger.drag == nil, "a session started inside the strip")
        effects += arranger.handle(pointer(.up, strip.midX + 30, strip.midY), now: start)
        #expect(effects.isEmpty, "a press inside the strip did something: \(effects)")
        #expect(arranger.world == before)
        // The press is gone: a later drag outside the strip starts nothing.
        _ = arranger.handle(pointer(.dragged, strip.midX, strip.maxY + 200), now: start)
        #expect(arranger.drag == nil)
    }

    @Test func leavingTheStripStartsAMoveSessionWithNoFramePollAndShowsTheGhost() throws {
        let start = ContinuousClock.now
        var (arranger, group, _, _) = try bareGroup(at: start)
        let point = Point(x: 1200, y: 500)
        let effects = try tear(&arranger, b, of: group, to: point, at: start)
        let session = try #require(arranger.drag, "no tear-off session")
        #expect(session.window == b && session.kind == .move && session.tearOffGroup == group)
        #expect(!effects.contains { if case .pollDragFrame = $0 { true } else { false } }, "a frame poll was asked for: \(effects)")
        #expect(ghosts(effects).last == TearOffGhost(member: b, title: "", pointer: point))
        #expect(arranger.isDragging)
    }

    @Test func aReleaseOnNoRegionFloatsTheTabAtTheClampedLandingFrameInOneUndoStep() throws {
        let start = ContinuousClock.now
        var (arranger, group, _, content) = try bareGroup(at: start, withA: true)  // [b, f, a], a selected
        let own = try ownTile(arranger, group)
        arranger.wantedFrames[b.identity] = Rect(x: 0, y: 0, width: own.width - 40, height: own.height - 40)  // its pre-group frame
        let point = centre(own)  // the landing frame (top 12 pt above the pointer) must be clamped up
        let expected = Planner.clamp(landing(arranger, b, content: content, at: point), into: area)
        _ = try tear(&arranger, b, of: group, to: point, at: start)
        let tick = arranger.handle(.tick, now: start + DragSession.dwell)
        #expect(previews(tick) == [.clamp(expected)], "tick gave \(tick)")
        let depth = arranger.history.depth(for: mainKey)
        let grouped = arranger.world
        let up = arranger.handle(pointer(.up, point.x, point.y), now: start + .milliseconds(200))
        let desk = try #require(arranger.world[mainKey])
        #expect(desk.desktop.frame(of: b) == expected, "b floats at \(String(describing: desk.desktop.frame(of: b)))")
        #expect(desk.tree.node(group.node) == .tabs(windows: [f, a], selected: 1), "the group lost more than b")
        #expect(arranger.history.depth(for: mainKey) == depth + 1, "the tear-off is not one undo step")
        #expect(announcements(up) == [.movedOut(dissolved: false)])
        #expect(ghosts(up) == [nil], "the ghost was not hidden: \(up)")
        #expect(commands(up).contains(.focus(b)))
        #expect(up.contains(.info("group \(group.node): \(b) moved out via tear-off, landed floating")))
        #expect(arranger.drag == nil)
        _ = arranger.handle(.command(.undo, focused: b), now: start + .milliseconds(300))
        #expect(arranger.world[mainKey]?.tree == grouped[mainKey]?.tree, "Undo did not restore the group")
        #expect(arranger.world[mainKey]?.desktop.contains(b) == false)
    }

    @Test func tearingFromATwoTabGroupDissolvesIt() throws {
        let start = ContinuousClock.now
        var (arranger, group, frame, _) = try bareGroup(at: start)  // [b, f], f selected
        let own = try ownTile(arranger, group)
        _ = try tear(&arranger, f, of: group, to: centre(own), at: start)
        let up = arranger.handle(pointer(.up, own.midX, own.midY), now: start + .milliseconds(200))
        let desk = try #require(arranger.world[mainKey])
        #expect(desk.tree.node(group.node) == .panel(b), "the group did not dissolve into b")
        #expect(desk.desktop.contains(f))
        #expect(setFrames(up)[b] == frame, "b did not take the whole group frame: \(up)")
        #expect(announcements(up) == [.movedOut(dissolved: true)])
    }
}

/// UI-SPEC Surface 4 release table and D-12 for tear-offs.
@Suite struct ArrangerTearOffReleaseTests {
    private func tileOfA(_ arranger: Arranger) throws -> Rect {
        let desk = try #require(arranger.world[mainKey])
        return try #require(try Planner.plan(desk: desk, area: area, gap: 8, mins: [:]).frames[a])
    }

    @Test func aReleaseOverADockPreviewDocksTheTabOutOfItsGroupInOneUndoStep() throws {
        let start = ContinuousClock.now
        var (arranger, group, _, _) = try bareGroup(at: start)  // [a | [b, f]], f selected
        let ra = try tileOfA(arranger)
        let point = Point(x: ra.minX + 0.1 * ra.width, y: ra.midY)
        _ = try tear(&arranger, f, of: group, to: point, at: start)
        let tick = arranger.handle(.tick, now: start + DragSession.dwell)
        #expect(previews(tick).contains { if case .dock = $0 { true } else { false } }, "no Dock preview: \(tick)")
        let depth = arranger.history.depth(for: mainKey)
        let up = arranger.handle(pointer(.up, point.x, point.y), now: start + .milliseconds(200))
        let tree = try #require(arranger.world[mainKey]?.tree)
        #expect(tree.node(try #require(tree.leaf(containing: f))) == .panel(f), "f did not dock as its own tile")
        #expect(tree.windows.first == f, "f did not dock left of a: \(tree.windows)")
        #expect(tree.node(group.node) == .panel(b), "the group did not dissolve into b")
        #expect(arranger.history.depth(for: mainKey) == depth + 1, "the dock is not one undo step")
        #expect(announcements(up) == [.movedOut(dissolved: true)])
        #expect(up.contains(.info("group \(group.node): \(f) moved out via tear-off, landed docked")))
    }

    @Test func aReleaseOverAGroupPreviewFormsThatGroupSelected() throws {
        let start = ContinuousClock.now
        var (arranger, group, _, _) = try bareGroup(at: start)  // [a | [b, f]], f selected, b hidden
        let ra = try tileOfA(arranger)
        _ = try tear(&arranger, b, of: group, to: centre(ra), at: start)
        let tick = arranger.handle(.tick, now: start + DragSession.groupDwell)
        #expect(!groupPreviews(tick).isEmpty, "no Group preview: \(tick)")
        let up = arranger.handle(pointer(.up, ra.midX, ra.midY), now: start + .milliseconds(450))
        let tree = try #require(arranger.world[mainKey]?.tree)
        let aLeaf = try #require(tree.leaf(containing: a))
        #expect(tree.node(aLeaf) == .tabs(windows: [a, b], selected: 1), "b did not group with a: \(String(describing: tree.node(aLeaf)))")
        #expect(tree.node(group.node) == .panel(f), "the old group did not dissolve into f")
        #expect(announcements(up) == [.grouped(tabs: 2)])
    }

    @Test func itsOwnGroupsCentreIsNeverAGroupTarget() throws {
        let start = ContinuousClock.now
        var (arranger, group, _, content) = try bareGroup(at: start)
        _ = try tear(&arranger, b, of: group, to: centre(content), at: start)
        let tick = arranger.handle(.tick, now: start + .milliseconds(450))
        #expect(groupPreviews(tick).isEmpty, "its own group was offered: \(tick)")
        #expect(previews(tick).contains { if case .clamp = $0 { true } else { false } }, "no landing ghost: \(tick)")
    }

    /// WR-01 (iteration 3): a torn tab is still in its group until release, so the group's tile stays on screen and a
    /// floater behind the group's selected member (focused after it) takes no group.
    @Test func aTornTabOverItsOwnGroupDoesNotGroupWithAFloaterBehindTheGroup() throws {
        let start = ContinuousClock.now
        // [b, f] docked on the right (f selected), t floating inside that tile.
        var (arranger, group, frame, _) = try bareGroup(
            at: start, floating: [info(5, frame: Rect(x: 1000, y: 300, width: 300, height: 200))])
        let tf = try #require(arranger.world[mainKey]?.desktop.frame(of: t))
        try #require(frame.contains(centre(tf)), "t is not over the group's tile: \(tf) \(frame)")
        _ = arranger.handle(.event(.windowFocused(t)), now: start)
        _ = arranger.handle(.event(.windowFocused(f)), now: start)
        _ = try tear(&arranger, b, of: group, to: centre(tf), at: start)
        let tick = arranger.handle(.tick, now: start + DragSession.groupDwell)
        #expect(groupPreviews(tick).isEmpty, "a group was offered over t, behind f: \(tick)")
        _ = arranger.handle(pointer(.up, tf.midX, tf.midY), now: start + .milliseconds(450))
        #expect(arranger.world[mainKey]?.desktop.groups.isEmpty == true, "b grouped with t, behind f")
    }

    @Test func aReleaseBackOverTheSourceStripCancelsWithNoChange() throws {
        let start = ContinuousClock.now
        var (arranger, group, _, _) = try bareGroup(at: start)
        let strip = try stripRect(arranger, group)
        let before = arranger.world
        _ = try tear(&arranger, b, of: group, to: Point(x: 1200, y: 500), at: start)
        _ = arranger.handle(.tick, now: start + DragSession.dwell)
        var effects = arranger.handle(pointer(.dragged, strip.midX, strip.midY), now: start + .milliseconds(200))
        effects += arranger.handle(.tick, now: start + .milliseconds(400))
        #expect(previews(effects).isEmpty, "a preview showed over the strip: \(effects)")
        let up = arranger.handle(pointer(.up, strip.midX, strip.midY), now: start + .milliseconds(450))
        #expect(arranger.world == before, "the release over the strip changed the World")
        #expect(announcements(up).isEmpty)
        #expect(up.contains(.info("group \(group.node): tear-off canceled (strip)")))
        #expect(ghosts(up) == [nil])
    }

    @Test func commandNeverOffersSwap() throws {
        let start = ContinuousClock.now
        var (arranger, group, _, _) = try bareGroup(at: start)
        let ra = try tileOfA(arranger)
        var effects = try tear(&arranger, b, of: group, to: centre(ra), [.command], at: start)
        effects += arranger.handle(.tick, now: start + .milliseconds(450))
        #expect(!previews(effects).contains { if case .swap = $0 { true } else { false } }, "a swap was offered: \(previews(effects))")
    }

    @Test func shiftBypassesTheDockToTheFloat() throws {
        let start = ContinuousClock.now
        var (arranger, group, _, content) = try bareGroup(at: start)
        let ra = try tileOfA(arranger)
        // ⇧ over a's edge band: no Dock, the float at the clamped landing frame.
        var effects: [ArrangerEffect]
        let point = Point(x: ra.minX + 0.1 * ra.width, y: ra.midY)
        let expected = Planner.clamp(landing(arranger, b, content: content, at: point), into: area)
        effects = try tear(&arranger, b, of: group, to: point, [.shift], at: start + .seconds(1))
        effects += arranger.handle(.tick, now: start + .seconds(1) + DragSession.dwell)
        #expect(previews(effects) == [.clamp(expected)], "⇧ did not bypass: \(previews(effects))")
        _ = arranger.handle(pointer(.up, point.x, point.y, [.shift]), now: start + .seconds(2))
        #expect(arranger.world[mainKey]?.desktop.frame(of: b) == expected)
    }

    @Test func tearingTheSelectedTabSelectsItsRightNeighbour() throws {
        let start = ContinuousClock.now
        var (arranger, group, _, _) = try bareGroup(at: start, withA: true)  // [b, f, a]
        try arranger.world.edit(mainKey, history: &arranger.history) { desk, _ throws(LayoutError) in try desk.tree.selectTab(f) }
        _ = arranger.handle(.gap(8), now: start)  // re-plans, sends the strip
        let own = try ownTile(arranger, group)
        _ = try tear(&arranger, f, of: group, to: centre(own), at: start)
        let up = arranger.handle(pointer(.up, own.midX, own.midY), now: start + .milliseconds(200))
        #expect(selected(arranger, group) == a, "the right neighbour was not selected")
        #expect(arranger.world[mainKey]?.tree.node(group.node) == .tabs(windows: [b, a], selected: 1))
        #expect(announcements(up) == [.movedOut(dissolved: false)])
    }
}

/// UI-SPEC Surface 4: Esc cancels a tear-off; a lost mouse-up never commits one (T-07-18).
@Suite struct ArrangerTearOffCancelTests {
    @Test func cancelTearOffEndsTheSessionAndTheRestOfThePressChangesNothing() throws {
        let start = ContinuousClock.now
        var (arranger, group, _, _) = try bareGroup(at: start)
        let before = arranger.world
        _ = try tear(&arranger, b, of: group, to: Point(x: 1200, y: 500), at: start)
        let tick = arranger.handle(.tick, now: start + DragSession.dwell)
        try #require(!previews(tick).isEmpty, "no landing preview: \(tick)")
        let cancel = arranger.handle(.tab(.cancelTearOff, ready: true), now: start + .milliseconds(200))
        #expect(cancel.contains(.preview(nil, displayUUID: "main")), "the preview was not withdrawn: \(cancel)")
        #expect(ghosts(cancel) == [nil])
        #expect(announcements(cancel) == [.tearOffCanceled])
        #expect(cancel.contains(.info("group \(group.node): tear-off canceled (esc)")))
        #expect(arranger.drag == nil)
        var rest = arranger.handle(pointer(.dragged, 1000, 600), now: start + .milliseconds(300))
        rest += arranger.handle(pointer(.up, 1000, 600), now: start + .milliseconds(400))
        #expect(rest.isEmpty, "the rest of the press did something: \(rest)")
        #expect(arranger.world == before)
    }

    @Test func aNewPressClearsAStaleTearOffAndItsGhostWithNoCommit() throws {
        let start = ContinuousClock.now
        var (arranger, group, _, _) = try bareGroup(at: start)
        let before = arranger.world
        _ = try tear(&arranger, b, of: group, to: Point(x: 1200, y: 500), at: start)
        _ = arranger.handle(.tick, now: start + DragSession.dwell)
        let down = arranger.handle(pointer(.down, 1200, 500), now: start + .seconds(1))  // the mouse-up was lost
        #expect(ghosts(down) == [nil], "the ghost stayed: \(down)")
        #expect(announcements(down).isEmpty)
        #expect(arranger.drag == nil && arranger.world == before)
        // A stale press that never left the strip is gone too.
        let strip = try stripRect(arranger, group)
        _ = arranger.handle(tabPress(b, at: centre(strip)), now: start + .seconds(2))
        _ = arranger.handle(pointer(.down, 100, 100), now: start + .seconds(3))
        _ = arranger.handle(pointer(.dragged, 1200, 500), now: start + .seconds(3))
        #expect(arranger.drag == nil, "a stale tab press tore off")
    }
}

// MARK: Move Out of Group and Close Tab (07-08, D-11, TABS-06)

/// D-11 landing rule and Move Out of Group from the tab context menu.
@Suite struct ArrangerTabsMoveOutTests {
    private let visible = Rect(x: 0, y: 25, width: 1440, height: 875)

    @Test func theMovedOutWindowLandsEightPointsRightOfTheGroupTopsAligned() {
        let frame = Arranger.moveOutFrame(size: Size(width: 400, height: 300), group: Rect(x: 100, y: 100, width: 800, height: 600), area: visible)
        #expect(frame == Rect(x: 908, y: 100, width: 400, height: 300))
    }

    @Test func withNoRoomOnTheRightItLandsEightPointsLeft() {
        let frame = Arranger.moveOutFrame(size: Size(width: 400, height: 300), group: Rect(x: 900, y: 100, width: 500, height: 600), area: visible)
        #expect(frame == Rect(x: 492, y: 100, width: 400, height: 300))
    }

    @Test func withNoRoomOnEitherSideItCascadesThenClamps() {
        let frame = Arranger.moveOutFrame(size: Size(width: 400, height: 400), group: Rect(x: 300, y: 600, width: 800, height: 300), area: visible)
        #expect(frame == Rect(x: 324, y: 500, width: 400, height: 400), "cascade (324, 624) clamped up to the visible frame's bottom")
    }

    @Test func moveOutFloatsTheMemberBesideTheGroupInOneUndoStep() throws {
        let start = ContinuousClock.now
        var (arranger, group, frame, content) = try bareGroup(at: start, withA: true)  // [b, f, a], a selected
        let size = arranger.wantedFrames[b.identity]?.size ?? content.size
        let expected = Arranger.moveOutFrame(size: size, group: frame, area: area)
        let depth = arranger.history.depth(for: mainKey), grouped = arranger.world
        let effects = arranger.handle(.tab(.moveOut(b, via: .menu), ready: true), now: start + .seconds(1))
        let desk = try #require(arranger.world[mainKey])
        #expect(desk.desktop.frame(of: b) == expected, "b floats at \(String(describing: desk.desktop.frame(of: b)))")
        #expect(desk.tree.node(group.node) == .tabs(windows: [f, a], selected: 1), "the group lost more than b")
        #expect(arranger.history.depth(for: mainKey) == depth + 1, "Move Out is not one undo step")
        #expect(announcements(effects) == [.movedOut(dissolved: false)])
        #expect(commands(effects).contains(.raise(b)) && commands(effects).contains(.focus(b)))
        #expect(effects.contains(.info("group \(group.node): \(b) moved out via menu, landed floating")))
        _ = arranger.handle(.command(.undo, focused: b), now: start + .seconds(2))
        #expect(arranger.world[mainKey]?.tree == grouped[mainKey]?.tree, "Undo did not restore the group")
        #expect(arranger.world[mainKey]?.desktop.contains(b) == false)
    }

    @Test func movingOutTheSelectedMemberSelectsTheLeftNeighbourWhenItWasLast() throws {
        let start = ContinuousClock.now
        var (arranger, group, _, _) = try bareGroup(at: start, withA: true)  // [b, f, a], a selected
        _ = arranger.handle(.tab(.moveOut(a, via: .menu), ready: true), now: start + .seconds(1))
        #expect(arranger.world[mainKey]?.tree.node(group.node) == .tabs(windows: [b, f], selected: 1))
        #expect(arranger.world[mainKey]?.desktop.contains(a) == true)
    }

    @Test func movingOutOfATwoTabGroupDissolvesIt() throws {
        let start = ContinuousClock.now
        var (arranger, group, _, _) = try bareGroup(at: start)  // [b, f], f selected
        let effects = arranger.handle(.tab(.moveOut(f, via: .menu), ready: true), now: start + .seconds(1))
        #expect(arranger.world[mainKey]?.tree.node(group.node) == .panel(b))
        #expect(announcements(effects) == [.movedOut(dissolved: true)])
    }

    @Test(arguments: [true, false])
    func aRefusedMoveOutBeepsAndChangesNothing(paused: Bool) throws {
        let start = ContinuousClock.now
        var (arranger, _, _, _) = try bareGroup(at: start)
        if paused { _ = arranger.handle(.setPaused(.user, true), now: start) }
        let before = arranger.world
        let effects = arranger.handle(.tab(.moveOut(b, via: .menu), ready: paused), now: start)
        #expect(effects.contains(.beep) && effects.contains(.tabAnnouncement(.refused(paused ? .paused : .notReady))))
        #expect(arranger.world == before)
    }
}

/// TABS-06: Close Tab closes one member through the close queue, shown first when hidden, and stops at a prompt.
@Suite struct ArrangerTabsCloseTabTests {
    @Test func closeTabOnTheSelectedMemberClosesItAtOnceAndTheNeighbourIsSelected() throws {
        let start = ContinuousClock.now
        var (arranger, group, _, content) = try bareGroup(at: start, withA: true)  // [b, f, a], a selected
        let effects = arranger.handle(.tab(.closeTab(a), ready: true), now: start)
        #expect(closes(effects) == [a])
        let closed = arranger.handle(.event(.windowDestroyed(a)), now: start + .milliseconds(100))
        #expect(selected(arranger, group) == f)
        #expect(commands(closed).contains(.setFrame(f, content)), "f was not written into the content rect: \(commands(closed))")
        #expect(closes(closed).isEmpty && arranger.tabs.closeQueue == nil, "Close Tab closed more than one window")
    }

    @Test func closeTabOnAHiddenMemberShowsItFirstThenCloses() throws {
        let start = ContinuousClock.now
        var (arranger, group, _, content) = try bareGroup(at: start, withA: true)
        let effects = arranger.handle(.tab(.closeTab(b), ready: true), now: start)
        #expect(closes(effects).isEmpty, "a hidden member was closed before it was shown")
        #expect(commands(effects).contains(.setFrame(b, content)) && arranger.tabs.pendingReveal?.revealed == b)
        #expect(selected(arranger, group) == b)
        let shown = arranger.handle(.event(.frameApplied(b, requested: content, actual: content)), now: start + .milliseconds(100))
        #expect(closes(shown) == [b])
    }

    @Test func aMemberStillOpenAfterTheConfirmationStaysSelectedAndNothingMoreHappens() throws {
        let start = ContinuousClock.now
        var (arranger, group, _, _) = try bareGroup(at: start, withA: true)
        _ = arranger.handle(.tab(.closeTab(a), ready: true), now: start)
        _ = arranger.handle(.tick, now: start + Arranger.closeConfirmation)
        let stop = arranger.handle(.closePrompt(a, showing: false), now: start + Arranger.closeConfirmation)
        #expect(announcements(stop) == [.didNotClose(a)])
        #expect(closes(stop).isEmpty && selected(arranger, group) == a)
        #expect(arranger.tabs.closeQueue == nil, "a resumable list was kept")
        let later = arranger.handle(.tick, now: start + .seconds(3))
        #expect(announcements(later).isEmpty && closes(later).isEmpty)
    }

    @Test func closingOneOfTwoTabsAnnouncesTheDissolve() throws {
        let start = ContinuousClock.now
        var (arranger, group, _, _) = try bareGroup(at: start)  // [b, f], f selected
        _ = arranger.handle(.tab(.closeTab(f), ready: true), now: start)
        let closed = arranger.handle(.event(.windowDestroyed(f)), now: start + .milliseconds(100))
        #expect(arranger.world[mainKey]?.tree.node(group.node) == .panel(b))
        #expect(closed.contains(.tabAnnouncement(.ended)), "Close Tab did not announce the dissolve: \(closed)")
    }

    @Test(arguments: [true, false])
    func aRefusedCloseTabBeepsAndSendsNothing(paused: Bool) throws {
        let start = ContinuousClock.now
        var (arranger, _, _, _) = try bareGroup(at: start)
        if paused { _ = arranger.handle(.setPaused(.user, true), now: start) }
        let before = arranger.world
        let effects = arranger.handle(.tab(.closeTab(f), ready: paused), now: start)
        #expect(effects.contains(.beep) && effects.contains(.tabAnnouncement(.refused(paused ? .paused : .notReady))))
        #expect(commands(effects).isEmpty && arranger.world == before && arranger.tabs.closeQueue == nil)
    }
}

/// UI-SPEC Surface 7: Next Tab, Previous Tab and Move Out of Group act on the focused window's group.
@Suite struct ArrangerTabCommandTests {
    @Test func nextTabWrapsFromTheLastTabAndPreviousTabWrapsBack() throws {
        let start = ContinuousClock.now
        var (arranger, group, _, _) = try bareGroup(at: start, withA: true)  // [b, f, a], a selected
        let next = arranger.handle(.command(.tabs(.next), focused: a), now: start)
        #expect(selected(arranger, group) == b, "next from the last tab did not wrap to the first")
        #expect(next.contains(.tabAnnouncement(.selected(index: 1, count: 3))))
        #expect(commands(next).contains(.focus(b)), "the reveal flow did not focus b")
        let previous = arranger.handle(.command(.tabs(.previous), focused: b), now: start + .seconds(2))
        #expect(selected(arranger, group) == a, "previous from the first tab did not wrap to the last")
        #expect(previous.contains(.tabAnnouncement(.selected(index: 3, count: 3))))
    }

    @Test func aTabCommandWithNoGroupBeepsAnnouncesAndLogs() throws {
        let start = ContinuousClock.now
        var (arranger, _, _, _) = try bareGroup(at: start)  // [b, f]; a docked alone
        for focused in [a, nil] as [WindowRef?] {
            #expect(arranger.handle(.command(.tabs(.next), focused: focused), now: start)
                == [.beep, .tabAnnouncement(.refused(.notInGroup)), .info("refused next tab: not in a tab group")])
        }
        _ = arranger.handle(.setPaused(.user, true), now: start)
        #expect(arranger.handle(.command(.tabs(.moveOut), focused: f), now: start)
            == [.beep, .tabAnnouncement(.refused(.paused)), .info("refused move out of group: arranging is paused")])
        #expect(arranger.handle(.tab(.command(.previous, focused: f, via: .url), ready: false), now: start).contains(
            .tabAnnouncement(.refused(.paused))), "paused is checked before ready, as in select")
    }

    @Test func aTabCommandWithoutAccessibilityIsRefusedNotReady() throws {
        let start = ContinuousClock.now
        var (arranger, _, _, _) = try bareGroup(at: start)
        #expect(arranger.handle(.tab(.command(.next, focused: f, via: .menu), ready: false), now: start)
            == [.beep, .tabAnnouncement(.refused(.notReady)), .info("refused next tab: not ready")])
    }

    @Test func tabCommandsAreAvailableOnlyForAGroupedFocusedWindowUnpausedAndReady() throws {
        let start = ContinuousClock.now
        var (arranger, _, _, _) = try bareGroup(at: start)
        for command in [TabCommand.next, .previous, .moveOut] {
            #expect(arranger.availability(.tabs(command), context: CommandContext(focused: f, ready: true)))
            #expect(arranger.availability(.tabs(command), context: CommandContext(focused: b, ready: true)), "a hidden member is in the group too")
            #expect(!arranger.availability(.tabs(command), context: CommandContext(focused: a, ready: true)))
            #expect(!arranger.availability(.tabs(command), context: CommandContext(focused: nil, ready: true)))
            #expect(!arranger.availability(.tabs(command), context: CommandContext(focused: f, ready: false)))
        }
        _ = arranger.handle(.setPaused(.user, true), now: start)
        #expect(!arranger.availability(.tabs(.next), context: CommandContext(focused: f, ready: true)))
    }

    @Test func tabGroupCountsCountsDockedAndFloatingGroupsOnEveryDeskAndEveryMember() throws {
        let start = ContinuousClock.now
        #expect(Arranger().tabGroupCounts() == (groups: 0, tabs: 0))
        var (arranger, _, _, _) = try bareGroup(at: start, withA: true)  // docked [b, f, a]
        #expect(arranger.tabGroupCounts() == (groups: 1, tabs: 3))
        let c = window(4), d = window(5), e = window(6), g = window(7)
        let away = DeskKey(displayUUID: "away", spaceID: nil)
        try arranger.world.addDesk(away)
        try arranger.world.reflow(away) { desk, ids throws(LayoutError) in
            for (window, frame) in [(c, frameA), (d, frameB), (e, smallF), (g, frameA)] { try desk.desktop.add(window, frame: frame) }
            try desk.desktop.group(id: try ids.make(), target: c, adding: d)
            try desk.desktop.group(id: try ids.make(), target: e, adding: g)
        }
        #expect(arranger.tabGroupCounts() == (groups: 3, tabs: 7), "a dormant desk's floating groups count too")
    }

    @Test func moveOutOfGroupMovesTheFocusedMemberOutViaTheSource() throws {
        let start = ContinuousClock.now
        var (arranger, group, _, _) = try bareGroup(at: start, withA: true)  // [b, f, a], a selected
        let effects = arranger.handle(.tab(.command(.moveOut, focused: a, via: .url), ready: true), now: start + .seconds(1))
        #expect(arranger.world[mainKey]?.desktop.contains(a) == true, "a does not float")
        #expect(announcements(effects) == [.movedOut(dissolved: false)])
        #expect(effects.contains(.info("group \(group.node): \(a) moved out via url, landed floating")))
        let viaHotkey = arranger.handle(.command(.tabs(.moveOut), focused: f), now: start + .seconds(2))
        #expect(viaHotkey.contains(.info("group \(group.node): \(f) moved out via hotkey, landed floating")))
    }
}

/// D-07, RESEARCH Pitfall 3: safety paths for hidden tabs (quit, Restore All, crash relaunch).
@Suite struct ArrangerTabSafetyTests {
    @Test func groupContentRectsHoldsEveryMemberOfADockedGroupOnADeskAtHome() throws {
        let start = ContinuousClock.now
        let (arranger, _, _, content) = try bareGroup(at: start, withA: true)  // [b, f, a], a selected, b and f parked
        let rects = arranger.groupContentRects()
        #expect(rects == [a.identity: content, b.identity: content, f.identity: content])
        #expect(arranger.homeTiles().isEmpty, "the desk is at home, so homeTiles alone gives no target for the hidden members")
        #expect(arranger.selectedGroupMembers() == [a])
    }

    @Test func groupContentRectsHoldsEveryMemberOfAFloatingGroup() throws {
        let start = ContinuousClock.now
        let (arranger, _, content) = try bareFloatingGroup(at: start)  // [t, f], f selected, t parked
        #expect(arranger.groupContentRects() == [t.identity: content, f.identity: content])
        #expect(arranger.selectedGroupMembers() == [f])
    }

    /// 07-05: while the selected member is minimised the engine stops recording the hidden one as parked, and the
    /// leaf has no planned rect. The quit restore must still bring the hidden one on screen: the stranded rule does.
    @Test func whileTheSelectedIsMinimisedTheQuitPlanStillBringsTheHiddenMemberOnScreen() throws {
        let start = ContinuousClock.now
        var (arranger, group, _, content) = try bareGroup(at: start)  // [b, f], f selected
        _ = arranger.handle(.tab(.minimizeGroup(group), ready: true), now: start)
        _ = arranger.handle(.event(.windowStateChanged(f, .absent)), now: start)
        try #require(!arranger.isParked(b), "the 07-05 premise changed")
        #expect(arranger.groupContentRects()[b.identity] == nil, "the absent selected member's leaf is planned")
        #expect(arranger.selectedGroupMembers().isEmpty, "a minimised selected member is raised at quit")
        let parked = info(3, frame: Rect(x: area.maxX - 1, y: area.maxY - 1, width: content.width, height: content.height))
        let groups = arranger.groupContentRects()
        let plan = Recovery.terminationPlan(
            windows: [parked], homeFrames: arranger.homeFrames, displays: [mainDisplay], docked: Set(groups.keys).union([b.identity]),
            homeTiles: arranger.homeTiles().merging(groups) { $1 })
        let back = try #require(plan[b], "the parked hidden member is left off screen")
        #expect(!Recovery.isStranded(back, displays: [mainDisplay]))
    }

    @Test func groupContentRectsUsesTheHomeViewWhileZoomedIn() throws {
        let start = ContinuousClock.now
        var (arranger, group, _, content) = try bareGroup(at: start, zoom: true)
        let leafA = try #require(arranger.world[mainKey]?.tree.leaf(containing: a))
        _ = arranger.handle(.zoomTo(.node(leafA), displayUUID: "main"), now: start)
        #expect(arranger.groupContentRects()[b.identity] == content, "group \(group.node) was not planned at home")
    }

    /// The cascade Restore All gives the `n`th non-selected member: content size, top-left `n` × 24 pt from the group's.
    private func cascade(_ n: Int, from frame: Rect, content: Rect, into visible: Rect) -> Rect {
        Planner.clamp(Rect(x: frame.minX + 24 * Double(n), y: frame.minY + 24 * Double(n), width: content.width, height: content.height), into: visible)
    }

    @Test func restoreAllDissolvesADockedGroupTheSelectedKeepsTheTileTheOthersCascade() throws {
        let start = ContinuousClock.now
        var (arranger, group, frame, content) = try bareGroup(at: start, withA: true)  // [b, f, a], a selected
        let depth = arranger.history.depth(for: mainKey)
        let effects = arranger.handle(.command(.restoreAll, focused: nil), now: start + .seconds(1))
        let desk = try #require(arranger.world[mainKey])
        #expect(desk.tree.node(group.node) == .panel(a), "a does not keep the group's tile")
        #expect(desk.desktop.frame(of: b) == cascade(1, from: frame, content: content, into: area))
        #expect(desk.desktop.frame(of: f) == cascade(2, from: frame, content: content, into: area))
        #expect(![a, b, f].contains { arranger.isParked($0) }, "a member is still parked")
        #expect(arranger.history.depth(for: mainKey) == depth + 1, "Restore All is not one undo step on the desk")
        #expect(effects.contains(.info("restore all: dissolved 1 groups, 2 windows brought back")))
    }

    @Test func restoreAllDissolvesAFloatingGroupTheSelectedTakesTheWholeFrame() throws {
        let start = ContinuousClock.now
        var (arranger, _, content) = try bareFloatingGroup(at: start)  // [t, f] at tFrame, f selected
        _ = arranger.handle(.command(.restoreAll, focused: nil), now: start + .seconds(1))
        let desk = try #require(arranger.world[mainKey])
        #expect(desk.desktop.groups.isEmpty)
        #expect(desk.desktop.frame(of: f) == tFrame, "the band did not return to the selected member")
        #expect(desk.desktop.frame(of: t) == cascade(1, from: tFrame, content: content, into: area))
        #expect(!arranger.isParked(t))
    }

    @Test func restoreAllCountsTheMembersBroughtBackOnceEvenWhenStranded() throws {
        let start = ContinuousClock.now
        var (arranger, _, frame, content) = try bareGroup(at: start, withA: true)
        _ = arranger.handle(.event(.windowMoved(b, Rect(x: 5000, y: 5000, width: content.width, height: content.height))), now: start)
        let effects = arranger.handle(.command(.restoreAll, focused: nil), now: start + .seconds(1))
        #expect(effects.contains(.notice(.restored(count: 2))), "N6 count: \(effects)")
        #expect(arranger.world[mainKey]?.desktop.frame(of: b) == cascade(1, from: frame, content: content, into: area),
            "the rescue moved the stranded member away from its cascade")
    }

    @Test func undoAfterRestoreAllReformsTheGroupWithTheSameSelection() throws {
        let start = ContinuousClock.now
        var (arranger, group, _, _) = try bareGroup(at: start, withA: true)
        _ = arranger.handle(.command(.restoreAll, focused: nil), now: start + .seconds(1))
        _ = arranger.handle(.command(.undo, focused: a), now: start + .seconds(2))
        #expect(arranger.world[mainKey]?.tree.node(group.node) == .tabs(windows: [b, f, a], selected: 2), "Undo did not re-form the group")
        #expect(arranger.isParked(b) && arranger.isParked(f), "the hidden members did not re-park")
    }

    /// A fresh Arranger on a `mode` launch restoring `saved`, whose first complete inventory tracks only `kept` (the CG
    /// list holds only them, so every other saved window is gone).
    private func relaunch(_ saved: World, keeping kept: [WindowInfo], mode: LaunchMode = .normal) -> (Arranger, [ArrangerEffect]) {
        var arranger = Arranger()
        _ = arranger.handle(.launch(mode), now: .now)
        _ = arranger.handle(.restore(saved, homeFrames: [:]), now: .now)
        let live = kept.map { CGWindowEntry(windowID: $0.window.windowID, pid: $0.window.pid, bounds: $0.frame, layer: 0, onScreen: true, alpha: 1) }
        let inventory = WindowInventory(displays: [mainDisplay], windows: kept, initialRefreshComplete: true, liveWindows: live)
        let effects = arranger.handle(.inventory(inventory), now: .now)
        return (arranger, effects)
    }

    /// `arranger` once every saved window that did not come back has expired (D-12).
    private func pastPlaceholderExpiry(_ arranger: Arranger) -> Arranger {
        var arranger = arranger
        _ = arranger.handle(.tick, now: .now + Arranger.neverOpenedWait)
        return arranger
    }

    @Test func aCrashRelaunchRescuesTheParkedMemberThenReformsTheGroupAndParksItAgain() async throws {
        var (harness, plan) = try await docked()
        await groupFWithB(&harness, try #require(plan.frames[b]))  // [b, f], f selected, b parked
        let leaf = try #require(harness.arranger.world[mainKey]?.tree.leaf(containing: b))
        let parked = try #require(await harness.frame(b))
        try #require(harness.arranger.isParked(b) && Recovery.isStranded(parked, displays: [mainDisplay]), "b is not parked off screen")
        let snapshot = harness.arranger.snapshot
        let content = try #require(harness.arranger.groupContentRects()[b.identity])

        var restored = Arranger()
        _ = restored.handle(.launch(.recovery), now: .now)
        _ = restored.handle(.restore(snapshot.world, homeFrames: snapshot.homeFrames), now: .now)
        let effects = restored.handle(.inventory(await harness.fake.inventory()), now: .now)
        let rescue = try #require(effects.first { if case .perform = $0 { true } else { false } }, "nothing was sent: \(effects)")
        guard case .perform(let first) = rescue, case .setFrame(b, let back)? = first.first(where: { $0.window == b }) else {
            Issue.record("the first perform does not move b: \(rescue)")
            return
        }
        #expect(!Recovery.isStranded(back, displays: [mainDisplay]), "b was not brought on screen: \(back)")
        #expect(effects.contains(.notice(.crashRecovered(unplaced: 0))), "N2: \(effects)")
        #expect(restored.world[mainKey]?.tree.node(leaf) == .tabs(windows: [b, f], selected: 1), "the group did not re-form with f selected")
        #expect(parks(effects).contains(.park(b, displayUUID: "main", size: content.size)), "b was not parked again at the content size: \(parks(effects))")
        #expect(restored.isParked(b))
    }

    @Test func aRelaunchWithAHiddenMemberGoneReformsWithTheRestAndLogs() throws {
        let (source, group, _, _) = try bareGroup(at: .now, withA: true)  // [b, f, a], a selected
        let (relaunched, effects) = relaunch(source.world, keeping: [info(1, frame: frameA), info(2, frame: smallF)])  // b gone
        #expect(relaunched.world[mainKey]?.tree.node(group.node) == .tabs(windows: [b, f, a], selected: 2), "b waits in its position")
        #expect(!effects.contains { if case .notice = $0 { true } else { false } }, "a relaunch with a member gone is not silent")
        let arranger = pastPlaceholderExpiry(relaunched)
        #expect(arranger.world[mainKey]?.tree.node(group.node) == .tabs(windows: [f, a], selected: 1), "the group did not keep a selected")
    }

    @Test func aRelaunchWithTheSelectedMemberGoneSelectsItsRightNeighbour() throws {
        let (source, group, _, _) = try bareGroup(at: .now, withA: true)  // [b, f, a]
        var saved = source.world
        try saved.reflow(mainKey) { desk, _ throws(LayoutError) in try desk.tree.selectTab(f) }
        let (relaunched, _) = relaunch(saved, keeping: [info(1, frame: frameA), info(3, frame: frameB)])  // f gone
        #expect(relaunched.world[mainKey]?.tree.node(group.node) == .tabs(windows: [b, f, a], selected: 2), "a, f's right neighbour, is not selected")
        let arranger = pastPlaceholderExpiry(relaunched)
        #expect(arranger.world[mainKey]?.tree.node(group.node) == .tabs(windows: [b, a], selected: 1), "a, f's right neighbour, is not selected")
    }

    @Test func aTwoMemberGroupWithOneGoneDissolvesDockedAndFloating() throws {
        let (dockedSource, group, _, _) = try bareGroup(at: .now)  // [b, f], f selected
        let docked = pastPlaceholderExpiry(relaunch(dockedSource.world, keeping: [info(1, frame: frameA), info(3, frame: frameB)]).0)  // f gone
        #expect(docked.world[mainKey]?.tree.node(group.node) == .panel(b), "the docked group did not dissolve into a plain panel")
        let (floatingSource, _, _) = try bareFloatingGroup(at: .now)  // [t, f]
        let floating = pastPlaceholderExpiry(relaunch(floatingSource.world, keeping: [info(5, frame: tFrame)]).0)  // f gone
        let desktop = try #require(floating.world[mainKey]?.desktop)
        #expect(desktop.groups.isEmpty && desktop.contains(t), "the floating group did not dissolve into a floater")
    }

    @Test func aGroupWithNoMemberLeftKeepsItsLeafUntilExpiryLikeAnyAbsentWindow() throws {
        let (source, group, _, _) = try bareGroup(at: .now)  // [b, f]
        let (relaunched, effects) = relaunch(source.world, keeping: [info(1, frame: frameA)])
        #expect(relaunched.world[mainKey]?.tree.node(group.node) == .tabs(windows: [b, f], selected: 1))
        let arranger = pastPlaceholderExpiry(relaunched)
        #expect(arranger.world[mainKey]?.tree.node(group.node) == nil)
        #expect(arranger.world[mainKey]?.tree.windows == [a])
        #expect(!effects.contains { if case .fault = $0 { true } else { false } }, "\(effects)")
    }
}

// MARK: Groups on the zoom stage (07-11)

private func cameraMoves(_ effects: [ArrangerEffect]) -> [CameraMove] {
    effects.compactMap { if case .cameraMove(let move) = $0 { move } else { nil } }
}

/// UI-SPEC Surface 6: the stage draws a group as its selected member's tile plus one strip; hidden members never.
@Suite struct ArrangerTabStageTests {
    @Test func aCameraMoveHasOneTileForTheSelectedMemberAndOneStripPerGroup() throws {
        let start = ContinuousClock.now
        var (arranger, group, frame, _) = try bareGroup(at: start, zoom: true)  // [b, f], f selected, b parked
        let move = try #require(cameraMoves(arranger.handle(.zoomTo(.node(group.node), displayUUID: "main"), now: start)).first)

        #expect(!move.tiles.contains { $0.window == b }, "the hidden member got a tile: \(move.tiles)")
        let tile = try #require(move.tiles.first { $0.window == f })
        #expect(tile.kind == .stay)
        let strip = try #require(move.strips.first, "no strip: \(move)")
        #expect(move.strips.count == 1)
        #expect(strip.group == group)
        #expect(strip.members == [b, f] && strip.selected == 1)
        #expect(strip.kind == .stay)
        #expect(strip.start == TabBand.strip(of: frame), "the strip did not start at the group frame's top")
        #expect(strip.end == TabBand.strip(of: TabBand.frame(ofContent: tile.end)), "the strip did not end above the tile")
    }
}

/// UI-SPEC Surface 6, collapsed group: one block, for the selected member, carrying the group's size.
@Suite struct ArrangerTabCollapsedBlockTests {
    @Test func aCollapsedGroupIsOneBlockForItsSelectedMemberWithItsSize() throws {
        let start = ContinuousClock.now
        var (arranger, rb) = try bareDocked(aMinimum: Size(width: 100, height: 840), zoom: true)  // fits a tile, not a content rect
        _ = drag(&arranger, a, from: frameA, to: centre(rb), at: start)
        _ = arranger.handle(.tick, now: start + .milliseconds(400))
        let up = arranger.handle(pointer(.up, rb.midX, rb.midY), now: start + .milliseconds(450))
        let blocks = up.compactMap { if case .collapsedBlocks(let blocks, "main") = $0 { blocks } else { nil } }.last
        #expect(blocks?.map(\.window) == [a], "not one block for the selected member: \(up)")
        #expect(blocks?.first?.groupSize == 2)
    }
}

/// UI-SPEC Surface 6, Snapshots: a tab in place is announced to the shell once, so it can be captured in the background.
@Suite struct ArrangerTabRevealedTests {
    private func revealed(_ effects: [ArrangerEffect]) -> [WindowRef] {
        effects.compactMap { if case .tabRevealed(let window) = $0 { window } else { nil } }
    }

    @Test func aMatchedReadBackEmitsTabRevealedOnce() throws {
        let start = ContinuousClock.now
        var (arranger, _, _, content) = try bareGroup(at: start)
        let select = arranger.handle(.tab(.select(b, via: .click), ready: true), now: start)
        #expect(revealed(select).isEmpty, "revealed before the read-back")
        let back = arranger.handle(.event(.frameApplied(b, requested: content, actual: content)), now: start + .milliseconds(40))
        #expect(revealed(back) == [b])
        #expect(revealed(arranger.handle(.event(.frameApplied(b, requested: content, actual: content)), now: start + .milliseconds(80))).isEmpty)
    }

    @Test func aRevealThatTimesOutEmitsNone() throws {
        let start = ContinuousClock.now
        var (arranger, _, _, _) = try bareGroup(at: start)
        _ = arranger.handle(.tab(.select(b, via: .click), ready: true), now: start)
        #expect(revealed(arranger.handle(.tick, now: start + .seconds(1))).isEmpty)
    }
}

// MARK: Code review 07 fixes

private func excluded(_ window: WindowRef, at frame: Rect) -> WindowInfo {
    WindowInfo(window: window, frame: frame, state: .present, displayUUID: "main", kind: .dockable, isExcluded: true)
}

private func parkedFrame(_ content: Rect) -> Rect {
    mainDisplay.parkedFrame(size: Size(width: content.width, height: content.height), among: [mainDisplay])
}

/// CR-01: excluding an app first writes its hidden tabs back on screen, then takes them out of their groups.
@Suite struct ArrangerTabExclusionTests {
    @Test func anExcludedHiddenDockedMemberComesBackAtTheContentRectOutOfItsGroup() throws {
        let start = ContinuousClock.now
        var (arranger, group, _, content) = try bareGroup(at: start)  // [b, f], f selected, b parked
        _ = arranger.handle(.event(.windowMoved(b, parkedFrame(content))), now: start)  // b's park echo
        _ = arranger.handle(.event(.windowMoved(f, content)), now: start)  // f's echo
        #expect(arranger.releaseFrames(forExcluding: ["com.example.other"]).isEmpty)
        #expect(arranger.releaseFrames(forExcluding: ["com.example.arranger"]) == [b: content], "the hidden member is not written back first")
        let effects = arranger.handle(.event(.windowChanged(excluded(b, at: parkedFrame(content)))), now: start + .seconds(2))
        let desk = try #require(arranger.world[mainKey])
        #expect(desk.tree.node(group.node) == .panel(f), "b is still in the group")
        #expect(desk.desktop.frame(of: b) == content, "b floats at its parked frame")
        #expect(arranger.tabGroup(holding: b) == nil && !arranger.isHiddenTab(b))
        #expect(!commands(effects).contains { $0.window == b }, "the excluded window was written: \(commands(effects))")
    }

    @Test func anExcludedHiddenFloatingMemberComesBackAtTheContentRectAndTheGroupDissolves() throws {
        let start = ContinuousClock.now
        var (arranger, _, content) = try bareFloatingGroup(at: start)  // [t, f], f selected, t parked
        _ = arranger.handle(.event(.windowMoved(t, parkedFrame(content))), now: start)
        #expect(arranger.releaseFrames(forExcluding: ["com.example.arranger"]) == [t: content], "the hidden member is not written back first")
        let effects = arranger.handle(.event(.windowChanged(excluded(t, at: parkedFrame(content)))), now: start + .seconds(2))
        let layer = try #require(arranger.world[mainKey]?.desktop)
        #expect(layer.groups.isEmpty, "the group left with one member did not dissolve")
        #expect(layer.frame(of: t) == content, "t floats at its parked frame")
        #expect(layer.frame(of: f) == tFrame, "the survivor did not take the whole frame")
        #expect(arranger.tabGroup(holding: t) == nil && !parks(effects).contains { $0.window == t })
        #expect(setFrames(effects)[f] == tFrame, "the survivor was not written into the group frame: \(effects)")
    }
}

/// WR-01: an app that snaps its size (whole character cells) still reveals; a failed reveal gives focus back.
@Suite struct ArrangerTabRevealToleranceTests {
    @Test func aReadBackAtTheOriginButSnappedShorterParksThePrevious() throws {
        let start = ContinuousClock.now
        var (arranger, group, _, content) = try bareGroup(at: start)
        _ = arranger.handle(.tab(.select(b, via: .click), ready: true), now: start)
        let snapped = Rect(x: content.x, y: content.y, width: content.width - 7, height: content.height - 10)
        let back = arranger.handle(.event(.frameApplied(b, requested: content, actual: snapped)), now: start + .milliseconds(40))
        #expect(parks(back) == [.park(f, displayUUID: "main", size: Size(width: content.width, height: content.height))], "\(back)")
        #expect(arranger.tabs.pendingReveal == nil && selected(arranger, group) == b)
        #expect(!arranger.handle(.tick, now: start + .seconds(2)).contains(.beep), "the snapped reveal timed out")
    }

    @Test func aReadBackFarLargerThanTheContentRectIsNoReveal() throws {
        let start = ContinuousClock.now
        var (arranger, _, _, content) = try bareGroup(at: start)
        _ = arranger.handle(.tab(.select(b, via: .click), ready: true), now: start)
        let refused = Rect(x: content.x, y: content.y, width: content.width, height: content.height + MinimumSizeLearner.refusalMargin + 8)
        #expect(parks(arranger.handle(.event(.frameApplied(b, requested: content, actual: refused)), now: start)).isEmpty)
        #expect(arranger.tabs.pendingReveal?.revealed == b)
    }

    @Test func aRevealThatTimesOutFocusesTheKeptMemberAgain() throws {
        let start = ContinuousClock.now
        var (arranger, group, _, _) = try bareGroup(at: start)
        #expect(commands(arranger.handle(.tab(.select(b, via: .click), ready: true), now: start)).contains(.focus(b)))
        let late = commands(arranger.handle(.tick, now: start + .seconds(1)))
        #expect(late.contains(.focus(f)), "f did not get focus back: \(late)")
        #expect(late.contains { if case .park(b, _, _) = $0 { true } else { false } }, "b was not parked again: \(late)")
        #expect(selected(arranger, group) == f)
    }
}

/// WR-03: a hidden member cannot be moved to another Space by a frame write, so a Space move never carries the group.
@Suite struct ArrangerTabSpaceRehomeTests {
    @Test func movingTheSelectedMemberToAnotherSpaceTakesItOutAloneAndTheRestStayOnTheOldDesk() throws {
        let start = ContinuousClock.now
        let spaced = DisplayInfo(uuid: "main", frame: mainDisplay.frame, visibleFrame: area, currentSpaceID: 1)
        let one = DeskKey(displayUUID: "main", spaceID: 1), two = DeskKey(displayUUID: "main", spaceID: 2)
        func onSpace(_ id: UInt32, _ frame: Rect, _ space: UInt64) -> WindowInfo {
            WindowInfo(window: window(id), frame: frame, state: .present, displayUUID: "main", kind: .dockable, spaces: [space])
        }
        var arranger = Arranger()
        let infos = [onSpace(1, frameA, 1), onSpace(2, smallF, 1), onSpace(3, frameB, 1)]
        _ = arranger.handle(.inventory(WindowInventory(displays: [spaced], windows: infos, initialRefreshComplete: true)), now: start)
        _ = arranger.handle(.command(.dock, focused: a), now: start)
        _ = arranger.handle(.command(.dock, focused: b), now: start)
        let leaf = try #require(arranger.world[one]?.tree.leaf(containing: b))
        try arranger.world.edit(one, history: &arranger.history) { desk, _ throws(LayoutError) in
            try desk.desktop.remove(f)
            try desk.tree.group(f, into: leaf)  // [b, f], f selected
        }
        _ = arranger.handle(.gap(8), now: start)
        try #require(arranger.isParked(b), "b was not parked")
        let away = Rect(x: 300, y: 200, width: 400, height: 300)
        _ = arranger.handle(.event(.windowChanged(onSpace(2, away, 2))), now: start + .seconds(1))
        #expect(arranger.world[one]?.tree.node(leaf) == .panel(b), "the hidden member did not keep the leaf on its own Space")
        #expect(arranger.world[two]?.desktop.groups.isEmpty == true, "the group followed to a Space its hidden member is not on")
        #expect(arranger.world[two]?.desktop.frame(of: f) == away && arranger.world[one]?.contains(f) == false)
        #expect(!arranger.isHiddenTab(b))
    }
}

/// WR-04: the window under the pointer is never parked before mouse-up, even when a tab switch hides it mid-drag.
@Suite struct ArrangerTabDragParkTests {
    @Test func aTabSwitchDuringAWholeGroupDragNeverParksTheDraggedWindow() throws {
        let start = ContinuousClock.now
        var (arranger, group, _, content) = try bareGroup(at: start)  // [b, f], f selected
        _ = drag(&arranger, f, from: content, to: Point(x: 1200, y: 600), at: start)
        try #require(arranger.drag?.window == f, "no drag session on f")
        let next = arranger.handle(.tab(.command(.next, focused: f, via: .hotkey), ready: true), now: start + .milliseconds(100))
        #expect(selected(arranger, group) == b, "the tab command did not select b: \(next)")
        let back = arranger.handle(.event(.frameApplied(b, requested: content, actual: content)), now: start + .milliseconds(140))
        #expect(!parks(back).contains { $0.window == f }, "the dragged window was parked: \(parks(back))")
        #expect(!arranger.isParked(f))
        #expect(!parks(arranger.handle(.gap(8), now: start + .milliseconds(200))).contains { $0.window == f }, "a later replan parked it")
    }
}

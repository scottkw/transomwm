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
        #expect(desk.desktop.contains(a), "⇧ did not undock")
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
    @Test(arguments: ["own tile", "Desktop tile", "collapsed target"])
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
        case "Desktop tile": centre(plan.desktopRect ?? area)
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
    at now: ContinuousClock.Instant, withA: Bool = false, zoom: Bool = false, displays: [DisplayInfo] = [mainDisplay]
) throws -> (Arranger, GroupKey, frame: Rect, content: Rect) {
    var arranger = Arranger()
    let infos = [info(1, frame: frameA), info(2, frame: smallF), info(3, frame: frameB)]
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

    @Test func aFocusWithin1sOfTheSelectedMemberGoingAbsentDoesNotSwitchTabs() throws {
        let start = ContinuousClock.now
        var (arranger, group, _, _) = try bareGroup(at: start)
        _ = arranger.handle(.event(.windowStateChanged(f, .absent)), now: start)
        _ = arranger.handle(.event(.windowFocused(b)), now: start + .milliseconds(500))
        #expect(selected(arranger, group) == f, "a focus after a minimise switched tabs")
        _ = arranger.handle(.event(.windowFocused(b)), now: start + .milliseconds(1500))
        #expect(selected(arranger, group) == b)
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

/// a, f, g and t floating on the main Desktop, nothing docked.
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

    @Test func theDesktopTilesOwnCentreFormsNothing() async throws {
        var harness = await floaters()
        let empty = Point(x: 380, y: 650)  // in the Desktop tile's centre zone, clear of every floater
        _ = await drag(&harness, f, from: smallF, to: empty)
        harness.now += .milliseconds(400)
        #expect(groupPreviews(await harness.send(.tick)).isEmpty)
        let depth = harness.arranger.history.depth(for: mainKey)
        await harness.send(pointer(.up, empty.x, empty.y))
        #expect(floatingGroups(harness).isEmpty)
        #expect(harness.arranger.history.depth(for: mainKey) == depth)
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
        let desktop = try #require(plan.desktopRect)
        let target = try #require(harness.arranger.world[mainKey]?.desktop.frame(of: t))
        try #require(desktop.contains(centre(target)), "t is not on the Desktop tile")
        _ = await drag(&harness, a, from: ra, to: centre(target))
        harness.now += .milliseconds(400)
        await harness.send(.tick)
        await harness.send(pointer(.up, target.midX, target.midY))
        let group = try #require(floatingGroups(harness).first)
        #expect(group.members == [t, a])
        #expect(harness.arranger.world[mainKey]?.tree.state(of: a) == nil, "a is still docked")
    }
}

/// The Planner side of floating groups: the selected member at the content rect, hidden members parked once at the content size.
@Suite struct FloatingGroupPlannerTests {
    private func groupedDesk(hidden: Bool = false) throws -> Desk {
        var desk = Desk()
        var ids = IDSource()
        try desk.tree.insert(a, at: .left, of: .desktop, ids: &ids)
        try desk.desktop.add(t, frame: tFrame)
        try desk.desktop.group(id: try ids.make(), target: t, adding: f)
        if hidden { try desk.tree.setDesktopHidden(true) }
        return desk
    }

    @Test func hiddenMembersParkAtTheContentSize() throws {
        let plan = try Planner.plan(desk: try groupedDesk(), area: area, gap: 8, mins: [:])
        let content = TabBand.content(of: tFrame)
        #expect(plan.parks == [t])
        #expect(plan.parkSizes[t] == Size(width: content.width, height: content.height))
        #expect(plan.frames[t] == nil)
    }

    @Test func aHiddenDesktopParksEveryMemberOnce() throws {
        let plan = try Planner.plan(desk: try groupedDesk(hidden: true), area: area, gap: 8, mins: [:])
        let content = TabBand.content(of: tFrame)
        #expect(plan.parks.filter { $0 == t }.count == 1 && plan.parks.filter { $0 == f }.count == 1, "parks: \(plan.parks)")
        #expect(plan.parkSizes[t] == Size(width: content.width, height: content.height))
        #expect(plan.parkSizes[f] == nil, "the selected member parks at its own size")
    }

    @Test func theSelectedMembersBandCountsTowardTheDesktopMinimum() throws {
        var desk = Desk()
        var ids = IDSource()
        try desk.tree.insert(a, at: .top, of: .desktop, ids: &ids)
        try desk.desktop.add(t, frame: tFrame)
        try desk.desktop.group(id: try ids.make(), target: t, adding: f)
        let mins = [f: Size(width: 100, height: 600), a: Size(width: 100, height: 100)]
        let grouped = try #require(try Planner.plan(desk: desk, area: area, gap: 8, mins: mins).desktopRect)
        #expect(grouped.height >= 632, "the band did not raise the Desktop minimum: \(grouped)")
        var plain = Desk()
        try plain.tree.insert(a, at: .top, of: .desktop, ids: &ids)
        try plain.desktop.add(f, frame: tFrame)
        let alone = try #require(try Planner.plan(desk: plain, area: area, gap: 8, mins: mins).desktopRect)
        #expect(alone.height < 632, "a plain floater got the band: \(alone)")
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

/// a docked left of the Desktop, t and f floating on it, both focused (t last), then grouped as [t, f] with f selected.
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

/// UI-SPEC Surface 3 "What the user never sees": hidden members stay out of focus moves; a hidden Desktop parks the group.
@Suite struct FloatingGroupVisibilityTests {
    @Test func aFocusMoveOntoTheDesktopPicksTheSelectedMemberNotAHiddenOne() throws {
        let start = ContinuousClock.now
        var (arranger, _) = try dockedBesideFloatingGroup(at: start)
        let effects = arranger.handle(.command(.focus(.right), focused: a), now: start)
        #expect(commands(effects) == [.focus(f)], "the focus move picked \(commands(effects))")
    }

    @Test func aHiddenDesktopParksEveryMemberAndShowingItBringsBackOnlyTheSelected() throws {
        let start = ContinuousClock.now
        var (arranger, _) = try dockedBesideFloatingGroup(at: start)
        // t's frame crosses a's tile, so the group's content rect is clamped into the Desktop.
        let desk = try #require(arranger.world[mainKey])
        let desktop = try #require(try Planner.plan(desk: desk, area: area, gap: 8, mins: [:]).desktopRect)
        let content = Planner.clamp(TabBand.content(of: tFrame), into: desktop)
        _ = arranger.handle(.event(.windowMoved(f, content)), now: start)  // f's echo
        let hide = arranger.handle(.command(.toggleDesktop, focused: a), now: start)
        #expect(arranger.isParked(f) && arranger.isParked(t), "not every member parked: \(hide)")
        #expect(parks(hide).filter { if case .park(t, _, _) = $0 { true } else { false } }.isEmpty, "t parked twice")
        #expect(strips(hide) == [[]], "the strip stayed on a hidden Desktop")
        for window in [f, t] {  // the parks' echoes: slivers at the display's corner
            _ = arranger.handle(.event(.windowMoved(window, Rect(x: 1439, y: 899, width: content.width, height: content.height))), now: start)
        }
        let show = arranger.handle(.command(.toggleDesktop, focused: a), now: start)
        #expect(setFrames(show)[f] == content, "f did not come back at the content rect: \(show)")
        #expect(setFrames(show)[t] == nil, "the hidden member came back")
        #expect(arranger.isParked(t) && !arranger.isParked(f))
        #expect(strips(show).last?.first?.floating == true, "the strip did not come back")
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
        #expect(!arranger.handle(.tick, now: start + .milliseconds(999)).contains(.tabAnnouncement(.didNotClose(a))))
        let stop = arranger.handle(.tick, now: start + Arranger.closeConfirmation)
        #expect(stop.contains(.tabAnnouncement(.didNotClose(a))))
        #expect(closes(stop).isEmpty)
        #expect(selected(arranger, group) == a, "the window that stopped Close Group is not the one shown")
        #expect(arranger.tabs.closeQueue == nil)
        #expect(closes(arranger.handle(.tab(.closeGroup(group), ready: true), now: start + .seconds(5))) == [a])
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
        _ = arranger.handle(.tab(.minimizeGroup(group), ready: true), now: start)
        _ = arranger.handle(.event(.windowStateChanged(f, .absent)), now: start + .milliseconds(200))
        let focus = arranger.handle(.event(.windowFocused(b)), now: start + .milliseconds(700))
        #expect(selected(arranger, group) == f, "the same-app focus switched tabs")
        #expect(commands(focus).isEmpty, "the focus moved a window: \(commands(focus))")
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
        // tFrame's centre is in the Desktop's centre zone, nearer the top: Dock Window's edge rule.
        #expect(desk.tree.parent(of: leaf).flatMap { desk.tree.node($0) }.map { if case .split(.vertical, let children, _) = $0 { children.first == leaf } else { false } } == true)
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
        var (arranger, _, frame, _) = try bareGroup(at: start)  // [a | [b, f] | Desktop]
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
        var (arranger, group, _, _) = try bareGroup(at: start)  // [a | [b, f] | Desktop]
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
        let before = try #require(arranger.world[mainKey])
        let desktop = try #require(try Planner.plan(desk: before, area: area, gap: 8, mins: [:]).desktopRect)
        _ = arranger.handle(.command(.snap(.leftHalf), focused: f), now: start + .seconds(1))
        let group = try #require(floatingGroup(arranger))
        let expected = Snap.frame(.leftHalf, window: tFrame, desktop: desktop, gap: 8)
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

/// [a | [b, f] | Desktop] on the fake, f selected; returns the group leaf, a's tile and the group's content rect.
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
        let point = Point(x: content.midX - 100, y: content.minY + 10 + 50)  // on the Desktop, no floater's centre
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

private func desktopRect(_ arranger: Arranger) throws -> Rect {
    let desk = try #require(arranger.world[mainKey])
    return try #require(try Planner.plan(desk: desk, area: area, gap: 8, mins: [:]).desktopRect)
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

    @Test func aReleaseOverEmptyDesktopFloatsTheTabAtTheClampedLandingFrameInOneUndoStep() throws {
        let start = ContinuousClock.now
        var (arranger, group, _, content) = try bareGroup(at: start, withA: true)  // [b, f, a], a selected
        let desktop = try desktopRect(arranger)
        arranger.wantedFrames[b.identity] = Rect(x: 0, y: 0, width: desktop.width - 40, height: desktop.height - 40)  // its pre-group frame
        let point = centre(desktop)  // the landing frame (top 12 pt above the pointer) must be clamped up
        let expected = Planner.clamp(landing(arranger, b, content: content, at: point), into: desktop)
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
        let desktop = try desktopRect(arranger)
        _ = try tear(&arranger, f, of: group, to: centre(desktop), at: start)
        let up = arranger.handle(pointer(.up, desktop.midX, desktop.midY), now: start + .milliseconds(200))
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
        let desktop = try desktopRect(arranger)
        let expected = Planner.clamp(landing(arranger, b, content: content, at: point), into: desktop)
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
        let desktop = try desktopRect(arranger)
        _ = try tear(&arranger, f, of: group, to: centre(desktop), at: start)
        let up = arranger.handle(pointer(.up, desktop.midX, desktop.midY), now: start + .milliseconds(200))
        #expect(selected(arranger, group) == a, "the right neighbour was not selected")
        #expect(arranger.world[mainKey]?.tree.node(group.node) == .tabs(windows: [b, a], selected: 1))
        #expect(announcements(up) == [.movedOut(dissolved: false)])
    }
}

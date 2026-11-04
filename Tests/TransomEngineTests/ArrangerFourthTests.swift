@testable import TransomEngine
import TransomModel
import Testing

private let area = Rect(x: 0, y: 25, width: 1440, height: 875)
private let mainKey = DeskKey(displayUUID: "main", spaceID: nil)
private let mainDisplay = DisplayInfo(uuid: "main", frame: Rect(x: 0, y: 0, width: 1440, height: 900), visibleFrame: area, currentSpaceID: nil)

private func window(_ id: UInt32) -> WindowRef {
    WindowRef(identity: WindowIdentity(windowID: id, pid: 900, bundleID: "com.example.arranger"))
}

private let w = window(1), a = window(2), b = window(3)
private let frameW = Rect(x: 600, y: 300, width: 400, height: 300)
/// Wider than the whole display: never fits a tile.
private let huge = Size(width: 1500, height: 100)

private func info(_ ref: WindowRef, _ frame: Rect = frameW, kind: WindowKind = .dockable, excluded: Bool = false, minimum: Size? = nil) -> WindowInfo {
    WindowInfo(window: ref, frame: frame, state: .present, displayUUID: "main", kind: kind, isExcluded: excluded, learnedMinimum: minimum)
}

/// An Arranger fed `infos` on the main display, with zoom on or off.
private func arranger(_ infos: [WindowInfo], zoom: Bool = false) -> Arranger {
    var arranger = Arranger()
    _ = arranger.handle(.inventory(WindowInventory(displays: [mainDisplay], windows: infos, initialRefreshComplete: true)), now: .now)
    if zoom { _ = arranger.handle(.zoomEnabled(true), now: .now) }
    return arranger
}

/// Docks `windows` left to right before the Desktop tile, flat at the root with equal weights.
private func dockFlat(_ windows: [WindowRef], in arranger: inout Arranger) throws {
    try arranger.world.edit(mainKey, history: &arranger.history) { desk, ids throws(LayoutError) in
        for window in windows.reversed() {
            try desk.desktop.remove(window)
            try desk.tree.insert(window, at: .left, of: desk.tree.root!, ids: &ids)
        }
    }
    _ = arranger.handle(.gap(8), now: .now)  // re-plans
}

private func command(_ arranger: inout Arranger, _ slot: FourthSlot, _ axis: Axis, focused: WindowRef?) -> [ArrangerEffect] {
    arranger.handle(.command(.dockFourth(slot, axis), focused: focused), now: .now)
}

private func rootWeights(_ arranger: Arranger) throws -> [Double] {
    let tree = try #require(arranger.world[mainKey]?.tree)
    guard case let .split(_, _, weights)? = tree.node(try #require(tree.root)) else { return [] }
    return weights
}

/// The root's children: a docked window's position from the left, read through the leaf holding it.
private func rootOrder(_ arranger: Arranger) throws -> [WindowRef?] {
    let tree = try #require(arranger.world[mainKey]?.tree)
    guard case let .split(_, children, _)? = tree.node(try #require(tree.root)) else { return [] }
    return children.map { id in
        if case .panel(let window)? = tree.node(id) { window } else { nil }
    }
}

private func expectWeights(_ actual: [Double], _ expected: [Double], sourceLocation: SourceLocation = #_sourceLocation) {
    #expect(actual.count == expected.count, "weights \(actual)", sourceLocation: sourceLocation)
    for (got, want) in zip(actual, expected) { #expect(abs(got - want) <= 1e-9, "weights \(actual)", sourceLocation: sourceLocation) }
}

private func announcements(_ effects: [ArrangerEffect]) -> [String] {
    effects.compactMap { if case .announce(let text) = $0 { text } else { nil } }
}

/// TILE-23, D-15, D-16: the fourth commands on the focused window.
@Suite struct ArrangerFourthTests {
    @Test func aFloatingWindowDocksAsTheFirstColumnInOneUndoStep() throws {
        var arranger = arranger([info(w)])
        let depth = arranger.history.depth(for: mainKey)

        let effects = command(&arranger, .first, .horizontal, focused: w)

        expectWeights(try rootWeights(arranger), [0.25, 0.75])
        #expect(try rootOrder(arranger) == [w, nil])
        #expect(arranger.history.depth(for: mainKey) == depth + 1)
        #expect(announcements(effects) == ["Docked to 1st column"])
    }

    @Test func theMiddleHalfRowHasItsOwnAnnouncement() {
        var arranger = arranger([info(w)])
        #expect(announcements(command(&arranger, .middle, .vertical, focused: w)) == ["Docked to middle half row"])
    }

    @Test func undoBringsTheWindowBackToFloatingAtItsFrame() throws {
        var arranger = arranger([info(w)])
        _ = command(&arranger, .first, .horizontal, focused: w)

        _ = arranger.handle(.command(.undo, focused: w), now: .now)

        let desk = try #require(arranger.world[mainKey])
        #expect(desk.desktop.frame(of: w) == frameW)
        #expect(desk.tree.state(of: w) == nil)
    }

    @Test func aDockedWindowMovesAndTheOthersShareWhatIsLeft() throws {
        var arranger = arranger([info(w), info(a, Rect(x: 700, y: 400, width: 150, height: 120))])
        try dockFlat([w, a], in: &arranger)
        expectWeights(try rootWeights(arranger), [1.0 / 3, 1.0 / 3, 1.0 / 3])
        let depth = arranger.history.depth(for: mainKey)

        _ = command(&arranger, .fourth, .horizontal, focused: w)

        expectWeights(try rootWeights(arranger), [3.0 / 8, 3.0 / 8, 1.0 / 4])
        #expect(try rootOrder(arranger) == [a, nil, w])
        #expect(arranger.history.depth(for: mainKey) == depth + 1)
    }

    @Test func noFocusedWindowBeeps() {
        var arranger = arranger([info(w)])
        #expect(command(&arranger, .first, .horizontal, focused: nil) == [.beep])
    }

    @Test func availabilityMatchesMoveOrSnap() {
        let c = window(4)
        var arranger = arranger([
            info(w), info(a, Rect(x: 700, y: 400, width: 150, height: 120)), info(b, frameW, kind: .neverDock(.subrole)),
            info(c, frameW, excluded: true),
        ])
        _ = arranger.handle(.command(.dock, focused: a), now: .now)
        let fourth = Command.dockFourth(.first, .horizontal)
        func available(_ focused: WindowRef?, ready: Bool = true) -> Bool {
            arranger.availability(fourth, context: CommandContext(focused: focused, ready: ready))
        }
        #expect(available(w), "floating")
        #expect(available(a), "docked")
        #expect(!available(nil))
        #expect(!available(b), "never dock")
        #expect(!available(c), "excluded")
        #expect(!available(w, ready: false))
        for focused in [w, a, b, c, nil] as [WindowRef?] {
            #expect(
                available(focused) == arranger.availability(.moveOrSnap(.left), context: CommandContext(focused: focused, ready: true)))
        }
        _ = arranger.handle(.command(.togglePause, focused: nil), now: .now)
        #expect(!available(w), "paused")
    }

    /// The first-column frame of `w` on a desk `change` left, planned with no minimums.
    private func wouldBeFrame(_ arranger: Arranger, _ edit: (inout Desk, inout IDSource) throws -> Void) throws -> Rect {
        var desk = try #require(arranger.world[mainKey])
        var ids = IDSource(next: 9000)
        try edit(&desk, &ids)
        let plan = try Planner.plan(desk: desk, area: area, gap: 8, mins: [:])
        return try #require(desk.tree.leaf(containing: w).flatMap { plan.resolution.nodeRects[$0] })
    }

    @Test func aDockedGroupMovesWholeForAnyFocusedMember() throws {
        var arranger = arranger([info(w), info(a, Rect(x: 700, y: 400, width: 150, height: 120))])
        try dockFlat([a], in: &arranger)
        let leaf = try #require(arranger.world[mainKey]?.tree.leaf(containing: a))
        try arranger.world.edit(mainKey, history: &arranger.history) { desk, _ throws(LayoutError) in
            try desk.desktop.remove(w)
            try desk.tree.group(w, into: leaf)
        }
        _ = arranger.handle(.gap(8), now: .now)
        let tree = try #require(arranger.world[mainKey]?.tree)
        guard case .tabs(let members, let selected)? = tree.node(leaf) else {
            Issue.record("no group")
            return
        }
        let notSelected = members[(selected + 1) % members.count]
        let depth = arranger.history.depth(for: mainKey)

        _ = command(&arranger, .fourth, .horizontal, focused: notSelected)

        let after = try #require(arranger.world[mainKey]?.tree)
        expectWeights(try rootWeights(arranger), [3.0 / 4, 1.0 / 4])
        guard case .split(_, let children, _)? = after.node(try #require(after.root)), case .tabs(let moved, _)? = after.node(children[1]) else {
            Issue.record("the group is not the last child: \(after)")
            return
        }
        #expect(Set(moved) == Set(members))
        #expect(arranger.history.depth(for: mainKey) == depth + 1)
    }

    @Test func aFloatingGroupDocksWhole() throws {
        var arranger = arranger([info(w), info(a, Rect(x: 700, y: 400, width: 150, height: 120))])
        try arranger.world.edit(mainKey, history: &arranger.history) { desk, ids throws(LayoutError) in
            try desk.desktop.group(id: try ids.make(), target: a, adding: w)
        }
        _ = arranger.handle(.gap(8), now: .now)
        let depth = arranger.history.depth(for: mainKey)

        _ = command(&arranger, .first, .horizontal, focused: w)

        let desk = try #require(arranger.world[mainKey])
        expectWeights(try rootWeights(arranger), [1.0 / 4, 3.0 / 4])
        #expect(desk.desktop.group(containing: w) == nil)
        #expect(desk.tree.leaf(containing: w) == desk.tree.leaf(containing: a), "the group came apart")
        #expect(arranger.history.depth(for: mainKey) == depth + 1)
    }

    @Test func withZoomOffAWindowThatDoesNotFitIsRefusedWithTheBlockedFlash() throws {
        var arranger = arranger([info(w, minimum: huge)])
        let world = arranger.world, depth = arranger.history.depth(for: mainKey)
        let frame = try wouldBeFrame(arranger) { desk, ids in
            try desk.desktop.remove(w)
            try desk.tree.insertFourth(.panel(w), states: [w.identity: .present], slot: .first, axis: .horizontal, ids: &ids)
        }

        let effects = command(&arranger, .first, .horizontal, focused: w)

        #expect(effects == [.beep, .announce("Not enough room to dock here"), .flashBlocked(frame, displayUUID: "main")])
        #expect(arranger.world == world)
        #expect(arranger.history.depth(for: mainKey) == depth)
    }

    @Test func aRefusedGroupFlashesAtItsLeafRect() throws {
        var arranger = arranger([info(w, minimum: huge), info(a, Rect(x: 700, y: 400, width: 150, height: 120))])
        try arranger.world.edit(mainKey, history: &arranger.history) { desk, ids throws(LayoutError) in
            try desk.desktop.group(id: try ids.make(), target: a, adding: w)
        }
        _ = arranger.handle(.gap(8), now: .now)
        let world = arranger.world
        let frame = try wouldBeFrame(arranger) { desk, ids in
            let group = try desk.desktop.removeGroup(try #require(desk.desktop.group(containing: w)).id)
            try desk.tree.insertFourth(
                .tabs(windows: group.group.members, selected: group.group.selected), states: group.states, slot: .middle, axis: .horizontal, ids: &ids)
        }

        let effects = command(&arranger, .middle, .horizontal, focused: w)

        #expect(effects == [.beep, .announce("Not enough room to dock here"), .flashBlocked(frame, displayUUID: "main")])
        #expect(arranger.world == world)
    }

    @Test func withZoomOnAWindowThatDoesNotFitCollapsesAndSaysSo() throws {
        var arranger = arranger([info(w, minimum: huge)], zoom: true)
        let depth = arranger.history.depth(for: mainKey)

        let effects = command(&arranger, .first, .horizontal, focused: w)

        #expect(announcements(effects) == [CollapseCopy.dockedAnnouncement(dragged: true, others: 0)])
        #expect(arranger.camera.collapsible == [w.identity])
        #expect(arranger.world[mainKey]?.tree.state(of: w) == .present)
        #expect(arranger.history.depth(for: mainKey) == depth + 1)
    }

    @Test func theSameFourthAgainOnlyBeepsAndAddsNoUndoStep() throws {
        var arranger = arranger([info(w)])
        _ = command(&arranger, .first, .horizontal, focused: w)
        let world = arranger.world, depth = arranger.history.depth(for: mainKey)

        #expect(command(&arranger, .first, .horizontal, focused: w) == [.beep])

        #expect(arranger.world == world, "the window got a new leaf")
        #expect(arranger.history.depth(for: mainKey) == depth)
    }

    /// Nothing moves on screen, but a floating window becoming docked is a change.
    @Test func aFloatingWindowAlreadyAtTheFrameStillDocks() throws {
        var trial = arranger([info(w)])
        _ = command(&trial, .first, .horizontal, focused: w)
        let desk = try #require(trial.world[mainKey])
        let tile = try #require(try Planner.plan(desk: desk, area: area, gap: 8, mins: [:]).frames[w])
        var atTheFrame = arranger([info(w, tile)])

        _ = command(&atTheFrame, .first, .horizontal, focused: w)

        #expect(atTheFrame.world[mainKey]?.tree.state(of: w) == .present)
    }

    /// A row with the root running the other way wraps it, in one step; the weights then edit like any other split.
    @Test func aRowWrapsTheRootInOneUndoStepAndNothingRemembersTheFourth() throws {
        var arranger = arranger([info(w), info(a, Rect(x: 700, y: 400, width: 150, height: 120))])
        try dockFlat([a], in: &arranger)
        let depth = arranger.history.depth(for: mainKey)

        _ = command(&arranger, .first, .vertical, focused: w)

        let tree = try #require(arranger.world[mainKey]?.tree)
        guard case .split(let axis, _, _)? = tree.node(try #require(tree.root)) else {
            Issue.record("no root split")
            return
        }
        #expect(axis == .vertical)
        expectWeights(try rootWeights(arranger), [1.0 / 4, 3.0 / 4])
        #expect(arranger.history.depth(for: mainKey) == depth + 1)

        _ = arranger.handle(.command(.growTile, focused: w), now: .now)
        expectWeights(try rootWeights(arranger), [0.35, 0.65])
    }
}

// MARK: Drags (D-12, D-18, UI-SPEC Surface 3)

private func pointer(_ kind: PointerEvent.Kind, _ x: Double, _ y: Double, _ modifiers: Modifiers = [], press: WindowRef? = nil) -> ArrangerInput {
    .pointer(PointerEvent(kind: kind, location: Point(x: x, y: y), modifiers: modifiers, pressWindow: press))
}

private func shifted(_ rect: Rect, _ dx: Double, _ dy: Double = 0) -> Rect {
    Rect(x: rect.x + dx, y: rect.y + dy, width: rect.width, height: rect.height)
}

private func previews(_ effects: [ArrangerEffect]) -> [PreviewState] {
    effects.compactMap { if case .preview(let state?, _) = $0 { state } else { nil } }
}

/// Presses `window`'s title bar with no modifier, drags 10 pt right (the session starts), presses `modifiers`, then goes on
/// to `point`, the frame following the pointer.
private func controlDrag(
    _ harness: inout Harness, _ window: WindowRef, from frame: Rect, to point: Point, _ modifiers: Modifiers = .control
) async -> [ArrangerEffect] {
    let grab = Point(x: frame.midX, y: frame.minY + 10)
    var effects = await harness.send(pointer(.down, grab.x, grab.y, press: window))
    effects += await harness.send(pointer(.dragged, grab.x + 10, grab.y))
    effects += await harness.send(.dragFrame(window.identity, shifted(frame, 10)))
    effects += await harness.send(pointer(.flagsChanged, grab.x + 10, grab.y, modifiers))
    effects += await harness.send(pointer(.dragged, point.x, point.y, modifiers))
    effects += await harness.send(.dragFrame(window.identity, shifted(frame, point.x - grab.x, point.y - grab.y)))
    return effects
}

/// The dwell passes.
private func tick(_ harness: inout Harness) async -> [ArrangerEffect] {
    harness.now += .milliseconds(150)
    return await harness.send(.tick)
}

/// The frame a dry run of a fourth gives `window` on the main desk: out of its tree or Desktop layer, `applyDrop`, plan.
private func fourthFrame(_ arranger: Arranger, _ window: WindowRef, _ slot: FourthSlot, _ axis: Axis) throws -> Rect {
    var desk = try #require(arranger.world[mainKey])
    var ids = arranger.world.ids
    if desk.desktop.contains(window) { try desk.desktop.remove(window) } else { try desk.tree.remove(window) }
    try desk.tree.applyDrop(.fourth(slot, axis), window: window, ids: &ids)
    return try #require(try Planner.plan(desk: desk, area: area, gap: 8, mins: [:]).frames[window])
}

/// w and a docked by the keyboard, with w's tile.
private func twoDocked() async throws -> (Harness, Rect) {
    var harness = await Harness.started(frames: [1: frameW, 2: Rect(x: 700, y: 400, width: 150, height: 120)])
    await harness.send(.command(.dock, focused: w))
    await harness.send(.command(.dock, focused: a))
    let desk = try #require(harness.arranger.world[mainKey])
    return (harness, try #require(try Planner.plan(desk: desk, area: area, gap: 8, mins: [:]).frames[w]))
}

extension ArrangerFourthTests {
    @Test func controlDuringADragPreviewsTheColumnAfterTheDwellAndDocksThere() async throws {
        var harness = await Harness.started(frames: [1: frameW])
        let during = await controlDrag(&harness, w, from: frameW, to: Point(x: 10, y: 310))
        #expect(previews(during).isEmpty, "a preview before the dwell: \(during)")

        let shown = await tick(&harness)
        let frame = try fourthFrame(harness.arranger, w, .first, .horizontal)
        #expect(shown.contains(.preview(.fourth(frame, label: "1st column"), displayUUID: "main")), "tick gave \(shown)")

        let depth = harness.arranger.history.depth(for: mainKey)
        let up = await harness.send(pointer(.up, 10, 310, .control))
        #expect(setFrames(up)[w] == frame)
        #expect(announcements(up) == ["Docked to 1st column"])
        #expect(harness.arranger.world[mainKey]?.tree.state(of: w) == .present)
        #expect(harness.arranger.history.depth(for: mainKey) == depth + 1)
        expectWeights(try rootWeights(harness.arranger), [0.25, 0.75])
    }

    @Test func controlCommandPicksARow() async throws {
        var harness = await Harness.started(frames: [1: frameW])
        _ = await controlDrag(&harness, w, from: frameW, to: Point(x: 700, y: 30), [.control, .command])

        let shown = await tick(&harness)

        let frame = try fourthFrame(harness.arranger, w, .first, .vertical)
        #expect(shown.contains(.preview(.fourth(frame, label: "1st row"), displayUUID: "main")), "tick gave \(shown)")
    }

    /// The window grows into the side with no tile (D-14), so the result is more than the half the zone names.
    @Test func theMiddleBandShowsTheResultNotTheZone() async throws {
        var harness = await Harness.started(frames: [1: frameW])
        _ = await controlDrag(&harness, w, from: frameW, to: Point(x: 720, y: 310))

        let shown = await tick(&harness)

        let frame = try fourthFrame(harness.arranger, w, .middle, .horizontal)
        #expect(shown.contains(.preview(.fourth(frame, label: "Middle half column"), displayUUID: "main")), "tick gave \(shown)")
        #expect(frame.width > area.width / 2, "\(frame)")
    }

    @Test func aDockedWindowMovesInOneUndoStep() async throws {
        var (harness, tile) = try await twoDocked()
        _ = await controlDrag(&harness, w, from: tile, to: Point(x: 1300, y: 310))
        let shown = await tick(&harness)
        let frame = try fourthFrame(harness.arranger, w, .fourth, .horizontal)
        #expect(shown.contains(.preview(.fourth(frame, label: "4th column"), displayUUID: "main")), "tick gave \(shown)")
        let depth = harness.arranger.history.depth(for: mainKey)

        let up = await harness.send(pointer(.up, 1300, 310, .control))

        #expect(setFrames(up)[w] == frame)
        #expect(announcements(up) == ["Docked to 4th column"])
        #expect(harness.arranger.history.depth(for: mainKey) == depth + 1)
    }
}

// MARK: Guides (UI-SPEC Surface 3)

private func guides(_ effects: [ArrangerEffect]) -> [([Rect], String)] {
    effects.compactMap { if case .fourthGuides(let rects, let uuid) = $0 { (rects, uuid) } else { nil } }
}

private let columns = FourthZones.bands(in: area, axis: .horizontal)
private let rows = FourthZones.bands(in: area, axis: .vertical)

/// w dragged with ⌃ into the 1st band and held past the dwell: the guides and a result are up.
private func guidesUp() async -> Harness {
    var harness = await Harness.started(frames: [1: frameW])
    _ = await controlDrag(&harness, w, from: frameW, to: Point(x: 10, y: 310))
    _ = await tick(&harness)
    return harness
}

extension ArrangerFourthTests {
    @Test func theGuidesAppearOnceWithTheFirstResult() async throws {
        var harness = await Harness.started(frames: [1: frameW])
        let during = await controlDrag(&harness, w, from: frameW, to: Point(x: 10, y: 310))
        #expect(guides(during).isEmpty, "guides before the dwell")

        let first = await tick(&harness)

        #expect(first.contains(.fourthGuides(columns, displayUUID: "main")), "tick gave \(first)")
        #expect(guides(first).count == 1)
        #expect(guides(await tick(&harness)).isEmpty, "sent again")
    }

    @Test func aZoneChangeLeavesTheGuidesAlone() async throws {
        var harness = await guidesUp()

        let moved = await harness.send(pointer(.dragged, 1300, 310, .control))

        #expect(moved.contains(.preview(nil, displayUUID: "main")))
        #expect(guides(moved).isEmpty)
        let shown = await tick(&harness)
        #expect(!previews(shown).isEmpty, "no new result")
        #expect(guides(shown).isEmpty)
    }

    @Test func commandSwitchesTheGuidesAtOnce() async throws {
        var harness = await guidesUp()

        let pressed = await harness.send(pointer(.flagsChanged, 10, 310, [.control, .command]))
        #expect(pressed.contains(.fourthGuides(rows, displayUUID: "main")), "got \(pressed)")

        let released = await harness.send(pointer(.flagsChanged, 10, 310, .control))
        #expect(released.contains(.fourthGuides(columns, displayUUID: "main")), "got \(released)")
    }

    @Test(arguments: [
        (Modifiers(), 10.0, "⌃ released"), (Modifiers([.control, .shift]), 10.0, "⇧ pressed"), (Modifiers.control, -5000.0, "off every display"),
    ] as [(Modifiers, Double, String)])
    func leavingAFourthHidesTheGuides(modifiers: Modifiers, x: Double, _ why: String) async throws {
        var harness = await guidesUp()

        let left = await harness.send(pointer(.dragged, x, 310, modifiers))

        #expect(left.contains(.fourthGuides([], displayUUID: "main")), "\(why): \(left)")
    }

    @Test func aNewDisplaysGuidesWaitForItsDwell() {
        let start = ContinuousClock.now
        let side = DisplayInfo(
            uuid: "side", frame: Rect(x: 1440, y: 0, width: 1920, height: 1080), visibleFrame: Rect(x: 1440, y: 0, width: 1920, height: 1080),
            currentSpaceID: nil)
        var arranger = Arranger()
        _ = arranger.handle(.inventory(WindowInventory(displays: [mainDisplay, side], windows: [info(w)], initialRefreshComplete: true)), now: start)
        let grab = Point(x: frameW.midX, y: frameW.minY + 10)
        _ = arranger.handle(pointer(.down, grab.x, grab.y, press: w), now: start)
        _ = arranger.handle(pointer(.dragged, grab.x + 10, grab.y), now: start)
        _ = arranger.handle(.dragFrame(w.identity, shifted(frameW, 10)), now: start)
        _ = arranger.handle(pointer(.dragged, 10, 310, .control), now: start)
        _ = arranger.handle(.tick, now: start + .milliseconds(150))

        let crossed = arranger.handle(pointer(.dragged, 1500, 310, .control), now: start + .milliseconds(160))

        #expect(guides(crossed).map(\.1) == ["main"] && guides(crossed).first?.0 == [], "got \(crossed)")
        let settled = arranger.handle(.tick, now: start + .milliseconds(310))
        #expect(settled.contains(.fourthGuides(FourthZones.bands(in: side.visibleFrame, axis: .horizontal), displayUUID: "side")), "got \(settled)")
    }

    @Test func aMouseUpHidesTheGuides() async throws {
        var harness = await guidesUp()
        let up = await harness.send(pointer(.up, 10, 310, .control))
        #expect(up.contains(.fourthGuides([], displayUUID: "main")), "got \(up)")
    }

    @Test func aPauseEndingTheDragHidesTheGuides() async throws {
        var harness = await guidesUp()
        var effects = await harness.send(.setPaused(.user, true))
        effects += await harness.send(pointer(.dragged, 1300, 310, .control))
        #expect(effects.contains(.fourthGuides([], displayUUID: "main")), "got \(effects)")
        #expect(effects.contains(.preview(nil, displayUUID: "main")))
        #expect(harness.arranger.drag == nil)
    }

    @Test func anAbandonedDragHidesTheGuides() async throws {
        var harness = await guidesUp()
        let again = await harness.send(pointer(.down, 800, 310, press: w))
        #expect(again.contains(.fourthGuides([], displayUUID: "main")), "got \(again)")
    }

    @Test func aDragThatShowedNoGuidesSendsNoGuideEffect() async throws {
        var harness = await Harness.started(frames: [1: frameW])
        var effects = await controlDrag(&harness, w, from: frameW, to: Point(x: 10, y: 310))
        effects += await harness.send(pointer(.up, 10, 310, .control))
        #expect(guides(effects).isEmpty, "got \(effects)")
    }
}

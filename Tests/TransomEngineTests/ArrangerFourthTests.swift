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

/// Docks `windows` in order before the Desktop tile, flat at the root with equal weights: left to right, or from the top.
private func dockFlat(_ windows: [WindowRef], at edge: Edge = .left, in arranger: inout Arranger) throws {
    try arranger.world.edit(mainKey, history: &arranger.history) { desk, ids throws(LayoutError) in
        for window in windows.reversed() {
            try desk.desktop.remove(window)
            try desk.tree.insert(window, at: edge, of: desk.tree.root!, ids: &ids)
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

    /// D-23: the announcement names what the window gets. Alone beside the Desktop tile, a slot with an empty side grows into it.
    @Test(arguments: [
        (FourthSlot.first, false, "1st column", "1st row"),
        (.second, false, "Left half", "Top half"),
        (.middle, false, "Left three quarters", "Top three quarters"),
        (.third, false, "Right half", "Bottom half"),
        (.fourth, false, "4th column", "4th row"),
        (.second, true, "2nd column", "2nd row"),
        (.middle, true, "Middle half column", "Middle half row"),
        (.third, true, "3rd column", "3rd row"),
    ])
    func theAnnouncementNamesTheActualSpan(slot: FourthSlot, besideATile: Bool, column: String, row: String) throws {
        for (axis, edge, label) in [(Axis.horizontal, Edge.left, column), (.vertical, .top, row)] {
            var arranger = besideATile ? arranger([info(w), info(a)]) : arranger([info(w)])
            if besideATile { try dockFlat([a], at: edge, in: &arranger) }
            #expect(announcements(command(&arranger, slot, axis, focused: w)) == ["Docked to \(label.lowercased())"])
        }
    }

    /// The user's case (host check 3): by rows over side-by-side windows the whole layout is one child, on one side.
    @Test(arguments: [(FourthSlot.second, "top half"), (.middle, "top three quarters"), (.third, "bottom half")])
    func rowsOverSideBySideWindowsNameTheShareTheWindowGets(slot: FourthSlot, name: String) throws {
        var arranger = arranger([info(w), info(a)])
        try dockFlat([a], in: &arranger)
        #expect(announcements(command(&arranger, slot, .vertical, focused: w)) == ["Docked to \(name)"])
    }

    /// Every span `FourthCopy` words, on both axes. An own span keeps the slot's name. No layout reaches (0.25, 1) today: the
    /// last tile's centre is never before the 2nd or middle slot's, but the label is the user's table all the same.
    @Test(arguments: [
        (0.0, 0.25, FourthSlot.first, "1st column", "1st row"),
        (0.25, 0.5, .second, "2nd column", "2nd row"),
        (0.5, 0.75, .third, "3rd column", "3rd row"),
        (0.75, 1, .fourth, "4th column", "4th row"),
        (0.25, 0.75, .middle, "Middle half column", "Middle half row"),
        (0, 0.5, .second, "Left half", "Top half"),
        (0.5, 1, .third, "Right half", "Bottom half"),
        (0, 0.75, .middle, "Left three quarters", "Top three quarters"),
        (0.25, 1, .middle, "Right three quarters", "Bottom three quarters"),
        (0, 1, .first, "Whole desk", "Whole desk"),
    ])
    func everySpanHasItsLabel(start: Double, end: Double, slot: FourthSlot, column: String, row: String) {
        #expect(FourthCopy.label(slot, .horizontal, span: (start, end)) == column)
        #expect(FourthCopy.label(slot, .vertical, span: (start, end)) == row)
    }

    @Test func theAnnouncementLowersTheLabelsCase() {
        #expect(FourthCopy.docked("Whole desk") == "Docked to whole desk")
        #expect(FourthCopy.docked("Middle half row") == "Docked to middle half row")
        #expect(FourthCopy.docked("1st row") == "Docked to 1st row")
    }

    @Test func aWindowWithNothingElseTakingPartGetsTheWholeDesk() throws {
        var arranger = arranger([info(w), info(a)])
        try dockFlat([a], in: &arranger)
        try arranger.world.edit(mainKey, history: &arranger.history) { desk, _ throws(LayoutError) in try desk.tree.setDesktopHidden(true) }
        try arranger.world.apply(.absent, for: a, on: mainKey, history: &arranger.history)
        #expect(announcements(command(&arranger, .third, .vertical, focused: w)) == ["Docked to whole desk"])
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
    /// D-23: the capsule and the announcement both name what the window gets, and the window gets that.
    @Test func aRowDragOverSideBySideWindowsSaysTopHalfAndGivesIt() async throws {
        var (harness, tile) = try await twoDocked()
        let point = Point(x: 720, y: area.minY + area.height * 0.3125)
        _ = await controlDrag(&harness, w, from: tile, to: point, [.control, .command])
        let frame = try fourthFrame(harness.arranger, w, .second, .vertical)
        #expect(abs(frame.height - (area.height - 24) / 2) <= 1, "\(frame)")  // three 8 pt gaps
        let shown = await tick(&harness)
        #expect(shown.contains(.preview(.fourth(frame, label: "Top half"), displayUUID: "main")), "tick gave \(shown)")
        let up = await harness.send(pointer(.up, point.x, point.y, [.control, .command]))
        #expect(setFrames(up)[w] == frame)
        #expect(announcements(up) == ["Docked to top half"])
    }

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

    /// The window grows into the side with no tile (D-14), and the capsule names that result, not the zone (D-23).
    @Test func theMiddleBandShowsTheResultNotTheZone() async throws {
        var harness = await Harness.started(frames: [1: frameW])
        _ = await controlDrag(&harness, w, from: frameW, to: Point(x: 720, y: 310))

        let shown = await tick(&harness)

        let frame = try fourthFrame(harness.arranger, w, .middle, .horizontal)
        #expect(shown.contains(.preview(.fourth(frame, label: "Left three quarters"), displayUUID: "main")), "tick gave \(shown)")
        #expect(frame.width > area.width / 2, "\(frame)")
    }

    /// UI-SPEC Surface 3: released on the zone it already holds, it stays, with nothing refused and nothing to undo (WR-08).
    @Test func aDockedWindowDroppedOnItsOwnZoneAddsNoUndoStep() async throws {
        var harness = await Harness.started(frames: [1: frameW])
        await harness.send(.command(.dockFourth(.first, .horizontal), focused: w))
        let tile = try fourthFrame(harness.arranger, w, .first, .horizontal)
        let world = harness.arranger.world, depth = harness.arranger.history.depth(for: mainKey)
        await harness.send(.event(.frameApplied(w, requested: tile, actual: tile)))
        await harness.send(.event(.windowMoved(w, tile)))

        _ = await controlDrag(&harness, w, from: tile, to: Point(x: 10, y: 310))
        let shown = await tick(&harness)
        #expect(shown.contains(.preview(.fourth(tile, label: "1st column"), displayUUID: "main")), "tick gave \(shown)")
        let up = await harness.send(pointer(.up, 10, 310, .control))

        #expect(harness.arranger.world == world, "the window got a new leaf")
        #expect(harness.arranger.history.depth(for: mainKey) == depth)
        #expect(announcements(up).isEmpty, "\(up)")
        #expect(!up.contains(.beep))
        #expect(setFrames(up)[w] == tile, "the window was not put back: \(up)")
    }

    /// Another zone is a real move: the guard is only for an edit that changes nothing.
    @Test func aDockedWindowDroppedOnAnotherZoneStillMoves() async throws {
        var harness = await Harness.started(frames: [1: frameW])
        await harness.send(.command(.dockFourth(.first, .horizontal), focused: w))
        let tile = try fourthFrame(harness.arranger, w, .first, .horizontal)
        let depth = harness.arranger.history.depth(for: mainKey)

        _ = await controlDrag(&harness, w, from: tile, to: Point(x: 1300, y: 310))
        _ = await tick(&harness)
        let up = await harness.send(pointer(.up, 1300, 310, .control))

        #expect(harness.arranger.history.depth(for: mainKey) == depth + 1)
        #expect(announcements(up) == ["Docked to 4th column"])
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

// MARK: The rest of the drag matrix (D-15, D-16, D-18, UI-SPEC Surface 2 rows 1-3 and Surface 3)

/// The same drag on an Arranger with no window system behind it.
private func controlDrag(
    _ arranger: inout Arranger, _ window: WindowRef, from frame: Rect, to point: Point, _ modifiers: Modifiers = .control,
    at now: ContinuousClock.Instant
) -> [ArrangerEffect] {
    let grab = Point(x: frame.midX, y: frame.minY + 10)
    var effects = arranger.handle(pointer(.down, grab.x, grab.y, press: window), now: now)
    effects += arranger.handle(pointer(.dragged, grab.x + 10, grab.y), now: now)
    effects += arranger.handle(.dragFrame(window.identity, shifted(frame, 10)), now: now)
    effects += arranger.handle(pointer(.flagsChanged, grab.x + 10, grab.y, modifiers), now: now)
    effects += arranger.handle(pointer(.dragged, point.x, point.y, modifiers), now: now)
    effects += arranger.handle(.dragFrame(window.identity, shifted(frame, point.x - grab.x, point.y - grab.y)), now: now)
    return effects
}

private func fourthLabels(_ effects: [ArrangerEffect]) -> [String] {
    previews(effects).compactMap { if case .fourth(_, let label) = $0 { label } else { nil } }
}

private func tabAnnouncements(_ effects: [ArrangerEffect]) -> [TabAnnouncement] {
    effects.compactMap { if case .tabAnnouncement(let announcement) = $0 { announcement } else { nil } }
}

private let noRoom = "Not enough room to dock here"

/// [a, w] grouped in one leaf, w selected, beside the Desktop tile. Returns the leaf and the group's content rect.
private func dockedGroup(at now: ContinuousClock.Instant) throws -> (Arranger, NodeID, content: Rect) {
    var bare = arranger([info(w), info(a, Rect(x: 700, y: 400, width: 150, height: 120))])
    try dockFlat([a], in: &bare)
    let leaf = try #require(bare.world[mainKey]?.tree.leaf(containing: a))
    try bare.world.edit(mainKey, history: &bare.history) { desk, _ throws(LayoutError) in
        try desk.desktop.remove(w)
        try desk.tree.group(w, into: leaf)
    }
    _ = bare.handle(.gap(8), now: now)
    let desk = try #require(bare.world[mainKey])
    let frame = try #require(try Planner.plan(desk: desk, area: area, gap: 8, mins: [:]).resolution.nodeRects[leaf])
    let content = TabBand.content(of: frame)
    _ = bare.handle(.event(.windowChanged(info(w, content))), now: now)  // w reached its tile: no window system says so here
    return (bare, leaf, content)
}

/// Presses `member`'s tab at its strip's centre, with no modifier, and drags out to `point` with `modifiers`.
private func tear(
    _ arranger: inout Arranger, _ member: WindowRef, to point: Point, _ modifiers: Modifiers, at now: ContinuousClock.Instant
) throws -> (Rect, [ArrangerEffect]) {
    let strip = try #require(arranger.tabs.shownStrips["main"]?.first?.frame, "no strip shown")
    var effects = arranger.handle(.pointer(PointerEvent(kind: .down, location: Point(x: strip.midX, y: strip.midY), pressTab: member)), now: now)
    effects += arranger.handle(pointer(.dragged, point.x, point.y, modifiers), now: now)
    return (strip, effects)
}

extension ArrangerFourthTests {
    /// RESEARCH Finding 2: a real press with ⌃ down never moves a window, so this serves apps that move their own.
    @Test func controlHeldAtThePressIsIgnoredUntilPressedAgain() async throws {
        var harness = await Harness.started(frames: [1: frameW])
        let grab = Point(x: frameW.midX, y: frameW.minY + 10)
        var effects = await harness.send(pointer(.down, grab.x, grab.y, .control, press: w))
        effects += await harness.send(pointer(.dragged, grab.x + 10, grab.y, .control))
        effects += await harness.send(.dragFrame(w.identity, shifted(frameW, 10)))
        effects += await harness.send(pointer(.dragged, 10, 310, .control))
        effects += await harness.send(.dragFrame(w.identity, shifted(frameW, 10 - grab.x, 310 - grab.y)))
        effects += await tick(&harness)
        #expect(fourthLabels(effects).isEmpty, "a fourth with ⌃ held since the press: \(effects)")
        #expect(guides(effects).isEmpty)
        guard case .dock? = previews(effects).first else {
            Issue.record("the row that applies did not act: \(effects)")
            return
        }

        _ = await harness.send(pointer(.flagsChanged, 10, 310))
        _ = await harness.send(pointer(.flagsChanged, 10, 310, .control))
        #expect(fourthLabels(await tick(&harness)) == ["1st column"], "⌃ pressed again in the same drag")
    }

    @Test func inHoldOptionModeControlAtThePressIsThePlainDrag() async throws {
        var (harness, tile) = try await twoDocked()
        await harness.send(.dragToDock(.holdOption))
        let grab = Point(x: tile.midX, y: tile.minY + 10)
        await harness.send(pointer(.down, grab.x, grab.y, .control, press: w))
        await harness.send(pointer(.dragged, grab.x + 40, grab.y, .control))
        await harness.send(.dragFrame(w.identity, shifted(tile, 40)))
        await harness.send(pointer(.dragged, 1300, 310, .control))
        await harness.send(.dragFrame(w.identity, shifted(tile, 1300 - grab.x, 310 - grab.y)))

        let up = await harness.send(pointer(.up, 1300, 310, .control))

        #expect(announcements(up) == [FourthCopy.floating])
        #expect(harness.arranger.world[mainKey]?.tree.state(of: w) == nil)
    }

    @Test(arguments: [
        (DragToDockMode.automatic, Modifiers([.control, .option]), "1st column"), (DragToDockMode.holdOption, Modifiers.control, "1st column"),
        (DragToDockMode.holdOption, Modifiers([.control, .option]), "1st column"), (DragToDockMode.holdOption, Modifiers([.control, .command]), "1st row"),
        (DragToDockMode.automatic, Modifiers([.control, .command, .option]), "1st row"),
        (DragToDockMode.holdOption, Modifiers([.control, .command, .option]), "1st row"),
    ] as [(DragToDockMode, Modifiers, String)])
    func optionWithControlChangesNothingInEitherMode(mode: DragToDockMode, modifiers: Modifiers, label: String) async throws {
        var harness = await Harness.started(frames: [1: frameW])
        await harness.send(.dragToDock(mode))
        _ = await controlDrag(&harness, w, from: frameW, to: Point(x: 10, y: 30), modifiers)
        #expect(fourthLabels(await tick(&harness)) == [label])
    }

    @Test(arguments: [(DragToDockMode.automatic, [String]()), (DragToDockMode.holdOption, [FourthCopy.floating])])
    func shiftWinsOverControl(mode: DragToDockMode, announced: [String]) async throws {
        var (harness, tile) = try await twoDocked()
        await harness.send(.dragToDock(mode))
        _ = await controlDrag(&harness, w, from: tile, to: Point(x: 1300, y: 310))
        _ = await tick(&harness)

        let pressed = await harness.send(pointer(.flagsChanged, 1300, 310, [.control, .shift]))
        #expect(pressed.contains(.fourthGuides([], displayUUID: "main")), "got \(pressed)")
        #expect(pressed.contains(.preview(nil, displayUUID: "main")))
        #expect(fourthLabels(await tick(&harness)).isEmpty)

        let up = await harness.send(pointer(.up, 1300, 310, [.control, .shift]))
        #expect(announcements(up) == announced)
        #expect(harness.arranger.world[mainKey]?.tree.state(of: w) == nil, "the window did not float")
    }

    @Test(arguments: [DragToDockMode.automatic, .holdOption])
    func aReleaseInsideTheDwellFollowsTheMissRules(mode: DragToDockMode) async throws {
        var floating = await Harness.started(frames: [1: frameW])
        await floating.send(.dragToDock(mode))
        _ = await controlDrag(&floating, w, from: frameW, to: Point(x: 10, y: 310))
        let world = floating.arranger.world[mainKey]?.tree, before = floating.arranger.history.depth(for: mainKey)
        let up = await floating.send(pointer(.up, 10, 310, .control))
        #expect(floating.arranger.world[mainKey]?.tree == world, "it docked")
        #expect(floating.arranger.history.depth(for: mainKey) == before)
        #expect(announcements(up).isEmpty)

        var (docked, tile) = try await twoDocked()
        await docked.send(.dragToDock(mode))
        _ = await controlDrag(&docked, w, from: tile, to: Point(x: 1300, y: 310))
        let depth = docked.arranger.history.depth(for: mainKey)
        let back = await docked.send(pointer(.up, 1300, 310, .control))
        #expect(setFrames(back)[w] == tile, "no snap back: \(back)")
        #expect(docked.arranger.world[mainKey]?.tree.state(of: w) == .present)
        #expect(docked.arranger.history.depth(for: mainKey) == depth)
        #expect(announcements(back).isEmpty, "\(back)")
    }

    @Test func controlReleasedInAutomaticModeGivesTheRowThatNowApplies() async throws {
        var harness = await Harness.started(frames: [1: frameW])
        _ = await controlDrag(&harness, w, from: frameW, to: Point(x: 10, y: 310))
        _ = await tick(&harness)

        _ = await harness.send(pointer(.flagsChanged, 10, 310))

        guard case .dock? = previews(await tick(&harness)).first else {
            Issue.record("no region preview after ⌃ was released")
            return
        }
    }

    @Test func controlReleasedInHoldOptionModeIsThePlainDragAtOnce() async throws {
        var (harness, tile) = try await twoDocked()
        await harness.send(.dragToDock(.holdOption))
        _ = await controlDrag(&harness, w, from: tile, to: Point(x: 1300, y: 310))
        _ = await harness.send(pointer(.flagsChanged, 1300, 310))

        let up = await harness.send(pointer(.up, 1300, 310))

        #expect(announcements(up) == [FourthCopy.floating])
        #expect(harness.arranger.world[mainKey]?.tree.state(of: w) == nil)
    }

    @Test func withZoomOffADropThatDoesNotFitIsBlockedAndRefusedWithoutABeep() throws {
        let start = ContinuousClock.now
        var bare = arranger([info(w, minimum: huge)])
        _ = controlDrag(&bare, w, from: frameW, to: Point(x: 10, y: 310), at: start)
        let loose = try fourthFrame(bare, w, .first, .horizontal)
        let shown = bare.handle(.tick, now: start + .milliseconds(150))
        #expect(previews(shown) == [.blocked(loose)], "tick gave \(shown)")
        let depth = bare.history.depth(for: mainKey)

        let up = bare.handle(pointer(.up, 10, 310, .control), now: start + .milliseconds(200))

        #expect(announcements(up) == [noRoom])
        #expect(!up.contains(.beep), "a refused drop never beeps")
        #expect(bare.world[mainKey]?.tree.state(of: w) == nil)
        #expect(bare.history.depth(for: mainKey) == depth)
    }

    @Test func withZoomOnADropThatDoesNotFitCollapsesWithItsOwnCopy() throws {
        let start = ContinuousClock.now
        var bare = arranger([info(w, minimum: huge)], zoom: true)
        _ = controlDrag(&bare, w, from: frameW, to: Point(x: 10, y: 310), at: start)
        let loose = try fourthFrame(bare, w, .first, .horizontal)
        let shown = bare.handle(.tick, now: start + .milliseconds(150))
        #expect(previews(shown) == [.collapsed(loose, label: CollapseCopy.draggedLabel)], "tick gave \(shown)")
        let depth = bare.history.depth(for: mainKey)

        let up = bare.handle(pointer(.up, 10, 310, .control), now: start + .milliseconds(200))

        #expect(announcements(up) == [CollapseCopy.dockedAnnouncement(dragged: true, others: 0)])
        #expect(bare.world[mainKey]?.tree.state(of: w) == .present)
        #expect(bare.history.depth(for: mainKey) == depth + 1)
    }

    @Test func aWholeGroupDragMovesTheGroupAsOneChild() throws {
        let start = ContinuousClock.now
        var (bare, _, content) = try dockedGroup(at: start)
        _ = controlDrag(&bare, w, from: content, to: Point(x: 1300, y: 310), at: start)
        let candidate = try #require(try bare.dropping(w, on: mainKey, at: .fourth(.fourth, .horizontal)).world[mainKey])
        let leaf = try #require(candidate.tree.leaf(containing: w))
        let frame = try #require(try Planner.plan(desk: candidate, area: area, gap: 8, mins: [:]).resolution.nodeRects[leaf])

        let shown = bare.handle(.tick, now: start + .milliseconds(150))
        #expect(previews(shown) == [.fourth(frame, label: "4th column")], "tick gave \(shown)")
        let depth = bare.history.depth(for: mainKey)

        let up = bare.handle(pointer(.up, 1300, 310, .control), now: start + .milliseconds(200))

        let desk = try #require(bare.world[mainKey])
        #expect(desk.tree.leaf(containing: w) == desk.tree.leaf(containing: a), "the group came apart")
        expectWeights(try rootWeights(bare), [3.0 / 4, 1.0 / 4])
        #expect(bare.history.depth(for: mainKey) == depth + 1)
        #expect(announcements(up) == ["Docked to 4th column"])
    }

    @Test func aTornOffTabDocksAloneAndAnnouncesBoth() throws {
        let start = ContinuousClock.now
        var (bare, _, _) = try dockedGroup(at: start)
        _ = try tear(&bare, a, to: Point(x: 1300, y: 310), .control, at: start)
        let candidate = try #require(try bare.dropping(a, on: mainKey, at: .fourth(.fourth, .horizontal)).world[mainKey])
        let frame = try #require(try Planner.plan(desk: candidate, area: area, gap: 8, mins: [:]).frames[a])

        let shown = bare.handle(.tick, now: start + .milliseconds(150))
        #expect(previews(shown) == [.fourth(frame, label: "4th column")], "tick gave \(shown)")

        let up = bare.handle(pointer(.up, 1300, 310, .control), now: start + .milliseconds(200))

        let desk = try #require(bare.world[mainKey])
        #expect(desk.tree.node(try #require(desk.tree.leaf(containing: a))) == .panel(a), "it did not dock alone")
        #expect(announcements(up) == ["Docked to 4th column"])
        #expect(tabAnnouncements(up) == [.movedOut(dissolved: true)])
    }

    @Test func aTornOffTabBackOverItsStripShowsNothingAndCancels() throws {
        let start = ContinuousClock.now
        var (bare, _, _) = try dockedGroup(at: start)
        let (strip, _) = try tear(&bare, a, to: Point(x: 1300, y: 310), .control, at: start)
        _ = bare.handle(.tick, now: start + .milliseconds(150))
        let world = bare.world

        var effects = bare.handle(pointer(.dragged, strip.midX, strip.midY, .control), now: start + .milliseconds(160))
        effects += bare.handle(.tick, now: start + .milliseconds(320))

        #expect(previews(effects).isEmpty, "got \(effects)")
        #expect(effects.contains(.fourthGuides([], displayUUID: "main")), "got \(effects)")
        _ = bare.handle(pointer(.up, strip.midX, strip.midY, .control), now: start + .milliseconds(330))
        #expect(bare.world == world, "the cancel changed something")
    }

    @Test func aDropOnAnotherDisplayLandsOnThatDesk() throws {
        let start = ContinuousClock.now
        let side = DisplayInfo(
            uuid: "side", frame: Rect(x: 1440, y: 0, width: 1920, height: 1080), visibleFrame: Rect(x: 1440, y: 0, width: 1920, height: 1080),
            currentSpaceID: nil)
        let sideKey = DeskKey(displayUUID: "side", spaceID: nil)
        var bare = Arranger()
        _ = bare.handle(.inventory(WindowInventory(displays: [mainDisplay, side], windows: [info(w)], initialRefreshComplete: true)), now: start)
        _ = controlDrag(&bare, w, from: frameW, to: Point(x: 10, y: 310), at: start)
        _ = bare.handle(.tick, now: start + .milliseconds(150))

        let crossed = bare.handle(pointer(.dragged, 1500, 310, .control), now: start + .milliseconds(160))
        #expect(crossed.contains(.preview(nil, displayUUID: "main")), "got \(crossed)")
        #expect(crossed.contains(.fourthGuides([], displayUUID: "main")), "got \(crossed)")
        let candidate = try #require(try bare.dropping(w, on: sideKey, at: .fourth(.first, .horizontal)).world[sideKey])
        let frame = try #require(try Planner.plan(desk: candidate, area: side.visibleFrame, gap: 8, mins: [:]).frames[w])
        let shown = bare.handle(.tick, now: start + .milliseconds(310))
        #expect(shown.contains(.preview(.fourth(frame, label: "1st column"), displayUUID: "side")), "got \(shown)")
        let depth = bare.history.depth(for: sideKey), mainDepth = bare.history.depth(for: mainKey)

        _ = bare.handle(pointer(.up, 1500, 310, .control), now: start + .milliseconds(320))

        #expect(bare.deskKey(of: w) == sideKey)
        #expect(bare.world[sideKey]?.tree.state(of: w) == .present)
        #expect(bare.history.depth(for: sideKey) == depth + 1)
        #expect(bare.history.depth(for: mainKey) == mainDepth)
    }

    @Test func aPointerOnNoDisplayShowsNoGuidesAndMisses() async throws {
        var harness = await Harness.started(frames: [1: frameW])
        var effects = await controlDrag(&harness, w, from: frameW, to: Point(x: -5000, y: 310))
        effects += await tick(&harness)
        #expect(guides(effects).isEmpty, "got \(effects)")
        #expect(fourthLabels(effects).isEmpty)
        let depth = harness.arranger.history.depth(for: mainKey)

        let up = await harness.send(pointer(.up, -5000, 310, .control))

        #expect(harness.arranger.world[mainKey]?.tree.state(of: w) == nil)
        #expect(harness.arranger.history.depth(for: mainKey) == depth)
        #expect(announcements(up).isEmpty)
    }

    @Test func aPointerAboveTheVisibleFramePicksTheNearestZone() async throws {
        var harness = await Harness.started(frames: [1: frameW])
        _ = await controlDrag(&harness, w, from: frameW, to: Point(x: 700, y: 5), [.control, .command])
        #expect(fourthLabels(await tick(&harness)) == ["1st row"])
    }

    @Test func aDockedWindowReleasedOnTheZoneItHoldsKeepsItsFrame() async throws {
        var harness = await Harness.started(frames: [1: frameW])
        await harness.send(.command(.dockFourth(.fourth, .horizontal), focused: w))
        let tile = try #require(await harness.frame(w))
        _ = await controlDrag(&harness, w, from: tile, to: Point(x: 1300, y: 310))
        #expect(previews(await tick(&harness)) == [.fourth(tile, label: "4th column")])

        let up = await harness.send(pointer(.up, 1300, 310, .control))

        #expect(setFrames(up)[w] == tile, "got \(up)")
        #expect(!announcements(up).contains(noRoom) && !up.contains(.beep))
        #expect(harness.arranger.world[mainKey]?.tree.state(of: w) == .present)
    }

    @Test func excludedOrNeverDockWindowsGetNoSession() {
        let start = ContinuousClock.now
        var bare = arranger([info(a, frameW, excluded: true), info(b, frameW, kind: .neverDock(.subrole))])
        for window in [a, b] {
            let effects = controlDrag(&bare, window, from: frameW, to: Point(x: 10, y: 310), at: start)
                + bare.handle(.tick, now: start + .milliseconds(150))
            #expect(effects.isEmpty, "\(window) got \(effects)")
            #expect(bare.drag == nil)
        }
    }

    @Test func withNoControlHeldADragGivesThePhase3Result() async throws {
        var harness = await Harness.started(frames: [1: frameW])
        var effects = await controlDrag(&harness, w, from: frameW, to: Point(x: 10, y: 310), [])
        effects += await tick(&harness)
        #expect(guides(effects).isEmpty)
        guard case .dock? = previews(effects).first else {
            Issue.record("no region preview: \(effects)")
            return
        }
        let up = await harness.send(pointer(.up, 10, 310))
        #expect(announcements(up).isEmpty, "\(up)")
    }
}

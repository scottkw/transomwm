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

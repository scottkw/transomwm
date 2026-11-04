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
}

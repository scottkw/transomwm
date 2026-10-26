import PaneEngine
import PaneModel
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
private let names: [WindowRef: String] = [a: "a", b: "b", c: "c", f: "f"]
private let somewhere = Rect(x: 200, y: 200, width: 400, height: 300)

/// An Arranger whose main desk holds the layout `build` makes, re-attached from a saved World (so the shape does
/// not depend on where Dock would put each window). Every window in `frames` is tracked; those `build` does not
/// dock float on the Desktop at their frame. Then focused, in order: `focus`.
private func arranger(
    frames: [WindowRef: Rect], minimums: [WindowRef: Size] = [:], focus: [WindowRef] = [],
    _ build: (inout Desk, inout IDSource) throws(LayoutError) -> Void = { _, _ in }
) throws -> Arranger {
    var world = World()
    var history = UndoHistory()
    try world.addDesk(key)
    try world.edit(key, history: &history, build)
    var arranger = Arranger(gap: gap)
    _ = arranger.handle(.restore(world, homeFrames: [:]), now: .now)
    let windows = frames.sorted { $0.key.identity < $1.key.identity }.map { window, frame in
        WindowInfo(window: window, frame: frame, state: .present, displayUUID: "main", learnedMinimum: minimums[window])
    }
    _ = arranger.handle(.inventory(WindowInventory(displays: [display], windows: windows, initialRefreshComplete: true)), now: .now)
    for window in focus { _ = arranger.handle(.event(.windowFocused(window)), now: .now) }
    return arranger
}

/// "H[a,V[b,c],D]": the tree's shape with window names, the Desktop as D.
private func shape(_ tree: LayoutTree) -> String {
    func describe(_ id: NodeID) -> String {
        switch tree.node(id) {
        case .split(let axis, let children, _)?:
            (axis == .horizontal ? "H[" : "V[") + children.map(describe).joined(separator: ",") + "]"
        case .panel(let window)?: names[window] ?? "?"
        case .tabs(let windows, _)?: "T[" + windows.map { names[$0] ?? "?" }.joined(separator: ",") + "]"
        case .desktop?: "D"
        case nil: "nil"
        }
    }
    return tree.root.map(describe) ?? "empty"
}

private func leaf(_ desk: Desk, _ window: WindowRef) throws(LayoutError) -> NodeID {
    guard let id = desk.tree.leaf(containing: window) else { throw .windowNotFound(window) }
    return id
}

/// [a | b | Desktop]
private func row(_ desk: inout Desk, _ ids: inout IDSource) throws(LayoutError) {
    try desk.tree.insert(a, at: .left, of: .desktop, ids: &ids)
    try desk.tree.insert(b, at: .right, of: try leaf(desk, a), ids: &ids)
}

/// [a | V[b, c] | Desktop]
private func columns(_ desk: inout Desk, _ ids: inout IDSource) throws(LayoutError) {
    try row(&desk, &ids)
    try desk.tree.insert(c, at: .bottom, of: try leaf(desk, b), ids: &ids)
}

private func plan(_ arranger: Arranger, mins: [WindowRef: Size] = [:]) throws -> FramePlan {
    try Planner.plan(desk: try #require(arranger.world[key]), area: visible, gap: gap, mins: mins)
}

private func depth(_ arranger: Arranger) -> Int { arranger.history.depth(for: key) }

/// TILE-13, TILE-14, D-09, D-11: ⌃⌥⌘⇧ arrows move a docked window into the neighbouring tile, or snap a floating one
/// to that half of the Desktop tile.
@Suite struct ArrangerCommandTests {
    /// Next to a sibling on the move axis the near edge is the window's own slot, so it goes past the neighbour:
    /// the window takes the neighbour's place in the row (03-12 deviation; the near-edge insert changes nothing).
    @Test func movingLeftPastASiblingTakesItsPlaceInOneUndoStep() throws {
        var arranger = try arranger(frames: [a: somewhere, b: somewhere], row)
        let before = try plan(arranger)
        let oldA = try #require(before.frames[a])
        let history = depth(arranger)

        let effects = arranger.handle(.command(.moveOrSnap(.left), focused: b), now: .now)

        let desk = try #require(arranger.world[key])
        #expect(shape(desk.tree) == "H[b,a,D]")
        #expect(depth(arranger) == history + 1)
        let frames = setFrames(effects)
        let moved = try #require(frames[b], "b was not moved: \(effects)")
        #expect(frames[a] != nil)
        #expect(moved.minX >= oldA.minX - 1 && moved.maxX <= oldA.maxX + 1, "b \(moved) is not in a's old tile \(oldA)")
    }

    /// Across a split boundary the window docks on the neighbour's near edge.
    @Test func movingOutOfAColumnDocksOnTheNeighboursNearEdge() throws {
        var arranger = try arranger(frames: [a: somewhere, b: somewhere, c: somewhere], columns)
        let effects = arranger.handle(.command(.moveOrSnap(.left), focused: c), now: .now)
        #expect(shape(try #require(arranger.world[key]).tree) == "H[a,c,b,D]")
        #expect(setFrames(effects)[c] != nil)
    }

    @Test func aDesktopNeighbourTakesTheWindowOnItsNearEdge() throws {
        // V[H[a, b], Desktop]: the Desktop is below b.
        var arranger = try arranger(frames: [a: somewhere, b: somewhere]) { desk, ids throws(LayoutError) in
            try desk.tree.insert(a, at: .top, of: .desktop, ids: &ids)
            try desk.tree.insert(b, at: .right, of: try leaf(desk, a), ids: &ids)
        }
        #expect(shape(try #require(arranger.world[key]).tree) == "V[H[a,b],D]")
        _ = arranger.handle(.command(.moveOrSnap(.bottom), focused: b), now: .now)
        #expect(shape(try #require(arranger.world[key]).tree) == "V[a,b,D]")
    }

    @Test func withNoNeighbourAcrossTheEdgeItBeepsAndChangesNothing() throws {
        var arranger = try arranger(frames: [a: somewhere, b: somewhere], row)
        let world = arranger.world, history = arranger.history
        #expect(arranger.handle(.command(.moveOrSnap(.left), focused: a), now: .now) == [.beep])
        #expect(arranger.world == world && arranger.history == history)
    }

    @Test func aMoveThatLeavesAWindowWithoutRoomIsRefusedAndFlashesTheBlockedPreview() throws {
        // Side by side, a + c + b need 400 + 600 + 450 + 3 gaps + the Desktop: more than the 1424 pt row.
        let mins = [a: Size(width: 400, height: 100), b: Size(width: 450, height: 100), c: Size(width: 600, height: 100)]
        var arranger = try arranger(frames: [a: somewhere, b: somewhere, c: somewhere], minimums: mins, columns)
        let world = arranger.world, history = arranger.history
        let effects = arranger.handle(.command(.moveOrSnap(.left), focused: c), now: .now)
        #expect(Array(effects.prefix(2)) == [.beep, .announce(Arranger.noRoom)])
        #expect(effects.count == 3 && effects.allSatisfy { if case .perform = $0 { false } else { true } })
        if case .flashBlocked(_, let uuid)? = effects.last { #expect(uuid == "main") } else { Issue.record("no flash: \(effects)") }
        #expect(arranger.world == world && arranger.history == history)
    }

    @Test func aFloatingWindowSnapsToThatHalfOfTheDesktopAsAFact() throws {
        var arranger = try arranger(frames: [a: somewhere, f: Rect(x: 900, y: 300, width: 300, height: 200)]) { desk, ids throws(LayoutError) in
            try desk.tree.insert(a, at: .left, of: .desktop, ids: &ids)
        }
        let desktop = try #require(try plan(arranger).desktopRect)
        let history = depth(arranger)
        let effects = arranger.handle(.command(.moveOrSnap(.left), focused: f), now: .now)
        let expected = Snap.frame(.leftHalf, window: Rect(x: 900, y: 300, width: 300, height: 200), desktop: desktop, gap: gap)
        #expect(setFrames(effects) == [f: expected])
        #expect(arranger.world[key]?.desktop.frame(of: f) == expected)
        #expect(depth(arranger) == history, "a snap is a floating-frame fact, not an undo step")
    }

    @Test func moveOrSnapIsAvailableForDockedAndFloatingWindowsAlike() throws {
        let arranger = try arranger(frames: [a: somewhere, f: somewhere]) { desk, ids throws(LayoutError) in
            try desk.tree.insert(a, at: .left, of: .desktop, ids: &ids)
        }
        #expect(arranger.isAvailable(.moveOrSnap(.left), focused: a))
        #expect(arranger.isAvailable(.moveOrSnap(.left), focused: f))
        #expect(!arranger.isAvailable(.moveOrSnap(.left), focused: nil))
        #expect(arranger.isFloating(f) && !arranger.isFloating(a) && !arranger.isFloating(nil))
    }
}

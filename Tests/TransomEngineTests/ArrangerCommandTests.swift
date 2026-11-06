import TransomEngine
import TransomModel
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
private let names: [WindowRef: String] = [a: "a", b: "b", c: "c", f: "f", ref(5): "x"]
private let somewhere = Rect(x: 200, y: 200, width: 400, height: 300)

/// An Arranger whose main desk holds the layout `build` makes, re-attached from a saved World (so the shape does
/// not depend on where Dock would put each window). Every window in `frames` is tracked; those `build` does not
/// dock float at their frame. Then focused, in order: `focus`. `empty` starts from a desk with no tree,
/// so a test holds before and after new desks lose their Desktop tile (08.1.1-09).
private func arranger(
    frames: [WindowRef: Rect], minimums: [WindowRef: Size] = [:], focus: [WindowRef] = [], extra: [WindowInfo] = [], empty: Bool = false,
    _ build: (inout Desk, inout IDSource) throws(LayoutError) -> Void = { _, _ in }
) throws -> Arranger {
    var world = empty ? try World(ids: IDSource(), desks: [key: Desk(tree: LayoutTree())]) : World()
    var history = UndoHistory()
    if !empty { try world.addDesk(key) }
    try world.edit(key, history: &history, build)
    var arranger = Arranger(gap: gap)
    _ = arranger.handle(.restore(world, homeFrames: [:]), now: .now)
    let windows = frames.sorted { $0.key.identity < $1.key.identity }.map { window, frame in
        WindowInfo(window: window, frame: frame, state: .present, displayUUID: "main", learnedMinimum: minimums[window])
    } + extra
    _ = arranger.handle(.inventory(WindowInventory(displays: [display], windows: windows, initialRefreshComplete: true)), now: .now)
    for window in focus { _ = arranger.handle(.event(.windowFocused(window)), now: .now) }
    return arranger
}

/// "H[a,V[b,c]]": the tree's shape with window names; "empty" for no tree.
private func shape(_ tree: LayoutTree) -> String {
    func describe(_ id: NodeID) -> String {
        switch tree.node(id) {
        case .split(let axis, let children, _)?:
            (axis == .horizontal ? "H[" : "V[") + children.map(describe).joined(separator: ",") + "]"
        case .panel(let window)?: names[window] ?? "?"
        case .tabs(let windows, _)?: "T[" + windows.map { names[$0] ?? "?" }.joined(separator: ",") + "]"
        case .spacer?: "_"
        case nil: "nil"
        }
    }
    return tree.root.map(describe) ?? "empty"
}

private func leaf(_ desk: Desk, _ window: WindowRef) throws(LayoutError) -> NodeID {
    guard let id = desk.tree.leaf(containing: window) else { throw .windowNotFound(window) }
    return id
}

/// [a | b]
private func row(_ desk: inout Desk, _ ids: inout IDSource) throws(LayoutError) {
    try desk.tree.applyDrop(.layoutEdge(.right), window: a, ids: &ids)
    try desk.tree.insert(b, at: .right, of: try leaf(desk, a), ids: &ids)
}

/// [a | V[b, c]]
private func columns(_ desk: inout Desk, _ ids: inout IDSource) throws(LayoutError) {
    try row(&desk, &ids)
    try desk.tree.insert(c, at: .bottom, of: try leaf(desk, b), ids: &ids)
}

private func plan(_ arranger: Arranger, mins: [WindowRef: Size] = [:]) throws -> FramePlan {
    try Planner.plan(desk: try #require(arranger.world[key]), area: visible, gap: gap, mins: mins)
}

private func depth(_ arranger: Arranger) -> Int { arranger.history.depth(for: key) }

/// TILE-13, TILE-14, D-09, D-11: ⌃⌥⌘⇧ arrows move a docked window into the neighbouring tile, or snap a floating one
/// to that half of the visible frame.
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
        #expect(shape(desk.tree) == "H[b,a]")
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
        #expect(shape(try #require(arranger.world[key]).tree) == "H[a,c,b]")
        #expect(setFrames(effects)[c] != nil)
    }

    @Test func aNeighbourBelowTakesTheWindowOnItsNearEdge() throws {
        // V[H[a, b], c]: c is below b.
        var arranger = try arranger(frames: [a: somewhere, b: somewhere, c: somewhere]) { desk, ids throws(LayoutError) in
            try desk.tree.applyDrop(.layoutEdge(.bottom), window: a, ids: &ids)
            try desk.tree.insert(b, at: .right, of: try leaf(desk, a), ids: &ids)
            try desk.tree.applyDrop(.layoutEdge(.bottom), window: c, ids: &ids)
        }
        #expect(shape(try #require(arranger.world[key]).tree) == "V[H[a,b],c]")
        _ = arranger.handle(.command(.moveOrSnap(.bottom), focused: b), now: .now)
        #expect(shape(try #require(arranger.world[key]).tree) == "V[a,b,c]")
    }

    @Test func withNoNeighbourAcrossTheEdgeItBeepsAndChangesNothing() throws {
        var arranger = try arranger(frames: [a: somewhere, b: somewhere], row)
        let world = arranger.world, history = arranger.history
        #expect(arranger.handle(.command(.moveOrSnap(.left), focused: a), now: .now) == [.beep])
        #expect(arranger.world == world && arranger.history == history)
    }

    @Test func aMoveThatLeavesAWindowWithoutRoomIsRefusedAndFlashesTheBlockedPreview() throws {
        // Side by side, a + c + b need 400 + 600 + 450 + 2 gaps: more than the 1424 pt row.
        let mins = [a: Size(width: 400, height: 100), b: Size(width: 450, height: 100), c: Size(width: 600, height: 100)]
        var arranger = try arranger(frames: [a: somewhere, b: somewhere, c: somewhere], minimums: mins, columns)
        let world = arranger.world, history = arranger.history
        let effects = arranger.handle(.command(.moveOrSnap(.left), focused: c), now: .now)
        #expect(Array(effects.prefix(2)) == [.beep, .announce(Arranger.noRoom)])
        #expect(effects.count == 3 && effects.allSatisfy { if case .perform = $0 { false } else { true } })
        if case .flashBlocked(_, let uuid)? = effects.last { #expect(uuid == "main") } else { Issue.record("no flash: \(effects)") }
        #expect(arranger.world == world && arranger.history == history)
    }

    /// 8.1.1 D-10: the half is of the visible frame, over the docked windows.
    @Test func aFloatingWindowSnapsToThatHalfOfTheScreenAsAFact() throws {
        var arranger = try arranger(frames: [a: somewhere, f: Rect(x: 900, y: 300, width: 300, height: 200)]) { desk, ids throws(LayoutError) in
            try desk.tree.applyDrop(.layoutEdge(.right), window: a, ids: &ids)
        }
        let history = depth(arranger)
        let effects = arranger.handle(.command(.moveOrSnap(.left), focused: f), now: .now)
        let expected = Snap.frame(.leftHalf, window: Rect(x: 900, y: 300, width: 300, height: 200), area: visible, gap: gap)
        #expect(setFrames(effects) == [f: expected])
        #expect(arranger.world[key]?.desktop.frame(of: f) == expected)
        #expect(depth(arranger) == history, "a snap is a floating-frame fact, not an undo step")
    }

    @Test func moveOrSnapIsAvailableForDockedAndFloatingWindowsAlike() throws {
        let arranger = try arranger(frames: [a: somewhere, f: somewhere]) { desk, ids throws(LayoutError) in
            try desk.tree.applyDrop(.layoutEdge(.right), window: a, ids: &ids)
        }
        #expect(arranger.isAvailable(.moveOrSnap(.left), focused: a))
        #expect(arranger.isAvailable(.moveOrSnap(.left), focused: f))
        #expect(!arranger.isAvailable(.moveOrSnap(.left), focused: nil))
        #expect(arranger.isFloating(f) && !arranger.isFloating(a) && !arranger.isFloating(nil))
    }
}

/// The weights of the split holding `window`'s leaf.
private func parentWeights(_ arranger: Arranger, _ window: WindowRef) throws -> [Double] {
    let tree = try #require(arranger.world[key]).tree
    let leaf = try #require(tree.leaf(containing: window))
    let parent = try #require(tree.parent(of: leaf))
    guard case .split(_, _, let weights)? = tree.node(parent) else { throw LayoutError.notASplit(parent) }
    return weights
}

/// TILE-11, TILE-12, TILE-13, TILE-14, D-32: swap with the previous window, grow and shrink, balance, rotate and flip,
/// and the other snap targets.
extension ArrangerCommandTests {
    @Test func swapPreviousExchangesTheFocusedWindowWithTheDockedOneFocusedBeforeIt() throws {
        var arranger = try arranger(frames: [a: somewhere, b: somewhere, f: somewhere], focus: [a, f, b], row)
        let history = depth(arranger)
        let effects = arranger.handle(.command(.swapPrevious, focused: b), now: .now)
        #expect(shape(try #require(arranger.world[key]).tree) == "H[b,a]")
        #expect(depth(arranger) == history + 1)
        #expect(setFrames(effects)[a] != nil && setFrames(effects)[b] != nil)
    }

    @Test func swapPreviousWithNoEarlierDockedWindowBeeps() throws {
        var arranger = try arranger(frames: [a: somewhere, b: somewhere, f: somewhere], focus: [f, b], row)
        let world = arranger.world
        #expect(!arranger.isAvailable(.swapPrevious, focused: b))
        #expect(arranger.handle(.command(.swapPrevious, focused: b), now: .now) == [.beep])
        #expect(arranger.world == world)
    }

    @Test func growAndShrinkMoveATenthOfTheSplitFromAndToTheSiblings() throws {
        // [a | b | c]: b has a sibling on each side.
        var arranger = try arranger(frames: [a: somewhere, b: somewhere, c: somewhere]) { desk, ids throws(LayoutError) in
            try row(&desk, &ids)
            try desk.tree.insert(c, at: .right, of: try leaf(desk, b), ids: &ids)
        }
        let start = try parentWeights(arranger, b)
        try #require(start.count == 3)
        _ = arranger.handle(.command(.growTile, focused: b), now: .now)
        let grown = try parentWeights(arranger, b)
        try #require(grown.count == 3)
        #expect(abs(grown[1] - (start[1] + 0.1)) < 1e-9)
        #expect(abs(grown[0] - grown[2]) < 1e-9, "the siblings did not give in proportion: \(grown)")
        _ = arranger.handle(.command(.shrinkTile, focused: b), now: .now)
        let shrunk = try parentWeights(arranger, b)
        #expect(zip(shrunk, start).allSatisfy { abs($0 - $1) < 1e-9 }, "\(shrunk) vs \(start)")
        #expect(depth(arranger) == 2)
    }

    /// c at its 800 pt minimum height leaves b, above it in the column, nothing to grow into. (A floater no longer
    /// sizes the Desktop tile, D-05, so the limit comes from a docked sibling.)
    @Test func growAtASizeLimitBeepsAndPushesNoUndoStep() throws {
        let mins = [c: Size(width: 100, height: 800)]
        var arranger = try arranger(frames: [a: somewhere, b: somewhere, c: somewhere], minimums: mins, columns)
        let world = arranger.world, history = arranger.history
        #expect(arranger.handle(.command(.growTile, focused: b), now: .now) == [.beep])
        #expect(arranger.world == world && arranger.history == history)
    }

    @Test func balanceEvensTheParentSplitAndFlipReversesIt() throws {
        var arranger = try arranger(frames: [a: somewhere, b: somewhere], row)
        _ = arranger.handle(.command(.growTile, focused: b), now: .now)
        _ = arranger.handle(.command(.balanceSplit, focused: b), now: .now)
        #expect(try parentWeights(arranger, b).allSatisfy { abs($0 - 1.0 / 2) < 1e-9 })
        _ = arranger.handle(.command(.flipSplit, focused: b), now: .now)
        #expect(shape(try #require(arranger.world[key]).tree) == "H[b,a]")
        #expect(depth(arranger) == 3)
    }

    @Test(arguments: [b, a])
    func rotateTurnsTheWholeLayoutFromTheRootAndTwiceRestoresIt(focused: WindowRef) throws {
        var arranger = try arranger(frames: [a: somewhere, b: somewhere, c: somewhere], columns)
        let original = try #require(arranger.world[key]).tree
        _ = arranger.handle(.command(.rotateSplit, focused: focused), now: .now)
        #expect(shape(try #require(arranger.world[key]).tree) == "V[a,H[b,c]]")
        _ = arranger.handle(.command(.rotateSplit, focused: focused), now: .now)
        #expect(arranger.world[key]?.tree == original)
        #expect(depth(arranger) == 2)
    }

    @Test(arguments: [Command.growTile, .shrinkTile, .balanceSplit, .rotateSplit, .flipSplit, .swapPrevious])
    func treeCommandsBeepForAFloatingWindow(command: Command) throws {
        var arranger = try arranger(frames: [a: somewhere, b: somewhere, f: somewhere], focus: [a, f], row)
        #expect(arranger.handle(.command(command, focused: f), now: .now) == [.beep])
    }

    /// 8.1.1 D-10: every target is on the visible frame, over the docked windows.
    @Test(arguments: [SnapTarget.leftThird, .centerThird, .rightThird, .topLeft, .topRight, .bottomLeft, .bottomRight, .maximize, .center])
    func snapPutsAFloatingWindowAtItsTargetAndADockedOneBeeps(target: SnapTarget) throws {
        let start = Rect(x: 900, y: 300, width: 300, height: 200)
        var arranger = try arranger(frames: [a: somewhere, f: start]) { desk, ids throws(LayoutError) in
            try desk.tree.applyDrop(.layoutEdge(.right), window: a, ids: &ids)
        }
        let expected = Snap.frame(target, window: start, area: visible, gap: gap)
        #expect(setFrames(arranger.handle(.command(.snap(target), focused: f), now: .now)) == [f: expected])
        #expect(arranger.world[key]?.desktop.frame(of: f) == expected)
        #expect(depth(arranger) == 0)
        #expect(arranger.handle(.command(.snap(target), focused: a), now: .now) == [.beep])
    }

    @Test func maximizeFillsTheVisibleFrameOnAnEmptyDesk() throws {
        var arranger = try arranger(frames: [f: Rect(x: 900, y: 300, width: 300, height: 200)], empty: true)
        let effects = arranger.handle(.command(.snap(.maximize), focused: f), now: .now)
        let filled = Rect(x: visible.minX + gap, y: visible.minY + gap, width: visible.width - 2 * gap, height: visible.height - 2 * gap)
        #expect(setFrames(effects) == [f: filled])
        #expect(depth(arranger) == 0)
    }
}

private func notices(_ effects: [ArrangerEffect]) -> [Notice] {
    effects.compactMap { if case .notice(let notice) = $0 { notice } else { nil } }
}

/// TILE-16, D-13: Arrange All Windows and Float All Windows, each one undo step.
extension ArrangerCommandTests {
    /// Screen order is top to bottom, then left to right: b (100, 100), a (500, 100), c (100, 600). On the empty desk b
    /// becomes the root; each other docks on the longer side of the largest tile (ties to the smaller NodeID).
    @Test func arrangeAllDocksEveryFloatingWindowInScreenOrderAsOneUndoStep() throws {
        let size = (width: 300.0, height: 200.0)
        var arranger = try arranger(frames: [
            a: Rect(x: 500, y: 100, width: size.width, height: size.height), b: Rect(x: 100, y: 100, width: size.width, height: size.height),
            c: Rect(x: 100, y: 600, width: size.width, height: size.height),
        ])
        #expect(arranger.isAvailable(.arrangeAll, focused: nil))
        let effects = arranger.handle(.command(.arrangeAll, focused: nil), now: .now)
        let desk = try #require(arranger.world[key])
        // b fills the frame; a goes right of it; then b (the smaller NodeID of two equal tall tiles) over c.
        #expect(shape(desk.tree) == "H[V[b,c],a]")
        #expect(desk.desktop.windows.isEmpty)
        #expect(notices(effects).isEmpty)
        #expect(depth(arranger) == 1)
        _ = arranger.handle(.command(.undo, focused: nil), now: .now)
        let undone = try #require(arranger.world[key])
        #expect(shape(undone.tree) == "empty" && Set(undone.desktop.windows.map(\.window)) == [a, b, c])
    }

    /// On an empty desk the first window in screen order becomes the root; the rest dock beside the largest tile.
    @Test func arrangeAllOnAnEmptyDeskStartsTheLayoutWithTheFirstWindow() throws {
        let size = (width: 300.0, height: 200.0)
        let frames = [
            a: Rect(x: 100, y: 100, width: size.width, height: size.height), b: Rect(x: 500, y: 100, width: size.width, height: size.height),
            c: Rect(x: 100, y: 600, width: size.width, height: size.height),
        ]
        var arranger = try arranger(frames: frames, empty: true)
        try #require(arranger.world[key]?.tree.root == nil, "precondition: the desk is not empty")

        let effects = arranger.handle(.command(.arrangeAll, focused: nil), now: .now)

        let desk = try #require(arranger.world[key])
        // a fills the frame; b goes right of it; then a (the smaller NodeID of two equal tall tiles) over c.
        #expect(shape(desk.tree) == "H[V[a,c],b]", "\(effects)")
        #expect(desk.desktop.windows.isEmpty)
        #expect(!effects.contains(.beep) && notices(effects).isEmpty)
        #expect(depth(arranger) == 1)
        _ = arranger.handle(.command(.undo, focused: nil), now: .now)
        let undone = try #require(arranger.world[key])
        #expect(undone.tree.root == nil)
        for window in [a, b, c] { #expect(undone.desktop.frame(of: window) == frames[window]) }
    }

    /// a alone, at least 500 wide and 600 tall. b (at least 1000 wide) does not fit beside a, the largest tile, on its
    /// longer side; c, with no minimum, docks there.
    @Test func aWindowThatDoesNotFitStaysFloatingAndIsCounted() throws {
        var arranger = try arranger(
            frames: [a: somewhere, b: Rect(x: 100, y: 650, width: 1000, height: 150), c: Rect(x: 1200, y: 700, width: 200, height: 150)],
            minimums: [a: Size(width: 500, height: 600), b: Size(width: 1000, height: 100)]
        ) { desk, ids throws(LayoutError) in
            try desk.tree.applyDrop(.layoutEdge(.bottom), window: a, ids: &ids)
        }
        let effects = arranger.handle(.command(.arrangeAll, focused: nil), now: .now)
        let desk = try #require(arranger.world[key])
        #expect(shape(desk.tree) == "H[a,c]" && desk.desktop.contains(b), "\(shape(desk.tree)) \(effects)")
        #expect(notices(effects) == [.arrangeLeftovers(count: 1)])
        #expect(depth(arranger) == 1)
    }

    @Test func whenNothingFitsArrangeAllBeepsAndFlashesTheFirstWindowsBlockedFrame() throws {
        var arranger = try arranger(frames: [b: Rect(x: 500, y: 100, width: 300, height: 200)], minimums: [b: Size(width: 100, height: 900)])
        let world = arranger.world, history = arranger.history
        let effects = arranger.handle(.command(.arrangeAll, focused: nil), now: .now)
        #expect(effects.first == .beep)
        #expect(effects.contains { if case .flashBlocked(_, "main") = $0 { true } else { false } }, "got \(effects)")
        #expect(arranger.world == world && arranger.history == history)
    }

    @Test func excludedNeverDockAndMinimisedWindowsAreNotArranged() throws {
        let x = ref(5)
        var arranger = try arranger(
            frames: [a: Rect(x: 100, y: 100, width: 300, height: 200), f: Rect(x: 500, y: 100, width: 300, height: 200)],
            extra: [
                WindowInfo(window: c, frame: somewhere, state: .present, displayUUID: "main", kind: .neverDock(.subrole)),
                WindowInfo(window: x, frame: somewhere, state: .present, displayUUID: "main", isExcluded: true),
            ])
        _ = arranger.handle(.event(.windowStateChanged(f, .absent)), now: .now)
        _ = arranger.handle(.command(.arrangeAll, focused: nil), now: .now)
        let desk = try #require(arranger.world[key])
        #expect(desk.tree.windows == [a])
        #expect(desk.desktop.contains(f) && arranger.deskKey(of: c) == nil && arranger.deskKey(of: x) == nil)
    }

    @Test func floatAllFloatsEveryDockedWindowAtItsTileAsOneUndoStep() throws {
        var arranger = try arranger(frames: [a: somewhere, b: somewhere, c: somewhere], columns)
        let tiles = try plan(arranger).frames
        #expect(arranger.isAvailable(.floatAll, focused: nil))
        let effects = arranger.handle(.command(.floatAll, focused: nil), now: .now)
        let desk = try #require(arranger.world[key])
        #expect(shape(desk.tree) == "empty")
        for window in [a, b, c] { #expect(desk.desktop.frame(of: window) == tiles[window]) }
        #expect(notices(effects) == [.floatedAll(count: 3)])
        #expect(depth(arranger) == 1)
        _ = arranger.handle(.command(.undo, focused: nil), now: .now)
        #expect(shape(try #require(arranger.world[key]).tree) == "H[a,V[b,c]]")
    }

    @Test func floatAllWithNothingDockedBeeps() throws {
        var arranger = try arranger(frames: [f: somewhere])
        #expect(arranger.handle(.command(.floatAll, focused: nil), now: .now) == [.beep])
    }
}

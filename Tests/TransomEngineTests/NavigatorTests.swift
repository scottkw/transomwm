import TransomEngine
import TransomModel
import TransomTestSupport
import Testing

private let pid: Int32 = 900
private let bundleID = "com.example.arranger"
private let key = DeskKey(displayUUID: "main", spaceID: nil)

private func ref(_ id: UInt32) -> WindowRef {
    WindowRef(identity: WindowIdentity(windowID: id, pid: pid, bundleID: bundleID))
}

private let a = ref(1), b = ref(2), c = ref(3)

/// [a | V[b, c] | Desktop] (with `four`, V[b, c, d]) re-attached from a saved World (as ArrangerFocusTests), zoom on.
private func nested(four: Bool = false) async throws -> Harness {
    var frames: [UInt32: Rect] = [
        1: Rect(x: 40, y: 80, width: 320, height: 232), 2: Rect(x: 1000, y: 100, width: 300, height: 200),
        3: Rect(x: 1000, y: 600, width: 300, height: 200),
    ]
    if four { frames[4] = Rect(x: 1000, y: 700, width: 300, height: 150) }
    var harness = await Harness.started(frames: frames)
    var world = World()
    var history = UndoHistory()
    try world.addDesk(key)
    try world.edit(key, history: &history) { desk, ids throws(LayoutError) in
        try desk.tree.insert(a, at: .left, of: .desktop, ids: &ids)
        guard let left = desk.tree.leaf(containing: a) else { throw .windowNotFound(a) }
        try desk.tree.insert(b, at: .right, of: left, ids: &ids)
        guard let middle = desk.tree.leaf(containing: b) else { throw .windowNotFound(b) }
        try desk.tree.insert(c, at: .bottom, of: middle, ids: &ids)
        guard four, let bottom = desk.tree.leaf(containing: c) else { return }
        try desk.tree.insert(ref(4), at: .bottom, of: bottom, ids: &ids)
    }
    harness.arranger = Arranger()
    await harness.send(.restore(world, homeFrames: [:]))
    await harness.send(.inventory(await harness.fake.inventory()))
    await harness.send(.zoomEnabled(true))
    #expect(harness.arranger.world[key]?.tree.windows == (four ? [a, b, c, ref(4)] : [a, b, c]))
    return harness
}

private func leaf(_ window: WindowRef, _ harness: Harness) throws -> NodeID {
    try #require(harness.arranger.world[key]?.tree.leaf(containing: window))
}

private func column(_ harness: Harness) throws -> NodeID {
    try #require(harness.arranger.world[key]?.tree.parent(of: try leaf(b, harness)))
}

private func moves(_ effects: [ArrangerEffect]) -> [CameraMove] {
    effects.compactMap { if case .cameraMove(let move) = $0 { move } else { nil } }
}

private func infos(_ effects: [ArrangerEffect]) -> [String] {
    effects.compactMap { if case .info(let text) = $0 { text } else { nil } }
}

extension Harness {
    /// Sends a camera command on the main display.
    @discardableResult
    fileprivate mutating func camera(
        _ command: CameraCommand, on uuid: String = "main", focused: WindowRef? = nil, pointer: Point? = nil
    ) async -> [ArrangerEffect] {
        await send(.camera(command, displayUUID: uuid, focused: focused, pointer: pointer))
    }

    /// Settles every camera move in `effects`, oldest first; returns the last settle's effects.
    @discardableResult
    fileprivate mutating func settle(_ effects: [ArrangerEffect]) async -> [ArrangerEffect] {
        var last: [ArrangerEffect] = []
        for move in moves(effects) { last = await send(.cameraSettle(displayUUID: move.displayUUID, moveID: move.id)) }
        return last
    }

    /// Moves that display's camera to `target` and settles.
    fileprivate mutating func go(_ target: ViewTarget, on uuid: String = "main") async throws {
        let effects = await send(.zoomTo(target, displayUUID: uuid))
        #expect(moves(effects).count == 1)
        await settle(effects)
        #expect(arranger.view(on: uuid) == target)
    }

    /// Runs a camera command that must move, settles it and returns where it went.
    fileprivate mutating func step(_ command: CameraCommand, on uuid: String = "main", focused: WindowRef? = nil) async -> ViewTarget? {
        let effects = await camera(command, on: uuid, focused: focused)
        await settle(effects)
        return moves(effects).first?.to
    }
}

/// The one refusal shape (UI-SPEC Surface 1): beep, the announcement, and a log line naming the command.
private func expectRefused(_ effects: [ArrangerEffect], _ announcement: String, command: String, sourceLocation: SourceLocation = #_sourceLocation) {
    #expect(effects.count == 3, sourceLocation: sourceLocation)
    #expect(effects.first == .beep, sourceLocation: sourceLocation)
    #expect(effects.contains(.announce(announcement)), sourceLocation: sourceLocation)
    #expect(infos(effects).first?.hasPrefix("refused \(command)") == true, sourceLocation: sourceLocation)
}

/// ZOOM-01, ZOOM-02: zoom out, step out and step in through the engine, with UI-SPEC Surface 1 refusals.
@Suite struct NavigatorTests {
    @Test func zoomOutAllFromANodeTargetsHome() async throws {
        var harness = try await nested()
        try await harness.go(.node(try leaf(b, harness)))

        let move = try #require(moves(await harness.camera(.zoomOutAll)).first)

        #expect(move.to == .home)
    }

    @Test func zoomOutAllAtHomeIsRefused() async throws {
        var harness = try await nested()

        expectRefused(await harness.camera(.zoomOutAll), "Already showing all windows", command: "zoomOutAll")
    }

    @Test func stepOutGoesToTheParent() async throws {
        var harness = try await nested()
        try await harness.go(.node(try leaf(b, harness)))

        let move = try #require(moves(await harness.camera(.stepOut)).first)

        #expect(move.to == .node(try column(harness)))
    }

    @Test func stepOutFromATopLevelChildGoesHome() async throws {
        var harness = try await nested()
        try await harness.go(.node(try column(harness)))

        #expect(moves(await harness.camera(.stepOut)).first?.to == .home)
    }

    @Test func stepOutAtHomeIsRefused() async throws {
        var harness = try await nested()

        expectRefused(await harness.camera(.stepOut), "Already showing all windows", command: "stepOut")
    }

    @Test func stepInGoesTowardTheFocusedWindow() async throws {
        var harness = try await nested()

        let first = await harness.camera(.stepIn, focused: c)
        #expect(moves(first).first?.to == .node(try column(harness)))
        await harness.settle(first)

        #expect(moves(await harness.camera(.stepIn, focused: c)).first?.to == .node(try leaf(c, harness)))
    }

    @Test func stepInWithoutAFocusedWindowInViewGoesTowardThePointer() async throws {
        var harness = try await nested()
        // At home the pointer over a's tile picks a.
        #expect(moves(await harness.camera(.stepIn, pointer: Point(x: 100, y: 400))).first?.to == .node(try leaf(a, harness)))

        try await harness.go(.node(try column(harness)))
        // In V's view, b is the top half of the display and c the bottom; a is focused but not in view.
        let move = moves(await harness.camera(.stepIn, focused: a, pointer: Point(x: 700, y: 800))).first
        #expect(move?.to == .node(try leaf(c, harness)))
    }

    @Test func stepInOtherwiseGoesToTheLargestChild() throws {
        let one = NodeID(raw: 1), two = NodeID(raw: 2), three = NodeID(raw: 3)
        let tree = try LayoutTree(
            root: one,
            nodes: [one: .split(axis: .horizontal, children: [two, three, .desktop], weights: [0.4, 0.4, 0.2]), two: .panel(a), three: .panel(b),
                .desktop: .desktop(hidden: false)],
            states: [a.identity: .present, b.identity: .present])
        func resolution(_ widthTwo: Double, _ widthThree: Double) -> Resolution {
            Resolution(nodeRects: [
                one: Rect(x: 0, y: 0, width: 1000, height: 500), two: Rect(x: 0, y: 0, width: widthTwo, height: 500),
                three: Rect(x: widthTwo, y: 0, width: widthThree, height: 500), .desktop: Rect(x: 900, y: 0, width: 100, height: 500),
            ])
        }

        #expect(Navigator.stepIn(view: .home, tree: tree, resolution: resolution(300, 600), focusedLeaf: nil, pointer: nil) == three)
        #expect(Navigator.stepIn(view: .home, tree: tree, resolution: resolution(450, 450), focusedLeaf: nil, pointer: nil) == two)
        #expect(Navigator.stepIn(view: .node(two), tree: tree, resolution: resolution(450, 450), focusedLeaf: nil, pointer: nil) == nil)
    }

    @Test func stepInOnASingleLeafIsRefused() async throws {
        var harness = try await nested()
        try await harness.go(.node(try leaf(a, harness)))

        expectRefused(await harness.camera(.stepIn, focused: a), "Nothing to zoom in to", command: "stepIn")
    }

    @Test func cameraCommandsAreUnavailableWithZoomOffPausedOrNoDesk() async throws {
        var harness = try await nested()
        let main = CommandContext(focused: nil, ready: true, displayUUID: "main")
        #expect(harness.arranger.availability(.camera(.stepIn), context: main))
        #expect(!harness.arranger.availability(.camera(.zoomOutAll), context: main), "zoom out is on at home")
        #expect(!harness.arranger.availability(.camera(.stepIn), context: CommandContext(focused: nil, ready: false, displayUUID: "main")))
        #expect(!harness.arranger.availability(.camera(.stepIn), context: CommandContext(focused: nil, ready: true)))
        #expect(!harness.arranger.availability(.camera(.stepIn), context: CommandContext(focused: nil, ready: true, displayUUID: "fullscreen-display")))

        await harness.send(.setPaused(.user, true))
        #expect(!harness.arranger.availability(.camera(.stepIn), context: main))
        expectRefused(await harness.camera(.stepIn), "Arranging is paused", command: "stepIn")
        await harness.send(.setPaused(.user, false))

        await harness.send(.zoomEnabled(false))
        #expect(!harness.arranger.availability(.camera(.stepIn), context: main))
        #expect(moves(await harness.camera(.stepIn)).isEmpty)
    }

    @Test func aCommandWithoutADisplayFaults() async throws {
        var harness = try await nested()

        let effects = await harness.send(.command(.camera(.stepIn), focused: nil))

        #expect(effects.count == 1)
        #expect(effects.allSatisfy { if case .fault = $0 { true } else { false } })
    }

    @Test func noDeskAnnouncesFullScreen() async throws {
        var harness = try await nested()

        let effects = await harness.send(.camera(.stepIn, displayUUID: "fullscreen-display", focused: nil, pointer: nil))

        expectRefused(effects, "Zoom isn't available in full screen", command: "stepIn")
    }
}


private let d = ref(4)
private let n = (0...7).map { NodeID(raw: UInt64($0)) }

/// n1 = V[n2 = H[n3, n4], n6 = H[n5, n7]]: two rows of two leaves, the bottom row cut at x = `cut`.
private func rows(cut: Double) throws -> (LayoutTree, Resolution) {
    let tree = try LayoutTree(
        root: n[1],
        nodes: [
            n[1]: .split(axis: .vertical, children: [n[2], n[6]], weights: [0.5, 0.5]),
            n[2]: .split(axis: .horizontal, children: [n[3], n[4]], weights: [0.5, 0.5]),
            n[6]: .split(axis: .horizontal, children: [n[5], n[7]], weights: [0.5, 0.5]),
            n[3]: .panel(a), n[4]: .panel(b), n[5]: .panel(c), n[7]: .panel(d),
        ],
        states: [a.identity: .present, b.identity: .present, c.identity: .present, d.identity: .present])
    let resolution = Resolution(nodeRects: [
        n[1]: Rect(x: 0, y: 0, width: 1000, height: 1000), n[2]: Rect(x: 0, y: 0, width: 1000, height: 496),
        n[6]: Rect(x: 0, y: 504, width: 1000, height: 496),
        n[3]: Rect(x: 0, y: 0, width: 496, height: 496), n[4]: Rect(x: 504, y: 0, width: 496, height: 496),
        n[5]: Rect(x: 0, y: 504, width: cut - 4, height: 496), n[7]: Rect(x: cut + 4, y: 504, width: 996 - cut, height: 496),
    ])
    return (tree, resolution)
}

/// ZOOM-09, ZOOM-10, ZOOM-11: Move View, Frame Focused Window and Frame Desktop with toggle-back.
@Suite struct PanAndFrameNavigatorTests {
    @Test func panMovesToTheSameDepthNeighbourWithTheLongestSharedEdge() async throws {
        // n3 spans 0..496: with the bottom row cut at 200 it shares 292 pt with n7 and 196 with n5.
        let (tree, wide) = try rows(cut: 200)
        #expect(Navigator.pan(view: .node(n[3]), edge: .bottom, tree: tree, homeResolution: wide, gap: 8, recency: []) == n[7])
        let (_, narrow) = try rows(cut: 400)
        #expect(Navigator.pan(view: .node(n[3]), edge: .bottom, tree: tree, homeResolution: narrow, gap: 8, recency: []) == n[5])
        // Same depth only: the top row (depth 1) pans to the bottom row, never into its leaves.
        #expect(Navigator.pan(view: .node(n[2]), edge: .bottom, tree: tree, homeResolution: wide, gap: 8, recency: []) == n[6])

        var harness = try await nested()
        try await harness.go(.node(try leaf(a, harness)))
        #expect(await harness.step(.pan(.right)) == .node(try column(harness)))
        #expect(await harness.step(.pan(.left)) == .node(try leaf(a, harness)))
    }

    @Test func panTiesGoToTheMostRecentlyViewed() throws {
        let (tree, even) = try rows(cut: 248)  // n5 and n7 each share 244 pt with n3
        #expect(Navigator.pan(view: .node(n[3]), edge: .bottom, tree: tree, homeResolution: even, gap: 8, recency: []) == n[5])
        #expect(Navigator.pan(view: .node(n[3]), edge: .bottom, tree: tree, homeResolution: even, gap: 8, recency: [n[7], n[5]]) == n[7])
    }

    @Test func panAtHomeIsRefused() async throws {
        var harness = try await nested()
        let expected: [Edge: String] = [
            .left: "No area to the left", .right: "No area to the right", .top: "No area above", .bottom: "No area below",
        ]
        for edge in Edge.allCases {
            expectRefused(await harness.camera(.pan(edge)), try #require(expected[edge]), command: "pan(")
        }
    }

    @Test func panWithNothingAcrossIsRefused() async throws {
        var harness = try await nested()
        try await harness.go(.node(try leaf(a, harness)))

        expectRefused(await harness.camera(.pan(.left)), "No area to the left", command: "pan(")
        expectRefused(await harness.camera(.pan(.top)), "No area above", command: "pan(")
    }

    @Test func frameWindowFramesTheFocusedLeafAndTogglesBack() async throws {
        var harness = try await nested()
        let leafB = try leaf(b, harness)
        #expect(!harness.arranger.isFramingFocused(displayUUID: "main", focused: b))

        #expect(await harness.step(.frameWindow, focused: b) == .node(leafB))
        #expect(harness.arranger.isFramingFocused(displayUUID: "main", focused: b))
        #expect(!harness.arranger.isFramingFocused(displayUUID: "main", focused: c))
        #expect(await harness.step(.frameWindow, focused: b) == .home)
        #expect(!harness.arranger.isFramingFocused(displayUUID: "main", focused: b))
        #expect(await harness.step(.frameWindow, focused: b) == .node(leafB))

        // From another view, the toggle goes Back to it.
        try await harness.go(.node(try column(harness)))
        #expect(await harness.step(.frameWindow, focused: c) == .node(try leaf(c, harness)))
        #expect(await harness.step(.frameWindow, focused: c) == .node(try column(harness)))
    }

    @Test func frameWindowDuringAPendingMoveComparesAgainstThePendingTarget() async throws {
        var harness = try await nested()
        let leafB = try leaf(b, harness)

        let first = try #require(moves(await harness.camera(.frameWindow, focused: b)).first)
        let second = try #require(moves(await harness.camera(.frameWindow, focused: b)).first)

        #expect(first.to == .node(leafB))
        #expect(second.from == .node(leafB) && second.to == .home)
        #expect(await harness.send(.cameraSettle(displayUUID: "main", moveID: first.id)).isEmpty)
        await harness.send(.cameraSettle(displayUUID: "main", moveID: second.id))
        #expect(harness.arranger.view(on: "main") == .home)
    }

    @Test func frameWindowRefusesFloatingExcludedOrNoFocus() async throws {
        var harness = try await nested()
        expectRefused(await harness.camera(.frameWindow), "No docked window to frame", command: "frameWindow")
        #expect(!harness.arranger.availability(.camera(.frameWindow), context: CommandContext(focused: nil, ready: true, displayUUID: "main")))
        #expect(harness.arranger.availability(.camera(.frameWindow), context: CommandContext(focused: b, ready: true, displayUUID: "main")))

        await harness.send(.command(.float, focused: c))
        #expect(harness.arranger.isFloating(c))
        expectRefused(await harness.camera(.frameWindow, focused: c), "No docked window to frame", command: "frameWindow")

        var excluded = try #require(harness.arranger.windows[b.identity])
        excluded.isExcluded = true
        await harness.send(.event(.windowChanged(excluded)))
        expectRefused(await harness.camera(.frameWindow, focused: b), "No docked window to frame", command: "frameWindow")
    }

    @Test func frameDesktopTogglesAndIsRefusedWhileHidden() async throws {
        var harness = try await nested()
        let main = CommandContext(focused: nil, ready: true, displayUUID: "main")
        #expect(harness.arranger.availability(.camera(.frameDesktop), context: main))

        #expect(await harness.step(.frameDesktop) == .node(.desktop))
        #expect(harness.arranger.isFramingDesktop(displayUUID: "main"))
        #expect(await harness.step(.frameDesktop) == .home)
        #expect(!harness.arranger.isFramingDesktop(displayUUID: "main"))

        await harness.send(.command(.toggleDesktop, focused: a))
        #expect(harness.arranger.world[key]?.tree.isDesktopHidden == true)
        expectRefused(await harness.camera(.frameDesktop), "The Desktop tile is hidden", command: "frameDesktop")
        #expect(!harness.arranger.availability(.camera(.frameDesktop), context: main))
    }

    /// IN-01: with nothing docked the Desktop tile is the root, so framing it is home, never `.node(root)`.
    @Test func frameDesktopOnAnEmptyDeskStaysHome() async throws {
        var harness = try await nested()
        for id: UInt32 in [1, 2, 3] { await harness.fake.close(id) }
        await harness.refresh()
        #expect(harness.arranger.world[key]?.tree.root == .desktop)
        #expect(harness.arranger.view(on: "main") == .home)

        let effects = await harness.camera(.frameDesktop)
        await harness.settle(effects)

        #expect(moves(effects).allSatisfy { $0.to == .home })
        #expect(harness.arranger.view(on: "main") == .home)
    }
}

private func entry(_ raw: UInt64) -> ViewEntry {
    ViewEntry(desk: key, target: .node(NodeID(raw: raw)), path: [NodeID(raw: raw)])
}

/// ZOOM-04, D-D: one history per display, pushed only at settle, dead entries skipped.
@Suite struct CameraHistoryTests {
    @Test func aSettlePushesThePreviousViewAndBackThenForwardReturnToIt() async throws {
        var harness = try await nested()
        let main = CommandContext(focused: nil, ready: true, displayUUID: "main")
        #expect(!harness.arranger.availability(.camera(.back), context: main))
        try await harness.go(.node(try leaf(a, harness)))
        try await harness.go(.node(try column(harness)))
        #expect(harness.arranger.availability(.camera(.back), context: main))
        #expect(!harness.arranger.availability(.camera(.forward), context: main))

        #expect(await harness.step(.back) == .node(try leaf(a, harness)))
        #expect(await harness.step(.back) == .home)
        #expect(harness.arranger.availability(.camera(.forward), context: main))
        #expect(await harness.step(.forward) == .node(try leaf(a, harness)))
        #expect(await harness.step(.forward) == .node(try column(harness)))
        expectRefused(await harness.camera(.forward), "No later view", command: "forward")
    }

    @Test func aDoubleBackGoesBackTwoAndForwardRetracesThem() async throws {
        var harness = try await nested()
        try await harness.go(.node(try leaf(a, harness)))
        try await harness.go(.node(try column(harness)))

        let first = await harness.camera(.back)
        let second = await harness.camera(.back)
        #expect(moves(second).first?.to == .home)
        await harness.settle(first + second)
        #expect(harness.arranger.view(on: "main") == .home)

        #expect(await harness.step(.forward) == .node(try leaf(a, harness)))
        #expect(await harness.step(.forward) == .node(try column(harness)))
    }

    @Test func historyIsPerDisplay() async throws {
        var harness = try await nested()
        let side = DisplayInfo(
            uuid: "side", frame: Rect(x: 1440, y: 0, width: 1920, height: 1080), visibleFrame: Rect(x: 1440, y: 0, width: 1920, height: 1080),
            currentSpaceID: nil)
        await harness.fake.setDisplays([try #require(harness.arranger.displays.first), side])
        await harness.fake.open(.standard(id: 4, pid: pid, frame: Rect(x: 1600, y: 100, width: 300, height: 200)))
        await harness.refresh()
        await harness.fake.advance(by: .milliseconds(300))
        await harness.refresh()
        await harness.send(.inventory(await harness.fake.inventory()))
        await harness.send(.command(.dock, focused: d))
        let sideLeaf = try #require(harness.arranger.world[DeskKey(displayUUID: "side", spaceID: nil)]?.tree.leaf(containing: d))

        try await harness.go(.node(try leaf(a, harness)))
        expectRefused(await harness.camera(.back, on: "side"), "No earlier view", command: "back")
        try await harness.go(.node(sideLeaf), on: "side")

        #expect(await harness.step(.back) == .home)
        #expect(harness.arranger.view(on: "side") == .node(sideLeaf))
        #expect(await harness.step(.back, on: "side") == .home)
    }

    @Test func the51stPushDropsTheOldest() {
        var history = CameraHistory()
        for raw in 1...51 { history.push(entry(UInt64(raw))) }

        #expect(CameraHistory.limit == 50)
        #expect(history.back.count == 50)
        #expect(history.back.first == entry(2) && history.back.last == entry(51))
    }

    @Test func aPushClearsForward() {
        var history = CameraHistory()
        history.push(entry(1))
        history.forward = [entry(2)]

        history.push(entry(3))

        #expect(history.back == [entry(1), entry(3)] && history.forward.isEmpty)
    }

    @Test func aRetargetPushesOnce() async throws {
        var harness = try await nested()

        let first = await harness.send(.zoomTo(.node(try leaf(a, harness)), displayUUID: "main"))
        let second = await harness.send(.zoomTo(.node(try column(harness)), displayUUID: "main"))
        await harness.settle(first + second)
        #expect(harness.arranger.view(on: "main") == .node(try column(harness)))

        #expect(await harness.step(.back) == .home)
        expectRefused(await harness.camera(.back), "No earlier view", command: "back")
    }

    @Test func backSkipsAnEntryWhoseNodeWasRemoved() async throws {
        var harness = try await nested()
        try await harness.go(.node(try leaf(c, harness)))
        try await harness.go(.node(try leaf(a, harness)))
        await harness.fake.close(3)
        await harness.refresh()
        #expect(harness.arranger.world[key]?.tree.windows == [a, b])

        #expect(await harness.step(.back) == .home)
    }

    @Test func backSkipsAnEntryWhoseDeskIsNotShown() async throws {
        var harness = await Harness.onSpaceOne()
        await harness.send(.zoomEnabled(true))
        let space1 = DeskKey(displayUUID: "D", spaceID: 1)
        let leafA = try #require(harness.arranger.world[space1]?.tree.leaf(containing: a))
        try await harness.go(.node(leafA), on: "D")
        _ = await harness.switchTo(2)
        await harness.openNew(3, frame: Rect(x: 730, y: 400, width: 150, height: 120), space: 2)
        await harness.send(.command(.dock, focused: c))
        let leafC = try #require(harness.arranger.world[DeskKey(displayUUID: "D", spaceID: 2)]?.tree.leaf(containing: c))
        try await harness.go(.node(leafC), on: "D")

        #expect(await harness.step(.back, on: "D") == .home)
        expectRefused(await harness.camera(.back, on: "D"), "No earlier view", command: "back")
    }

    @Test func emptyHistoryRefusesBothWays() async throws {
        var harness = try await nested()

        expectRefused(await harness.camera(.back), "No earlier view", command: "back")
        expectRefused(await harness.camera(.forward), "No later view", command: "forward")
    }
}

/// H[n1 = a, n2 = V[n3 = b, n4 = c], Desktop] under root n5, with on-screen tiles side by side.
private func band() throws -> (LayoutTree, [NodeID: Rect]) {
    let tree = try LayoutTree(
        root: n[5],
        nodes: [
            n[5]: .split(axis: .horizontal, children: [n[1], n[2], .desktop], weights: [0.4, 0.4, 0.2]),
            n[2]: .split(axis: .vertical, children: [n[3], n[4]], weights: [0.5, 0.5]),
            n[1]: .panel(a), n[3]: .panel(b), n[4]: .panel(c), .desktop: .desktop(hidden: false),
        ],
        states: [a.identity: .present, b.identity: .present, c.identity: .present])
    let tiles: [NodeID: Rect] = [
        n[1]: Rect(x: 0, y: 0, width: 400, height: 1000), n[3]: Rect(x: 400, y: 0, width: 400, height: 500),
        n[4]: Rect(x: 400, y: 500, width: 400, height: 500), .desktop: Rect(x: 800, y: 0, width: 200, height: 1000),
    ]
    return (tree, tiles)
}

/// ZOOM-03 (engine): the rubber band's target is the lowest common ancestor of the tiles whose centres it holds.
@Suite struct RectTargetNavigatorTests {
    @Test func rectTargetIsTheLowestCommonAncestorOfCentresInside() throws {
        let (tree, tiles) = try band()
        // b's centre (600, 250) and c's (600, 750).
        #expect(Navigator.rectTarget(band: Rect(x: 550, y: 200, width: 100, height: 600), tiles: tiles, tree: tree) == n[2])
        #expect(Navigator.rectTarget(band: Rect(x: 550, y: 200, width: 100, height: 100), tiles: tiles, tree: tree) == n[3])
        #expect(Navigator.rectTarget(band: Rect(x: 150, y: 200, width: 500, height: 350), tiles: tiles, tree: tree) == n[5])
        #expect(Navigator.lowestCommonAncestor([n[3], n[4]], in: tree) == n[2])
        #expect(Navigator.lowestCommonAncestor([n[3], NodeID(raw: 99)], in: tree) == nil)
        #expect(Navigator.ancestors(of: n[4], in: tree) == [n[5], n[2], n[4]])
    }

    @Test func aCentreOnTheBandEdgeCounts() throws {
        let (tree, tiles) = try band()
        // The band's right and bottom edges pass exactly through b's centre.
        #expect(Navigator.rectTarget(band: Rect(x: 500, y: 150, width: 100, height: 100), tiles: tiles, tree: tree) == n[3])
        #expect(Navigator.rectTarget(band: Rect(x: 600, y: 250, width: 10, height: 10), tiles: tiles, tree: tree) == n[3])
    }

    @Test func noCentreInsideGivesNoTarget() throws {
        let (tree, tiles) = try band()
        #expect(Navigator.rectTarget(band: Rect(x: 410, y: 10, width: 100, height: 100), tiles: tiles, tree: tree) == nil)
        #expect(Navigator.rectTarget(band: Rect(x: 0, y: 0, width: 0, height: 0), tiles: tiles, tree: tree) == nil)
    }

    @Test func collapsedAndDesktopTilesCount() async throws {
        let (tree, tiles) = try band()
        #expect(Navigator.rectTarget(band: Rect(x: 850, y: 450, width: 100, height: 100), tiles: tiles, tree: tree) == .desktop)
        #expect(Navigator.rectTarget(band: Rect(x: 550, y: 450, width: 400, height: 350), tiles: tiles, tree: tree) == n[5])

        // The engine's tiles: every leaf of the committed view on screen, the Desktop tile included, splits never.
        var harness = try await nested()
        let shown = try harness.arranger.shownLeafRects(displayUUID: "main")
        #expect(Set(shown.keys) == [try leaf(a, harness), try leaf(b, harness), try leaf(c, harness), .desktop])
        try await harness.go(.node(try column(harness)))
        #expect(Set(try harness.arranger.shownLeafRects(displayUUID: "main").keys) == [try leaf(b, harness), try leaf(c, harness)])
    }
}

private let e = ref(5)

/// CONTEXT E: focus or a new window outside the view widens the camera to the smallest view holding both; a vanished view
/// node falls back to its deepest surviving ancestor.
@Suite struct WideningNavigatorTests {
    @Test func focusingAWindowOutsideTheViewWidensTheCamera() async throws {
        var harness = try await nested()
        try await harness.go(.node(try leaf(b, harness)))

        let effects = await harness.send(.event(.windowFocused(c)))
        #expect(moves(effects).count == 1)
        #expect(moves(effects).first?.to == .node(try column(harness)))
        await harness.settle(effects)

        #expect(moves(await harness.send(.event(.windowFocused(a)))).first?.to == .home)
    }

    @Test func focusInsideTheViewDoesNotMoveTheCamera() async throws {
        var harness = try await nested()
        try await harness.go(.node(try column(harness)))

        #expect(moves(await harness.send(.event(.windowFocused(b)))).isEmpty)
        #expect(moves(await harness.send(.event(.windowFocused(c)))).isEmpty)
    }

    @Test func aNewWindowOutsideTheViewWidensAndIsNotParkedFirst() async throws {
        var harness = try await nested()
        try await harness.go(.node(try column(harness)))
        #expect(await harness.fake.parked.contains(a.identity))

        await harness.fake.open(.standard(id: 5, pid: pid, frame: Rect(x: 600, y: 300, width: 300, height: 200)))
        var effects = await harness.refresh()
        await harness.fake.advance(by: .milliseconds(300))
        effects += await harness.refresh()

        #expect(harness.arranger.world[key]?.desktop.contains(e) == true)
        let move = try #require(moves(effects).first)
        #expect(moves(effects).count == 1)
        #expect(move.to == .home)
        #expect(!effects.contains { if case .perform(let commands) = $0 { commands.contains(.park(e, displayUUID: "main")) } else { false } })
        #expect(!(await harness.fake.parked.contains(e.identity)), "the new window was parked before the camera showed it")

        await harness.settle(effects)
        #expect(harness.arranger.view(on: "main") == .home)
        #expect(!(await harness.fake.parked.contains(e.identity)))
        #expect(!(await harness.fake.parked.contains(a.identity)))
    }

    @Test func aViewWhoseNodeDisappearedFallsBackToTheDeepestLiveAncestor() async throws {
        var harness = try await nested(four: true)
        let column = try column(harness)
        #expect(harness.arranger.world[key]?.tree.parent(of: try leaf(ref(4), harness)) == column)
        try await harness.go(.node(try leaf(c, harness)))

        await harness.fake.close(3)
        await harness.refresh()

        #expect(harness.arranger.world[key]?.tree.node(column) != nil)
        #expect(harness.arranger.view(on: "main") == .node(column))

        // With nothing of the path left but the root, it is home.
        var three = try await nested()
        try await three.go(.node(try leaf(c, three)))
        await three.fake.close(3)
        await three.refresh()
        #expect(three.arranger.view(on: "main") == .home)
    }
}

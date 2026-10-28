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

/// [a | V[b, c] | Desktop] re-attached from a saved World (as ArrangerFocusTests), zoom on.
private func nested() async throws -> Harness {
    var harness = await Harness.started(frames: [
        1: Rect(x: 40, y: 80, width: 320, height: 232), 2: Rect(x: 1000, y: 100, width: 300, height: 200),
        3: Rect(x: 1000, y: 600, width: 300, height: 200),
    ])
    var world = World()
    var history = UndoHistory()
    try world.addDesk(key)
    try world.edit(key, history: &history) { desk, ids throws(LayoutError) in
        try desk.tree.insert(a, at: .left, of: .desktop, ids: &ids)
        guard let left = desk.tree.leaf(containing: a) else { throw .windowNotFound(a) }
        try desk.tree.insert(b, at: .right, of: left, ids: &ids)
        guard let middle = desk.tree.leaf(containing: b) else { throw .windowNotFound(b) }
        try desk.tree.insert(c, at: .bottom, of: middle, ids: &ids)
    }
    harness.arranger = Arranger()
    await harness.send(.restore(world, homeFrames: [:]))
    await harness.send(.inventory(await harness.fake.inventory()))
    await harness.send(.zoomEnabled(true))
    #expect(harness.arranger.world[key]?.tree.windows == [a, b, c])
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
    fileprivate mutating func camera(_ command: CameraCommand, focused: WindowRef? = nil, pointer: Point? = nil) async -> [ArrangerEffect] {
        await send(.camera(command, displayUUID: "main", focused: focused, pointer: pointer))
    }

    /// Settles every camera move in `effects`, oldest first; returns the last settle's effects.
    @discardableResult
    fileprivate mutating func settle(_ effects: [ArrangerEffect]) async -> [ArrangerEffect] {
        var last: [ArrangerEffect] = []
        for move in moves(effects) { last = await send(.cameraSettle(displayUUID: move.displayUUID, moveID: move.id)) }
        return last
    }

    /// Moves the main display's camera to `target` and settles.
    fileprivate mutating func go(_ target: ViewTarget) async throws {
        let effects = await send(.zoomTo(target, displayUUID: "main"))
        #expect(moves(effects).count == 1)
        await settle(effects)
        #expect(arranger.view(on: "main") == target)
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

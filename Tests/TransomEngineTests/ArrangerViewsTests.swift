@testable import TransomEngine
import TransomModel
import TransomTestSupport
import Testing

private let pid: Int32 = 900
private let bundleID = "com.example.arranger"
private let key = DeskKey(displayUUID: "main", spaceID: nil)

private func ref(_ id: UInt32) -> WindowRef {
    WindowRef(identity: WindowIdentity(windowID: id, pid: pid, bundleID: bundleID))
}

private let a = ref(1), b = ref(2), c = ref(3), d = ref(4)
private let three = ViewSlot(3)!

/// a, b and c docked one after another (Phase 3 tiles: a | b | (Desktop tile / c)), d floating on the Desktop unless
/// `floater` is false, zoom on.
private func threeDocked(floater: Bool = true) async throws -> Harness {
    var frames: [UInt32: Rect] = [
        1: Rect(x: 40, y: 80, width: 320, height: 232), 2: Rect(x: 730, y: 400, width: 150, height: 120),
        3: Rect(x: 1100, y: 600, width: 150, height: 120),
    ]
    if floater { frames[4] = Rect(x: 1000, y: 100, width: 200, height: 150) }
    var harness = await Harness.started(frames: frames)
    for window in [a, b, c] { await harness.send(.command(.dock, focused: window)) }
    try #require(harness.arranger.world[key].map { Set($0.tree.windows) } == [a, b, c])
    await harness.send(.zoomEnabled(true))
    return harness
}

private func tree(_ harness: Harness) throws -> LayoutTree {
    try #require(harness.arranger.world[key]?.tree)
}

/// The smallest node holding `windows`' leaves (a floater's is the Desktop tile).
private func lca(_ windows: [WindowRef], _ harness: Harness) throws -> NodeID {
    try #require(Navigator.lowestCommonAncestor(windows.compactMap { harness.arranger.leafNode(of: $0) }, in: tree(harness)))
}

private func moves(_ effects: [ArrangerEffect]) -> [CameraMove] {
    effects.compactMap { if case .cameraMove(let move) = $0 { move } else { nil } }
}

private func notices(_ effects: [ArrangerEffect]) -> [Notice] {
    effects.compactMap { if case .notice(let notice) = $0 { notice } else { nil } }
}

@discardableResult
private func camera(_ command: CameraCommand, _ harness: inout Harness, focused: WindowRef? = nil) async -> [ArrangerEffect] {
    await harness.send(.camera(command, displayUUID: "main", focused: focused, pointer: nil))
}

private func has(_ effect: ArrangerEffect, _ effects: [ArrangerEffect]) -> Bool { effects.contains(effect) }

private func announcements(_ effects: [ArrangerEffect]) -> [String] {
    effects.compactMap { if case .announce(let text) = $0 { text } else { nil } }
}

/// Saves the (Desktop tile / c) view into slot 3 and goes home: the view holds c and d.
private func savedCAndD(_ harness: inout Harness) async throws -> NodeID {
    let node = try lca([c, d], harness)
    try await zoom(&harness, to: .node(node))
    await camera(.saveView(three), &harness)
    try await zoom(&harness, to: .home)
    return node
}

/// Moves the camera to `target` and settles.
private func zoom(_ harness: inout Harness, to target: ViewTarget) async throws {
    let move = try #require(moves(await harness.send(.zoomTo(target, displayUUID: "main"))).first)
    await harness.send(.cameraSettle(displayUUID: "main", moveID: move.id))
}

/// VIEW-01, 08 UI-SPEC Surface 1: ⇧⌥{n} stores the view's desk and window identities, ⌥{n} zooms back to the smallest
/// node holding the windows still there.
@Suite struct ArrangerViewsTests {
    @Test func savingThenGoingBackZoomsToTheSavedWindows() async throws {
        var harness = try await threeDocked()
        let node = try lca([c, d], harness)
        let root = try tree(harness).root
        try #require(node != root, "c and the Desktop tile share a split without a and b")
        try await zoom(&harness, to: .node(node))

        let saved = await camera(.saveView(three), &harness)

        #expect(notices(saved) == [.viewSaved(three, replaced: false, displayUUID: "main")])
        #expect(moves(saved).isEmpty)
        #expect(harness.arranger.camera.savedViews[three] == SavedView(slot: three, desk: key, home: false, windows: [c.identity, d.identity]))
        try await zoom(&harness, to: .home)

        let shown = await camera(.view(three), &harness)

        #expect(moves(shown).map(\.to) == [.node(node)])
        #expect(notices(shown) == [.viewShown(three, displayUUID: "main")])
    }

    @Test func aLaterLayoutChangeStillTargetsTheSmallestNodeHoldingTheSavedWindows() async throws {
        var harness = try await threeDocked()
        let saved = try #require(harness.arranger.leafNode(of: c))
        try await zoom(&harness, to: .node(saved))
        await camera(.saveView(three), &harness)
        try await zoom(&harness, to: .home)
        await harness.send(.event(.windowFocused(a)))
        await harness.send(.command(.swapPrevious, focused: c))  // c now sits in a's old tile
        let moved = try #require(harness.arranger.leafNode(of: c))
        try #require(moved != saved)

        let shown = await camera(.view(three), &harness)

        #expect(moves(shown).map(\.to) == [.node(moved)])
        #expect(notices(shown) == [.viewShown(three, displayUUID: "main")])
    }

    @Test func theDeskHoldingMostSavedWindowsIsTheTargetAndATieGoesToTheSavedDesk() async throws {
        var harness = try await threeDocked()
        let other = DeskKey(displayUUID: "main", spaceID: 7)  // another Space's desk, holding window 5
        try harness.arranger.world.addDesk(other)
        try harness.arranger.world.reflow(other) { desk, _ throws(LayoutError) in try desk.desktop.add(ref(5), frame: Rect(x: 100, y: 100, width: 200, height: 150)) }
        try #require(harness.arranger.deskKey(of: ref(5)) == other)
        let windows = [c.identity, ref(5).identity]

        #expect(harness.arranger.viewDestination(SavedView(slot: three, desk: key, home: false, windows: windows)).key == key)
        #expect(harness.arranger.viewDestination(SavedView(slot: three, desk: other, home: false, windows: windows)).key == other)
        let most = SavedView(slot: three, desk: other, home: false, windows: [a.identity, c.identity, ref(5).identity])
        let destination = harness.arranger.viewDestination(most)
        #expect(destination.key == key, "two of three are on the main desk")
        #expect(destination.target == .home && destination.allGone == false, "a and c share only the root")
    }

    @Test func oneSavedWindowClosedGoesToTheSurvivorsLeafWithNoOtherNotice() async throws {
        var harness = try await threeDocked()
        _ = try await savedCAndD(&harness)
        await harness.fake.close(4)
        await harness.refresh()
        try #require(harness.arranger.deskKey(of: d) == nil)

        let shown = await camera(.view(three), &harness)

        #expect(moves(shown).map(\.to) == [.node(try #require(harness.arranger.leafNode(of: c)))])
        #expect(notices(shown) == [.viewShown(three, displayUUID: "main")])
        #expect(!has(.beep, shown))
    }

    @Test func everySavedWindowClosedGoesHomeWithN17AndKeepsTheSlot() async throws {
        var harness = try await threeDocked()
        let node = try await savedCAndD(&harness)
        try await zoom(&harness, to: .node(try #require(harness.arranger.leafNode(of: a))))
        for id: UInt32 in [3, 4] { await harness.fake.close(id) }
        await harness.refresh()
        try #require(harness.arranger.world[key]?.tree.node(node) == nil || harness.arranger.deskKey(of: c) == nil)

        let shown = await camera(.view(three), &harness)

        #expect(moves(shown).map(\.to) == [.home])
        #expect(notices(shown) == [.viewWindowsClosed(three, displayUUID: "main")])
        #expect(!has(.beep, shown))
        #expect(harness.arranger.camera.savedViews[three] != nil, "the slot stays saved (D-05)")

        let move = try #require(moves(shown).first)
        await harness.send(.cameraSettle(displayUUID: "main", moveID: move.id))
        let again = await camera(.view(three), &harness)
        #expect(moves(again).isEmpty, "already home: nothing moves")
        #expect(notices(again) == [.viewWindowsClosed(three, displayUUID: "main")])
    }

    @Test func everySavedWindowGoneOnADisconnectedDisplayMovesNothing() async throws {
        var harness = try await threeDocked()
        let saved = SavedView(slot: three, desk: DeskKey(displayUUID: "unplugged", spaceID: nil), home: false, windows: [ref(99).identity])
        harness.arranger.camera.savedViews.save(saved)

        let shown = await camera(.view(three), &harness)

        #expect(moves(shown).isEmpty)
        #expect(has(.beep, shown))
        #expect(notices(shown) == [.viewDisplayGone(three, displayUUID: "main")])
        #expect(harness.arranger.camera.savedViews[three] == saved)
    }

    @Test func aHomeViewGoesBackHome() async throws {
        var harness = try await threeDocked()
        let saved = await camera(.saveView(three), &harness)
        #expect(harness.arranger.camera.savedViews[three] == SavedView(slot: three, desk: key, home: true, windows: []))
        #expect(notices(saved) == [.viewSaved(three, replaced: false, displayUUID: "main")])
        try await zoom(&harness, to: .node(try #require(harness.arranger.leafNode(of: a))))

        let shown = await camera(.view(three), &harness)

        #expect(moves(shown).map(\.to) == [.home])
        #expect(notices(shown) == [.viewShown(three, displayUUID: "main")])
    }

    @Test func savingDuringAMoveSavesItsTarget() async throws {
        var harness = try await threeDocked()
        let leaf = try #require(harness.arranger.leafNode(of: a))
        try #require(moves(await harness.send(.zoomTo(.node(leaf), displayUUID: "main"))).count == 1)  // not settled

        await camera(.saveView(three), &harness)

        #expect(harness.arranger.camera.savedViews[three] == SavedView(slot: three, desk: key, home: false, windows: [a.identity]))
    }

    @Test func savingAViewWithNoWindowsIsRefusedAndKeepsTheSlot() async throws {
        var harness = try await threeDocked(floater: false)
        await camera(.saveView(three), &harness)  // home
        try await zoom(&harness, to: .node(.desktop))

        let refused = await camera(.saveView(three), &harness)

        #expect(has(.beep, refused))
        #expect(notices(refused) == [.viewNothingToSave(displayUUID: "main")])
        #expect(harness.arranger.camera.savedViews[three] == SavedView(slot: three, desk: key, home: true, windows: []))
    }

    @Test func savingOverAUsedSlotReplacesItWithoutConfirmation() async throws {
        var harness = try await threeDocked()
        await camera(.saveView(three), &harness)
        try await zoom(&harness, to: .node(try #require(harness.arranger.leafNode(of: a))))

        let replaced = await camera(.saveView(three), &harness)

        #expect(notices(replaced) == [.viewSaved(three, replaced: true, displayUUID: "main")])
        #expect(harness.arranger.camera.savedViews[three]?.windows == [a.identity])
    }

    @Test func goingToAnEmptySlotBeepsWithN16() async throws {
        var harness = try await threeDocked()

        let refused = await camera(.view(three), &harness)

        #expect(moves(refused).isEmpty)
        #expect(has(.beep, refused))
        #expect(notices(refused) == [.viewEmpty(three, displayUUID: "main")])
    }

    @Test func goingToTheViewAlreadyShownMovesNothingAndIsNoRefusal() async throws {
        var harness = try await threeDocked()
        let node = try await savedCAndD(&harness)
        try await zoom(&harness, to: .node(node))

        let shown = await camera(.view(three), &harness)

        #expect(moves(shown).isEmpty)
        #expect(!has(.beep, shown) && announcements(shown).isEmpty)
        #expect(notices(shown) == [.viewShown(three, displayUUID: "main")])
    }

    @Test func pausedOrFullScreenRefusesLikeEveryCameraCommand() async throws {
        var harness = try await threeDocked()
        await camera(.saveView(three), &harness)
        // A display with no desk (a full-screen Space) refuses like Zoom Out to All Windows.
        for command in [CameraCommand.view(three), .saveView(three)] {
            let refused = await harness.send(.camera(command, displayUUID: "full-screen", focused: nil, pointer: nil))
            #expect(has(.beep, refused) && announcements(refused) == [Navigator.Refusal.fullScreen.announcement])
        }
        await harness.send(.command(.togglePause, focused: nil))
        let zoomOut = await camera(.zoomOutAll, &harness)
        for command in [CameraCommand.view(three), .saveView(three)] {
            let refused = await camera(command, &harness)
            #expect(has(.beep, refused) && announcements(refused) == announcements(zoomOut))
            #expect(announcements(refused) == [Navigator.Refusal.paused.announcement])
            #expect(notices(refused).isEmpty && moves(refused).isEmpty)
        }
    }

    @Test func savingTouchesNoWindowOrUndoHistoryAndGoingPushesBackHistory() async throws {
        var harness = try await threeDocked()
        let node = try lca([c, d], harness)
        try await zoom(&harness, to: .node(node))
        let world = harness.arranger.world, history = harness.arranger.history, back = harness.arranger.camera.histories["main"]

        let saved = await camera(.saveView(three), &harness)

        #expect(harness.arranger.world == world && harness.arranger.history == history)
        #expect(harness.arranger.camera.histories["main"] == back)
        #expect(!saved.contains { if case .perform = $0 { true } else if case .save = $0 { true } else { false } })
        try await zoom(&harness, to: .home)
        let move = try #require(moves(await camera(.view(three), &harness)).first)
        await harness.send(.cameraSettle(displayUUID: "main", moveID: move.id))
        let entry = try #require(harness.arranger.camera.histories["main"]?.back.last)
        #expect(entry.desk == key && entry.target == .home)
        #expect(harness.arranger.history == history, "going to a view is never an undo step")
    }

    @Test func goingFocusesTheMostRecentWindowInsideTheViewWhenFocusIsOutside() async throws {
        var harness = try await threeDocked()
        _ = try await savedCAndD(&harness)
        await harness.send(.event(.windowFocused(c)))
        await harness.send(.event(.windowFocused(a)))

        try #require(moves(await camera(.view(three), &harness, focused: a)).count == 1)
        #expect(harness.arranger.camera.pending["main"]?.focus == c)

        try await zoom(&harness, to: .home)
        try #require(moves(await camera(.view(three), &harness, focused: c)).count == 1)
        #expect(harness.arranger.camera.pending["main"]?.focus == nil, "focus inside the view stays")
    }
}

import Foundation
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

/// a, b, c and d docked one after another, each by its centre (tiles: a | b | (d / c)), zoom on.
private func fourDocked() async throws -> Harness {
    let frames: [UInt32: Rect] = [
        1: Rect(x: 40, y: 80, width: 320, height: 232), 2: Rect(x: 730, y: 400, width: 150, height: 120),
        3: Rect(x: 1300, y: 400, width: 100, height: 120), 4: Rect(x: 1000, y: 100, width: 200, height: 150),
    ]
    var harness = await Harness.started(frames: frames)
    for window in [a, b, c, d] { await harness.send(.command(.dock, focused: window)) }
    try #require(harness.arranger.world[key].map { Set($0.tree.windows) } == [a, b, c, d])
    await harness.send(.zoomEnabled(true))
    return harness
}

private func tree(_ harness: Harness) throws -> LayoutTree {
    try #require(harness.arranger.world[key]?.tree)
}

/// The smallest node holding `windows`' leaves.
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

/// Saves the (d / c) view into slot 3 and goes home: the view holds c and d.
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
        var harness = try await fourDocked()
        let node = try lca([c, d], harness)
        let root = try tree(harness).root
        try #require(node != root, "c and d share a split without a and b")
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
        var harness = try await fourDocked()
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
        var harness = try await fourDocked()
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

    /// D-14, 09 UI-SPEC Surface 4: the menu bar fills the badge of the saved view the display's camera shows.
    @Test func theCurrentSlotIsTheSavedViewOnScreen() async throws {
        var harness = try await fourDocked()
        let node = try await savedCAndD(&harness)
        harness.arranger.camera.savedViews.save(SavedView(slot: ViewSlot(1)!, desk: key, home: true, windows: []))
        try await zoom(&harness, to: .node(node))

        #expect(harness.arranger.savedViewSlots == [1, 3])
        #expect(harness.arranger.currentViewSlot(displayUUID: "main") == three)
        #expect(harness.arranger.currentViewSlot(displayUUID: "unplugged") == nil)
    }

    @Test func noSlotIsCurrentAtHomeOrAtAnUnsavedView() async throws {
        var harness = try await fourDocked()
        let node = try await savedCAndD(&harness)
        harness.arranger.camera.savedViews.save(SavedView(slot: ViewSlot(1)!, desk: key, home: true, windows: []))

        #expect(harness.arranger.currentViewSlot(displayUUID: "main") == nil, "a saved home view is never filled")
        try await zoom(&harness, to: .node(try #require(harness.arranger.leafNode(of: a))))
        #expect(harness.arranger.currentViewSlot(displayUUID: "main") == nil)
        // The same node shown on another Space's desk is not slot 3's view.
        let other = DeskKey(displayUUID: "main", spaceID: 7)
        await harness.send(.event(.spaceChanged(displayUUID: "main", spaceID: 7)))
        harness.arranger.camera.views[other] = .node(node)
        try #require(harness.arranger.view(on: "main") == .node(node))
        #expect(harness.arranger.currentViewSlot(displayUUID: "main") == nil)
    }

    @Test func oneSavedWindowClosedGoesToTheSurvivorsLeafWithNoOtherNotice() async throws {
        var harness = try await fourDocked()
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
        var harness = try await fourDocked()
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
        var harness = try await fourDocked()
        let saved = SavedView(slot: three, desk: DeskKey(displayUUID: "unplugged", spaceID: nil), home: false, windows: [ref(99).identity])
        harness.arranger.camera.savedViews.save(saved)

        let shown = await camera(.view(three), &harness)

        #expect(moves(shown).isEmpty)
        #expect(has(.beep, shown))
        #expect(notices(shown) == [.viewDisplayGone(three, displayUUID: "main")])
        #expect(harness.arranger.camera.savedViews[three] == saved)
    }

    /// 8.1.1 D-14: floating windows are not part of a view, so a node view saves only its docked windows.
    @Test func savingANodeViewSavesOnlyItsDockedWindows() async throws {
        var harness = try await fourDocked()
        await harness.send(.command(.float, focused: d))
        try #require(harness.arranger.isFloating(d))
        try await zoom(&harness, to: .node(try #require(harness.arranger.leafNode(of: c))))

        await camera(.saveView(three), &harness)

        #expect(harness.arranger.camera.savedViews[three]?.windows == [c.identity])
    }

    /// RESEARCH Open Question 3: a view saved before 8.1.1 that names only floating windows goes home at runtime, with
    /// no file rewrite, and its notice is N15, not the "all gone" N17: the windows are still there.
    @Test func aViewOfOnlyFloatingWindowsGoesHome() async throws {
        var harness = try await fourDocked()
        for window in [c, d] { await harness.send(.command(.float, focused: window)) }
        try #require(harness.arranger.isFloating(c) && harness.arranger.isFloating(d))
        try await zoom(&harness, to: .node(try #require(harness.arranger.leafNode(of: a))))
        harness.arranger.camera.savedViews.save(SavedView(slot: three, desk: key, home: false, windows: [c.identity, d.identity]))

        let shown = await camera(.view(three), &harness)

        #expect(moves(shown).map(\.to) == [.home])
        #expect(notices(shown) == [.viewShown(three, displayUUID: "main")])
        #expect(!has(.beep, shown))
    }

    @Test func aHomeViewGoesBackHome() async throws {
        var harness = try await fourDocked()
        let saved = await camera(.saveView(three), &harness)
        #expect(harness.arranger.camera.savedViews[three] == SavedView(slot: three, desk: key, home: true, windows: []))
        #expect(notices(saved) == [.viewSaved(three, replaced: false, displayUUID: "main")])
        try await zoom(&harness, to: .node(try #require(harness.arranger.leafNode(of: a))))

        let shown = await camera(.view(three), &harness)

        #expect(moves(shown).map(\.to) == [.home])
        #expect(notices(shown) == [.viewShown(three, displayUUID: "main")])
    }

    @Test func savingDuringAMoveSavesItsTarget() async throws {
        var harness = try await fourDocked()
        let leaf = try #require(harness.arranger.leafNode(of: a))
        try #require(moves(await harness.send(.zoomTo(.node(leaf), displayUUID: "main"))).count == 1)  // not settled

        await camera(.saveView(three), &harness)

        #expect(harness.arranger.camera.savedViews[three] == SavedView(slot: three, desk: key, home: false, windows: [a.identity]))
    }

    @Test func savingOverAUsedSlotReplacesItWithoutConfirmation() async throws {
        var harness = try await fourDocked()
        await camera(.saveView(three), &harness)
        try await zoom(&harness, to: .node(try #require(harness.arranger.leafNode(of: a))))

        let replaced = await camera(.saveView(three), &harness)

        #expect(notices(replaced) == [.viewSaved(three, replaced: true, displayUUID: "main")])
        #expect(harness.arranger.camera.savedViews[three]?.windows == [a.identity])
    }

    @Test func goingToAnEmptySlotBeepsWithN16() async throws {
        var harness = try await fourDocked()

        let refused = await camera(.view(three), &harness)

        #expect(moves(refused).isEmpty)
        #expect(has(.beep, refused))
        #expect(notices(refused) == [.viewEmpty(three, displayUUID: "main")])
    }

    @Test func goingToTheViewAlreadyShownMovesNothingAndIsNoRefusal() async throws {
        var harness = try await fourDocked()
        let node = try await savedCAndD(&harness)
        try await zoom(&harness, to: .node(node))

        let shown = await camera(.view(three), &harness)

        #expect(moves(shown).isEmpty)
        #expect(!has(.beep, shown) && announcements(shown).isEmpty)
        #expect(notices(shown) == [.viewShown(three, displayUUID: "main")])
    }

    @Test func pausedOrFullScreenRefusesLikeEveryCameraCommand() async throws {
        var harness = try await fourDocked()
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
        var harness = try await fourDocked()
        let node = try lca([c, d], harness)
        try await zoom(&harness, to: .node(node))
        let world = harness.arranger.world, history = harness.arranger.history, back = harness.arranger.camera.histories["main"]

        let saved = await camera(.saveView(three), &harness)

        #expect(harness.arranger.world == world && harness.arranger.history == history)
        #expect(harness.arranger.camera.histories["main"] == back)
        #expect(!saved.contains { if case .perform = $0 { true } else { false } })
        try await zoom(&harness, to: .home)
        let move = try #require(moves(await camera(.view(three), &harness)).first)
        await harness.send(.cameraSettle(displayUUID: "main", moveID: move.id))
        let entry = try #require(harness.arranger.camera.histories["main"]?.back.last)
        #expect(entry.desk == key && entry.target == .home)
        #expect(harness.arranger.history == history, "going to a view is never an undo step")
    }

    @Test func goingFocusesTheMostRecentWindowInsideTheViewWhenFocusIsOutside() async throws {
        var harness = try await fourDocked()
        _ = try await savedCAndD(&harness)
        await harness.send(.event(.windowFocused(c)))
        await harness.send(.event(.windowFocused(a)))

        try #require(moves(await camera(.view(three), &harness, focused: a)).count == 1)
        #expect(harness.arranger.camera.pending["main"]?.focus == c)

        try await zoom(&harness, to: .home)
        try #require(moves(await camera(.view(three), &harness, focused: c)).count == 1)
        #expect(harness.arranger.camera.pending["main"]?.focus == nil, "focus inside the view stays")
    }

    /// VIEW-02, D-14: a view written to layout.json and loaded by a fresh Arranger lands on the same windows.
    @Test func aViewSurvivesASnapshotAndARestore() async throws {
        var harness = try await fourDocked()
        let node = try await savedCAndD(&harness)
        let snapshot = harness.arranger.snapshot
        #expect(snapshot.views.map(\.slot) == [three] && snapshot.views.first?.windows == [c.identity, d.identity])

        var restored = Harness()
        restored.arranger = Arranger()
        await restored.send(.restore(snapshot.world, homeFrames: snapshot.homeFrames, views: snapshot.views))
        #expect(restored.arranger.snapshot.views == snapshot.views, "a write before the re-attach loses no view")
        await restored.send(.inventory(await harness.fake.inventory()))
        await restored.send(.zoomEnabled(true))
        let move = try #require(moves(await camera(.view(three), &restored)).first)
        #expect(move.to == .node(node))
    }

    /// D-02, RESEARCH Pitfall 3: a rekey rewrites the identity in every view, so going there still frames the window.
    @Test func aWindowRekeyRewritesTheIdentityInEveryView() async throws {
        var harness = try await fourDocked()
        let node = try await savedCAndD(&harness)
        let four = ViewSlot(4)!
        try await zoom(&harness, to: .node(node))
        await camera(.saveView(four), &harness)
        try await zoom(&harness, to: .home)
        let renamed = ref(30)
        var info = try #require(harness.arranger.windows[c.identity])
        info.window = renamed
        await harness.send(.event(.windowRekeyed(from: c, to: info)))

        #expect(harness.arranger.camera.savedViews[three]?.windows == [d.identity, renamed.identity])
        #expect(harness.arranger.camera.savedViews[four]?.windows == [d.identity, renamed.identity])
        #expect(moves(await camera(.view(three), &harness)).first?.to == .node(try lca([renamed, d], harness)))
    }

    /// The remap keeps slots sorted and each window list sorted and unique: an unsorted list would make layout.json invalid.
    @Test func aRemapKeepsTheViewsSortedAndUnique() async throws {
        var harness = try await fourDocked()
        _ = try await savedCAndD(&harness)
        let five = ViewSlot(5)!
        await camera(.saveView(five), &harness)
        harness.arranger.camera.savedViews.save(SavedView(slot: ViewSlot(1)!, desk: key, home: false, windows: [a.identity, c.identity]))

        harness.arranger.remapViews(from: a.identity, to: ref(9).identity)
        harness.arranger.remapViews(from: c.identity, to: ref(8).identity)
        harness.arranger.remapViews(from: d.identity, to: ref(8).identity)

        let views = harness.arranger.camera.savedViews.sorted
        #expect(views.map(\.slot.number) == [1, 3, 5])
        #expect(views[0].windows == [ref(8).identity, ref(9).identity], "re-sorted by identity")
        #expect(views[1].windows == [ref(8).identity], "two identities that became one are kept once")
        #expect(views[2].home && views[2].windows.isEmpty)
    }

    /// RESEARCH Pitfall 3: a relaunch match rewrites the loaded view; the view lands on the windows that came back.
    @Test func aRelaunchMatchRewritesTheLoadedViews() async throws {
        var source = try await fourDocked()
        for (id, title) in [(UInt32(1), "Notes"), (2, "Plan"), (3, "Chart"), (4, "Mail")] { await source.fake.update(id) { $0.title = title } }
        _ = await source.refresh()
        _ = try await savedCAndD(&source)
        let saved = source.arranger.snapshot

        let newPID: Int32 = 901
        func relaunched(_ id: UInt32) -> WindowRef { WindowRef(identity: WindowIdentity(windowID: id, pid: newPID, bundleID: bundleID)) }
        var harness = Harness()
        await harness.fake.setDisplays(await source.fake.inventory().displays)
        await harness.fake.addApp(FakeApp(pid: newPID, bundleID: bundleID))
        for (id, title) in [(UInt32(11), "Mail"), (12, "Chart"), (13, "Plan"), (14, "Notes")] {
            await harness.fake.open(.standard(id: id, pid: newPID, frame: Rect(x: 100, y: 100, width: 300, height: 200), title: title))
        }
        await harness.fake.refreshAll()
        _ = await harness.inbox.take()
        await harness.send(.restore(saved.world, homeFrames: [:], views: saved.views))
        await harness.send(.inventory(await harness.fake.inventory()))
        await harness.send(.zoomEnabled(true))

        #expect(harness.arranger.camera.savedViews[three]?.windows == [relaunched(11).identity, relaunched(12).identity])
        let node = try lca([relaunched(11), relaunched(12)], harness)
        #expect(moves(await camera(.view(three), &harness)).first?.to == .node(node))
    }

    /// After a reboot a returning window can carry another saved window's ID: the view must not chain the two rewrites.
    @Test func matchesOnReusedIdentitiesAreRemappedTogether() async throws {
        var source = try await fourDocked()
        for (id, title) in [(UInt32(1), "Notes"), (2, "Plan"), (3, "Chart"), (4, "Mail")] { await source.fake.update(id) { $0.title = title } }
        _ = await source.refresh()
        _ = try await savedCAndD(&source)  // c and d: "Chart" and "Mail"
        let saved = source.arranger.snapshot

        var harness = Harness()
        await harness.fake.setDisplays(await source.fake.inventory().displays)
        await harness.fake.addApp(FakeApp(pid: pid, bundleID: bundleID))
        // Window 4 (d's old ID) is "Chart" now, and "Mail" came back as window 5.
        for (id, title) in [(UInt32(1), "Notes"), (2, "Plan"), (4, "Chart"), (5, "Mail")] {
            await harness.fake.open(.standard(id: id, pid: pid, frame: Rect(x: 100, y: 100, width: 300, height: 200), title: title))
        }
        await harness.fake.refreshAll()
        _ = await harness.inbox.take()
        await harness.send(.restore(saved.world, homeFrames: [:], views: saved.views, bootChanged: true))
        await harness.send(.inventory(await harness.fake.inventory()))

        #expect(harness.arranger.camera.savedViews[three]?.windows == [ref(4).identity, ref(5).identity])
    }

    /// UI-SPEC Surface 1: a saved view reaches layout.json with the next debounced save, though no window changed (CR-01).
    @Test func savingAViewSchedulesASave() async throws {
        var harness = try await fourDocked()
        let saved = await camera(.saveView(three), &harness)
        #expect(notices(saved).count == 1)
        #expect(has(.save(.debounced), saved))
        let went = await camera(.view(three), &harness)
        #expect(!has(.save(.debounced), went), "going to a view changes nothing to save")
    }

    /// D-05: an identity no desk holds is pruned at the snapshot; a view left with none keeps its slot and desk and goes home.
    @Test func theSnapshotPrunesIdentitiesNoDeskHolds() async throws {
        var harness = try await fourDocked()
        _ = try await savedCAndD(&harness)
        await harness.fake.close(3)
        _ = await harness.refresh()
        #expect(harness.arranger.snapshot.views.first?.windows == [d.identity])

        await harness.fake.close(4)
        _ = await harness.refresh()
        let view = try #require(harness.arranger.snapshot.views.first)
        #expect(view.slot == three && view.desk == key && !view.home && view.windows.isEmpty)
        #expect(harness.arranger.viewDestination(view).target == .home && harness.arranger.viewDestination(view).allGone)
    }

    /// The shell's view of a slot (D-03): where it goes, before any Space is switched.
    @Test func theDestinationNamesTheDeskTargetAndWhetherAllAreGone() async throws {
        var harness = try await fourDocked()
        #expect(harness.arranger.viewDestination(slot: three) == nil, "an empty slot has none")
        let node = try await savedCAndD(&harness)
        var destination = try #require(harness.arranger.viewDestination(slot: three))
        #expect(destination.key == key && destination.target == .node(node) && !destination.allGone)
        #expect(destination.alive == 2 && destination.total == 2)

        await harness.fake.close(3)
        await harness.fake.close(4)
        _ = await harness.refresh()
        destination = try #require(harness.arranger.viewDestination(slot: three))
        #expect(destination.key == key && destination.target == .home && destination.allGone)
        #expect(destination.alive == 0 && destination.total == 2)
        #expect(harness.arranger.savedViewSlots == [3])
    }

    /// D-03: addressed to the display showing the desk, the camera moves there wherever the pointer is. Addressed to
    /// another display it only refuses: that display does not show the desk.
    @Test func goingZoomsTheDestinationDisplayNotThePointers() async throws {
        let onMain = Rect(x: 40, y: 80, width: 320, height: 232)
        var harness = Harness()
        await harness.fake.setDisplays([
            DisplayInfo(uuid: "main", frame: Rect(x: 0, y: 0, width: 1440, height: 900), visibleFrame: Rect(x: 0, y: 25, width: 1440, height: 875), currentSpaceID: nil),
            DisplayInfo(uuid: "side", frame: Rect(x: 1440, y: 0, width: 1920, height: 1080), visibleFrame: Rect(x: 1440, y: 25, width: 1920, height: 1055), currentSpaceID: nil),
        ])
        await harness.fake.addApp(FakeApp(pid: pid, bundleID: bundleID))
        await harness.fake.open(.standard(id: 1, pid: pid, frame: onMain))
        await harness.fake.open(.standard(id: 2, pid: pid, frame: Rect(x: 1480, y: 80, width: 320, height: 232)))
        await harness.fake.open(.standard(id: 3, pid: pid, frame: Rect(x: 2900, y: 600, width: 320, height: 232)))
        await harness.fake.refreshAll()
        _ = await harness.inbox.take()
        await harness.send(.inventory(await harness.fake.inventory()))
        // c docked beside b, so b's leaf is not the side desk's root (which would be the home view).
        for window in [b, c] { await harness.send(.command(.dock, focused: window)) }
        await harness.send(.zoomEnabled(true))
        let leaf = try #require(harness.arranger.leafNode(of: b))
        let toLeaf = try #require(moves(await harness.send(.zoomTo(.node(leaf), displayUUID: "side"))).first)
        await harness.send(.cameraSettle(displayUUID: "side", moveID: toLeaf.id))
        await harness.send(.camera(.saveView(three), displayUUID: "side", focused: nil, pointer: nil))
        let toHome = try #require(moves(await harness.send(.zoomTo(.home, displayUUID: "side"))).first)
        await harness.send(.cameraSettle(displayUUID: "side", moveID: toHome.id))
        await harness.send(.event(.windowFocused(b)))
        await harness.send(.event(.windowFocused(a)))

        let elsewhere = await harness.send(.camera(.view(three), displayUUID: "main", focused: a, pointer: Point(x: 100, y: 100)))
        #expect(moves(elsewhere).isEmpty && has(.beep, elsewhere))

        let there = await harness.send(.camera(.view(three), displayUUID: "side", focused: a, pointer: Point(x: 100, y: 100)))
        #expect(moves(there).map(\.displayUUID) == ["side"] && moves(there).first?.to == .node(leaf))
        #expect(notices(there) == [.viewShown(three, displayUUID: "side")])
        #expect(harness.arranger.camera.pending["side"]?.focus == b, "focus outside the view moves inside it")
    }

    /// UI-SPEC: every window gone and the saved Space no longer there: the shell addresses the saved display, which goes
    /// home on the Space it shows, with N17.
    @Test func allGoneOnAMissingSpaceGoesHomeOnTheDisplaysCurrentSpace() async throws {
        var harness = try await fourDocked()
        harness.arranger.camera.savedViews.save(SavedView(slot: three, desk: DeskKey(displayUUID: "main", spaceID: 99), home: false, windows: [ref(77).identity]))
        try await zoom(&harness, to: .node(try #require(harness.arranger.leafNode(of: a))))

        let shown = await camera(.view(three), &harness)

        #expect(moves(shown).first?.to == .home)
        #expect(notices(shown) == [.viewWindowsClosed(three, displayUUID: "main")])
    }

    /// T-08-03: a stored slot outside 1–9 fails to decode, so a hostile file can't address a tenth slot.
    @Test func aSlotOutsideOneToNineFailsToDecode() throws {
        let decoder = JSONDecoder()
        #expect(try decoder.decode(ViewSlot.self, from: Data("3".utf8)) == three)
        #expect(throws: DecodingError.self) { try decoder.decode(ViewSlot.self, from: Data("0".utf8)) }
        #expect(throws: DecodingError.self) { try decoder.decode(ViewSlot.self, from: Data("10".utf8)) }
        #expect(try JSONEncoder().encode(three) == Data("3".utf8))
        #expect(ViewSlot(0) == nil && ViewSlot(10) == nil && ViewSlot.all.map(\.number) == Array(1...9))
    }
}

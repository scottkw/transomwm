import TransomEngine
import TransomModel
import TransomTestSupport
import Testing

private let pid: Int32 = 900
private let newPID: Int32 = 901
private let bundleID = "com.example.arranger"
private let otherBundle = "com.example.other"
private let key = DeskKey(displayUUID: "main", spaceID: nil)

private func ref(_ id: UInt32, title: String = "", pid: Int32 = pid, bundle: String = bundleID, order: UInt64 = 0) -> WindowRef {
    WindowRef(identity: WindowIdentity(windowID: id, pid: pid, bundleID: bundle), titleHint: title, creationOrder: order)
}

private func tracked(_ window: WindowRef, frame: Rect = Rect(x: 300, y: 300, width: 400, height: 300)) -> WindowInfo {
    WindowInfo(window: window, frame: frame, state: .present, displayUUID: "main")
}

/// A window of the relaunched app, under a new pid.
private func returning(_ id: UInt32, title: String) -> WindowInfo { tracked(ref(id, title: title, pid: newPID)) }

/// [Notes (1) | Plan (2) | Other (3) | Desktop]: two docked windows of one app, titled, beside another app's.
private func threeDocked() async -> Harness {
    var harness = Harness()
    await harness.fake.setDisplays([DisplayInfo(
        uuid: "main", frame: Rect(x: 0, y: 0, width: 1440, height: 900), visibleFrame: Rect(x: 0, y: 25, width: 1440, height: 875), currentSpaceID: nil)])
    await harness.fake.addApp(FakeApp(pid: pid, bundleID: bundleID))
    await harness.fake.addApp(FakeApp(pid: 950, bundleID: otherBundle))
    await harness.fake.open(.standard(id: 1, pid: pid, frame: Rect(x: 40, y: 80, width: 320, height: 232), title: "Notes"))
    await harness.fake.open(.standard(id: 2, pid: pid, frame: Rect(x: 730, y: 400, width: 150, height: 120), title: "Plan"))
    await harness.fake.open(.standard(id: 3, pid: 950, frame: Rect(x: 1000, y: 600, width: 150, height: 120), title: "Other"))
    await harness.fake.refreshAll()
    _ = await harness.inbox.take()
    await harness.send(.inventory(await harness.fake.inventory()))
    for window in [ref(1), ref(2), ref(3, pid: 950, bundle: otherBundle)] { await harness.send(.command(.dock, focused: window)) }
    return harness
}

/// ⌘Q as the shell reports it: `.appTerminated`, then each window's `.windowDestroyed`.
private func quit(_ harness: inout Harness) async -> [ArrangerEffect] {
    var effects = await harness.send(.event(.appTerminated(pid: pid)))
    for id: UInt32 in [1, 2] { effects += await harness.send(.event(.windowDestroyed(ref(id)))) }
    return effects
}

private func tiles(_ harness: Harness) async -> [Rect] {
    var rects: [Rect] = []
    for id: UInt32 in [1, 2] { if let frame = await harness.frame(ref(id)) { rects.append(frame) } }
    return rects
}

/// VIEW-04, D-11, D-12, D-12a: a window that has not come back keeps its tile until it does, or until its deadline.
@Suite struct ArrangerPlaceholderTests {
    @Test func quitThenRelaunchRefillsBothTiles() async throws {
        var harness = await threeDocked()
        let tiled = await tiles(harness)
        try #require(tiled.count == 2)

        let held = await quit(&harness)
        #expect(harness.arranger.world[key]?.tree.windows.map(\.windowID) == [1, 2, 3], "both refs stay in the tree")
        #expect(harness.arranger.isPlaceholder(ref(1)) && harness.arranger.isPlaceholder(ref(2)))
        #expect(harness.arranger.placeholderCount == 2)
        #expect(setFrames(held).isEmpty, "a quit writes nothing: the neighbour does not reflow")
        #expect(!harness.arranger.hasDormantWindows, "a placeholder is not a dormant window, so nothing prunes it")

        await harness.send(.event(.appLaunched(pid: newPID, bundleID: bundleID)))
        // Reopened in the other order, so creation order alone would swap them.
        let plan = await harness.send(.event(.windowCreated(returning(12, title: "Plan"))))
        let notes = await harness.send(.event(.windowCreated(returning(11, title: "Notes"))))

        #expect(harness.arranger.world[key]?.tree.windows.map(\.windowID) == [11, 12, 3], "each window is back in its own leaf")
        #expect(harness.arranger.world[key]?.desktop.windows.isEmpty == true)
        #expect(harness.arranger.placeholderCount == 0)
        #expect(setFrames(plan)[ref(12, pid: newPID)] == tiled[1])
        #expect(setFrames(notes)[ref(11, pid: newPID)] == tiled[0])
        #expect((plan + notes).contains { if case .info(let line) = $0 { line.contains("filled by window 12") } else { false } })
    }

    /// Windows come back with a new identity: an inventory's CG list that lacks the old one must not close the tile.
    @Test func anInventoryNeverClosesAPlaceholder() async throws {
        var harness = await threeDocked()
        _ = await quit(&harness)
        var inventory = await harness.fake.inventory()
        inventory.windows.removeAll { $0.window.pid == pid }
        inventory.liveWindows = [CGWindowEntry(windowID: 3, pid: 950, bounds: Rect(x: 0, y: 0, width: 10, height: 10), layer: 0, onScreen: true, alpha: 1)]
        await harness.send(.inventory(inventory))
        #expect(harness.arranger.world[key]?.tree.windows.map(\.windowID) == [1, 2, 3])
        #expect(harness.arranger.placeholderCount == 2)
    }

    /// A ⌘W in a quitting window's app, or any other app's window, is not a placeholder.
    @Test func onlyDockedWindowsOfTheQuittingPidWait() async throws {
        var harness = await threeDocked()
        await harness.send(.event(.appTerminated(pid: pid)))
        await harness.send(.event(.windowDestroyed(ref(3, pid: 950, bundle: otherBundle))))
        #expect(harness.arranger.world[key]?.tree.windows.map(\.windowID) == [1, 2])
        #expect(!harness.arranger.isPlaceholder(ref(3, pid: 950, bundle: otherBundle)))
    }

    /// A placeholder keeps the latest title, which the World's ref may not have: `windows` is forgotten at the destroy.
    @Test func aPlaceholderKeepsItsWindowsLatestTitle() async throws {
        var harness = await threeDocked()
        await harness.fake.update(1) { $0.title = "Renamed" }
        _ = await harness.refresh()
        _ = await quit(&harness)
        #expect(harness.arranger.world[key]?.tree.windows.first?.titleHint == "Renamed")
    }

    /// D-02, RESEARCH Pitfall 3: a saved view follows the window that fills the placeholder.
    @Test func aSavedViewFollowsTheFilledPlaceholder() async throws {
        var harness = await threeDocked()
        await harness.send(.zoomEnabled(true))
        let leaf = try #require(harness.arranger.world[key]?.tree.leaf(containing: ref(1)))
        let move = try #require(harness.arranger.handle(.zoomTo(.node(leaf), displayUUID: "main"), now: harness.now).compactMap { effect -> CameraMove? in
            if case .cameraMove(let move) = effect { move } else { nil }
        }.first)
        await harness.send(.cameraSettle(displayUUID: "main", moveID: move.id))
        let slot = try #require(ViewSlot(1))
        await harness.send(.camera(.saveView(slot), displayUUID: "main", focused: nil, pointer: nil))
        _ = await quit(&harness)
        await harness.send(.event(.windowCreated(returning(11, title: "Notes"))))
        #expect(harness.arranger.viewDestination(slot: slot)?.alive == 1)
        #expect(harness.arranger.world[key]?.tree.leaf(containing: ref(11, pid: newPID)) == leaf)
    }
}

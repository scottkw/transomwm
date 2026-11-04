import Foundation
import TransomEngine
@testable import TransomMac
import TransomModel
import Testing

/// Within 2 pt on every side (the fixture reports whole points).
private func near(_ a: Rect, _ b: Rect) -> Bool {
    abs(a.x - b.x) <= 2 && abs(a.y - b.y) <= 2 && abs(a.width - b.width) <= 2 && abs(a.height - b.height) <= 2
}

/// The fixture's windows as the system tracks them, once all of `fixture.windows` are present with a title.
@MainActor private func trackedWithTitles(_ system: AXWindowSystem, _ fixture: FixtureProcess) async throws -> [WindowInfo] {
    let ids = fixture.windows.sorted { $0.index < $1.index }.map(\.id)
    var found: [WindowInfo] = []
    _ = await waitUntil(timeout: .seconds(3)) {
        let inventory = await system.inventory()
        guard inventory.initialRefreshComplete else { return false }
        found = ids.compactMap { id in inventory.windows.first { $0.window.windowID == id && $0.state == .present } }
        return found.count == ids.count && found.allSatisfy { !$0.window.titleHint.isEmpty }
    }
    try #require(found.count == ids.count && found.allSatisfy { !$0.window.titleHint.isEmpty }, "the fixture windows were never tracked with titles")
    return found
}

/// VIEW-04, D-10, D-11 live: an app relaunched under a new pid while Transom was not running gets each window back
/// into its own tile, matched by the titles layout.json kept. Fixture windows only; the store is a temporary
/// directory, never the user's real layout.json.
@Suite(.serialized, .enabled(if: IntegrationEnv.trusted, "needs a process with the Accessibility grant"))
@MainActor struct RematchIntegrationTests {
    @Test(.timeLimit(.minutes(1)))
    func aRelaunchedAppGetsItsTilesBackAfterATransomRelaunch() async throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: "transom-rematch-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: directory) }

        // Session 1, built headlessly: [Fixture 0 | Fixture 1 | Desktop], saved with titles.
        let first = try await FixtureProcess.launch(["standard", "standard"])
        defer { first.terminate() }
        let firstPID = first.pid
        let firstSystem = AXWindowSystem(appFilter: { pid, _ in pid == firstPID })
        await firstSystem.start()
        let windows = try await trackedWithTitles(firstSystem, first).map(\.window)
        try #require(windows.map(\.titleHint) == ["Fixture 0", "Fixture 1"], "unexpected fixture titles \(windows.map(\.titleHint))")
        var builder = Arranger()
        _ = builder.handle(.inventory(await firstSystem.inventory()), now: .now)
        let key = try #require(builder.deskKey(of: windows[0]))
        var world = builder.world, history = UndoHistory()
        try world.edit(key, history: &history) { desk, ids throws(LayoutError) in
            for window in windows where desk.desktop.contains(window) { try desk.desktop.remove(window) }
            try desk.tree.insert(windows[0], at: .left, of: .desktop, ids: &ids)
            guard let leaf = desk.tree.leaf(containing: windows[0]) else { throw .windowNotFound(windows[0]) }
            try desk.tree.insert(windows[1], at: .right, of: leaf, ids: &ids)
        }
        try #require(world[key]?.tree.windows == windows)
        try LayoutStore(directory: directory).save(LayoutFile(world: world, homeFrames: [:], session: SessionRecord(cleanExit: true, launchedAt: Date())))
        first.terminate()

        // The app relaunches (new pid, new window IDs, same titles), then Transom does.
        let second = try await FixtureProcess.launch(["standard", "standard"])
        defer { second.terminate() }
        let secondPID = second.pid
        try #require(secondPID != firstPID)
        let system = AXWindowSystem(appFilter: { pid, _ in pid == secondPID })
        await system.start()
        _ = try await trackedWithTitles(system, second)
        let arrange = ArrangeController(system: system, store: LayoutStore(directory: directory))
        defer { withExtendedLifetime(arrange) {} }  // its events loop ends with it
        await arrange.start()

        let visible = try #require(Displays.current().first { $0.uuid == key.displayUUID }).visibleFrame
        let tiles = try Planner.plan(desk: try #require(world[key]), area: visible, gap: arrange.arranger.gap, mins: [:]).frames
        let wanted = [try #require(tiles[windows[0]]), try #require(tiles[windows[1]])]
        var frames: [Rect?] = []
        let back = await waitUntil(timeout: .seconds(5)) {
            _ = try? await second.send("list")
            frames = (0..<2).map { index in second.windows.first { $0.index == index }?.frame }
            return zip(frames, wanted).allSatisfy { frame, tile in frame.map { near($0, tile) } ?? false }
        }
        #expect(back, "Fixture 0 / Fixture 1 are at \(frames), not their tiles \(wanted)")
        let docked = arrange.arranger.world[key]?.tree.windows ?? []
        #expect(docked.map(\.pid) == [secondPID, secondPID], "the relaunched windows are not docked: \(docked)")
    }

    /// D-11, D-12a live: an app quits while Transom runs, so its two docked tiles stay reserved and the third tile keeps
    /// its size; it relaunches, and each window goes back into its own tile. Prints the order the events arrived in
    /// (RESEARCH Assumption A1). Fixture windows only; the store is a temporary directory.
    @Test(.timeLimit(.minutes(1)))
    func quitAndRelaunchRefillsBothTiles() async throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: "transom-quit-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: directory) }

        let first = try await FixtureProcess.launch(["standard", "standard"])
        defer { first.terminate() }
        let keeper = try await FixtureProcess.launch(["standard"])
        defer { keeper.terminate() }
        let firstPID = first.pid
        // By bundle, not by pid: the relaunched fixture must reach the tracker as a launch.
        let system = AXWindowSystem(appFilter: { _, bundle in bundle == "unbundled:TransomFixtureApp" })
        await system.start()
        let windows = try await trackedWithTitles(system, first).map(\.window)
        let third = try await trackedWithTitles(system, keeper)[0].window
        let arrange = ArrangeController(system: system, store: LayoutStore(directory: directory))
        defer { withExtendedLifetime(arrange) {} }
        await arrange.start()
        var order: [String] = []
        arrange.onEvent = { event in
            switch event {
            case .appTerminated(let pid) where pid == firstPID: order.append("appTerminated")
            case .windowDestroyed(let window) where window.pid == firstPID: order.append("windowDestroyed \(window.windowID)")
            default: break
            }
        }
        for window in windows + [third] {
            await arrange.dispatch(.dock, focused: window)
            try #require(arrange.arranger.deskKey(of: window).flatMap { arrange.arranger.world[$0]?.tree.state(of: window) } == .present, "\(window) did not dock")
        }
        func current(_ fixture: FixtureProcess, _ index: Int) async -> Rect? {
            _ = try? await fixture.send("list")
            return fixture.windows.first { $0.index == index }?.frame
        }
        let key = try #require(arrange.arranger.deskKey(of: windows[0]))
        let visible = try #require(Displays.current().first { $0.uuid == key.displayUUID }).visibleFrame
        let tiles = try Planner.plan(desk: try #require(arrange.arranger.world[key]), area: visible, gap: arrange.arranger.gap, mins: [:]).frames
        let wanted = [try #require(tiles[windows[0]]), try #require(tiles[windows[1]])]
        let thirdTile = try #require(tiles[third])
        let settled = await waitUntil(timeout: .seconds(3)) {
            let frames = [await current(first, 0), await current(first, 1), await current(keeper, 0)]
            return zip(frames, wanted + [thirdTile]).allSatisfy { frame, tile in frame.map { near($0, tile) } ?? false }
        }
        try #require(settled, "the three windows never reached their tiles")

        _ = try await first.send("quit")
        let held = await waitUntil(timeout: .seconds(2)) { windows.allSatisfy(arrange.arranger.isPlaceholder) }
        print("A1 event order on quit: \(order)")
        #expect(held, "the tiles are not reserved after the quit; events: \(order)")
        #expect(await current(keeper, 0).map { near($0, thirdTile) } == true, "the third tile changed")

        let second = try await FixtureProcess.launch(["standard", "standard"])
        defer { second.terminate() }
        var frames: [Rect?] = []
        let back = await waitUntil(timeout: .seconds(5)) {
            frames = [await current(second, 0), await current(second, 1)]
            return zip(frames, wanted).allSatisfy { frame, tile in frame.map { near($0, tile) } ?? false }
        }
        #expect(back, "Fixture 0 / Fixture 1 are at \(frames), not their tiles \(wanted)")
        #expect(arrange.arranger.placeholderCount == 0)
        #expect(await current(keeper, 0).map { near($0, thirdTile) } == true, "the third tile changed")
    }
}

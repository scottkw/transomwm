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
}

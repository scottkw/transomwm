import Foundation
import TransomEngine
@testable import TransomMac
import TransomModel
import Testing

private func intersection(_ a: Rect, _ b: Rect) -> (width: Double, height: Double) {
    (max(0, min(a.maxX, b.maxX) - max(a.minX, b.minX)), max(0, min(a.maxY, b.maxY) - max(a.minY, b.minY)))
}

/// TABS-01, D-04, D-07 live: tab groups against fixture windows only (never another app). The store is a temporary
/// directory, never the user's real layout.json.
@Suite(.serialized, .enabled(if: IntegrationEnv.trusted, "needs a process with the Accessibility grant"))
@MainActor struct TabGroupIntegrationTests {
    /// A saved group [0, 1] with window 1 selected: a fresh controller puts window 1 in the content rect (the tile minus
    /// the 32 pt band) and parks window 0 at the content size, a sliver on screen.
    @Test(.timeLimit(.minutes(1)))
    func aSavedGroupReformsWithTheHiddenMemberParkedAtTheContentSize() async throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: "transom-tabs-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: directory) }
        let fixture = try await FixtureProcess.launch(["standard", "standard"])
        defer { fixture.terminate() }
        let fixturePID = fixture.pid
        let system = AXWindowSystem(appFilter: { pid, _ in pid == fixturePID })
        await system.start()
        let ids = fixture.windows.sorted { $0.index < $1.index }.map(\.id)
        try #require(ids.count == 2)
        var found: [WindowInfo] = []
        _ = await waitUntil(timeout: .seconds(3)) {
            let inventory = await system.inventory()
            guard inventory.initialRefreshComplete else { return false }
            found = ids.compactMap { id in inventory.windows.first { $0.window.windowID == id && $0.state == .present } }
            return found.count == 2
        }
        try #require(found.count == 2, "the fixture windows were never tracked")
        let hidden = found[0].window, selected = found[1].window

        // Built headlessly: window 0 docked, then window 1 grouped into its leaf (selected, D-03).
        var builder = Arranger()
        _ = builder.handle(.inventory(await system.inventory()), now: .now)
        _ = builder.handle(.command(.dock, focused: hidden), now: .now)
        let key = try #require(builder.deskKey(of: hidden))
        let leaf = try #require(builder.world[key]?.tree.leaf(containing: hidden), "window 0 did not dock")
        var world = builder.world, history = UndoHistory()
        try world.edit(key, history: &history) { desk, _ throws(LayoutError) in
            if desk.desktop.contains(selected) { try desk.desktop.remove(selected) }
            try desk.tree.group(selected, into: leaf)
        }
        try #require(world[key]?.tree.node(leaf) == .tabs(windows: [hidden, selected], selected: 1))
        try LayoutStore(directory: directory).save(
            LayoutFile(world: world, homeFrames: [:], session: SessionRecord(cleanExit: true, launchedAt: Date())))

        let arrange = ArrangeController(system: system, store: LayoutStore(directory: directory))
        defer { withExtendedLifetime(arrange) {} }  // its events loop ends with it
        await arrange.start()
        let visible = try #require(Displays.current().first { $0.uuid == key.displayUUID }).visibleFrame

        var content: Rect?
        var last: [Rect] = []
        let formed = await waitUntil(timeout: .seconds(3)) {
            guard let desk = arrange.arranger.world[key],
                let tile = try? Planner.plan(desk: desk, area: visible, gap: arrange.arranger.gap, mins: [:]).resolution.nodeRects[leaf]
            else { return false }
            let rect = TabBand.content(of: tile)
            content = rect
            _ = try? await fixture.send("list")
            last = fixture.windows.sorted { $0.index < $1.index }.map(\.frame)
            guard last.count == 2 else { return false }
            let shown = last[1], parked = last[0], sliver = intersection(parked, visible)
            return abs(shown.x - rect.x) <= 2 && abs(shown.y - rect.y) <= 2 && abs(shown.width - rect.width) <= 2
                && abs(shown.height - rect.height) <= 2 && sliver.width * sliver.height < 40 * 40
                && abs(parked.width - rect.width) <= 1 && abs(parked.height - rect.height) <= 1
        }
        #expect(formed, "windows at \(last), content rect \(String(describing: content)), visible \(visible)")
        #expect(arrange.arranger.world[key]?.tree.node(leaf) == .tabs(windows: [hidden, selected], selected: 1), "the saved group did not come back")
        #expect(arrange.arranger.isParked(hidden))
    }
}

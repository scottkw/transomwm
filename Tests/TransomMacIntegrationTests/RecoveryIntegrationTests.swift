import Foundation
import TransomEngine
@testable import TransomMac
import TransomModel
import Testing

/// Inside `outer`, allowing 1 pt for the fixture's integer rounding.
private func within(_ rect: Rect, _ outer: Rect) -> Bool {
    rect.minX >= outer.minX - 1 && rect.minY >= outer.minY - 1 && rect.maxX <= outer.maxX + 1 && rect.maxY <= outer.maxY + 1
}

/// The share of `rect`'s area inside the displays' visible frames (they never overlap).
private func visibleFraction(_ rect: Rect, _ displays: [DisplayInfo]) -> Double {
    let inside = displays.map(\.visibleFrame).reduce(0.0) { sum, d in
        sum + max(0, min(rect.maxX, d.maxX) - max(rect.minX, d.minX)) * max(0, min(rect.maxY, d.maxY) - max(rect.minY, d.minY))
    }
    return inside / (rect.width * rect.height)
}

/// SAFE-02 live: after an unclean exit, a fresh controller brings a stranded fixture window back on screen and puts it
/// back in its tile. The store is a temporary directory, never the user's real layout.json; only fixture windows move.
@Suite(.serialized, .enabled(if: IntegrationEnv.trusted, "needs a process with the Accessibility grant"))
@MainActor struct RecoveryIntegrationTests {
    /// Window 0 docked, window 1 floating, both pushed off every display. The floating one is the real test: nothing
    /// but the recovery rule moves a floating window, while the docked one would go back to its tile anyway.
    @Test(.timeLimit(.minutes(1)))
    func strandedWindowsComeBackOnScreenAfterAnUncleanExit() async throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: "transom-recovery-\(UUID().uuidString)", directoryHint: .isDirectory)
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
        let docked = found[0].window, floating = found[1].window

        // What a session that crashed leaves: window 0 docked, window 1 floating, and cleanExit false.
        var crashed = Arranger()
        _ = crashed.handle(.inventory(await system.inventory()), now: .now)
        _ = crashed.handle(.command(.dock, focused: docked), now: .now)
        let key = try #require(crashed.deskKey(of: docked))
        try #require(crashed.world[key]?.tree.state(of: docked) == .present, "window 0 did not dock")
        try #require(crashed.world[key]?.desktop.contains(floating) == true, "window 1 is not floating on the same desk")
        try LayoutStore(directory: directory).save(
            LayoutFile(world: crashed.world, homeFrames: [:], session: SessionRecord(cleanExit: false, launchedAt: Date())))

        // Past every display, not just the main one (this Mac may have a display to its right). macOS may keep a sliver
        // on screen, so "away" means less than half of each window is visible.
        let displays = Displays.current()
        let farX = (displays.map(\.frame.maxX).max() ?? 0) + 2000
        for index in 0..<2 { _ = try await fixture.send("move \(index) \(Int(farX)) \(200 + 100 * index)") }
        var seen: [Rect] = []
        let away = await waitUntil(timeout: .seconds(3)) {
            let windows = await system.inventory().windows
            seen = ids.compactMap { id in windows.first { $0.window.windowID == id }?.frame }
            return seen.count == 2 && seen.allSatisfy { visibleFraction($0, displays) < 0.5 }
        }
        _ = try? await fixture.send("list")
        try #require(away, "the fixture windows never went off screen: tracked \(seen), fixture \(fixture.windows.map(\.frame))")

        let arrange = ArrangeController(system: system, store: LayoutStore(directory: directory))
        defer { withExtendedLifetime(arrange) {} }  // its events loop ends with it
        await arrange.start()
        let visible = try #require(displays.first { $0.uuid == key.displayUUID }).visibleFrame
        var last: [Rect] = []
        let back = await waitUntil(timeout: .seconds(5)) {
            _ = try? await fixture.send("list")
            last = fixture.windows.sorted { $0.index < $1.index }.map(\.frame)
            return last.count == 2 && last.allSatisfy { within($0, visible) }
        }
        #expect(back, "the windows are at \(last), not inside \(visible)")
        #expect(arrange.arranger.world[key]?.tree.state(of: docked) == .present, "the saved layout did not come back")
        #expect(arrange.arranger.world[key]?.desktop.contains(floating) == true, "window 1 no longer floats")
    }
}

import AppKit
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

    /// D-D, 04-08: three docked windows zoomed to window 0 (1 and 2 parked), then Transom "crashes": the controller goes
    /// with no quit restore and no clean exit. A fresh controller on the same store (a recovery launch, zoom on) has every
    /// window back in its home tile within 3 s, none stranded.
    @Test(.timeLimit(.minutes(1)))
    func aRelaunchAfterACrashWhileZoomedBringsWindowsBack() async throws {
        _ = NSApplication.shared  // the stage needs the window server connection (ZoomSettleIntegrationTests)
        let directory = FileManager.default.temporaryDirectory.appending(path: "transom-recovery-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: directory) }
        let fixture = try await FixtureProcess.launch(["standard", "standard", "standard"])
        defer { fixture.terminate() }
        let fixturePID = fixture.pid
        func listed() async -> [Rect] {
            _ = try? await fixture.send("list")
            return fixture.windows.sorted { $0.index < $1.index }.map(\.frame)
        }
        func near(_ a: Rect, _ b: Rect) -> Bool {
            abs(a.x - b.x) <= 2 && abs(a.y - b.y) <= 2 && abs(a.width - b.width) <= 2 && abs(a.height - b.height) <= 2
        }

        var tiles: [Rect] = []
        var display: DisplayInfo?
        do {  // the session that crashes
            let system = AXWindowSystem(appFilter: { pid, _ in pid == fixturePID })
            await system.start()
            var crashing: ArrangeController? = ArrangeController(system: system, store: LayoutStore(directory: directory), zoomEnabled: true)
            await crashing?.start()
            let arrange = try #require(crashing)
            var refs: [TransomModel.WindowRef] = []
            for window in fixture.windows.sorted(by: { $0.index < $1.index }) {
                func find() -> TransomModel.WindowRef? {
                    arrange.arranger.windows.values.first { $0.window.pid == fixturePID && $0.window.windowID == window.id }?.window
                }
                _ = await waitUntil(timeout: .seconds(3)) { find().map { arrange.arranger.deskKey(of: $0) != nil } ?? false }
                refs.append(try #require(find(), "window \(window.id) never reached a desk"))
            }
            await arrange.dispatch(.arrangeAll, focused: refs[0])
            let key = try #require(arrange.arranger.deskKey(of: refs[0]))
            try #require(refs.allSatisfy { arrange.arranger.world[key]?.tree.state(of: $0) == .present }, "Arrange All did not dock all three")
            let screen = try #require(Displays.current().first { $0.uuid == key.displayUUID })
            display = screen
            let tiled = await waitUntil(timeout: .seconds(3)) {
                tiles = await listed()
                return tiles.count == 3 && tiles.indices.allSatisfy { i in tiles.indices.allSatisfy { j in i == j || !tiles[i].overlaps(tiles[j]) } }
                    && tiles.allSatisfy { !Recovery.isStranded($0, displays: [screen]) }
            }
            try #require(tiled, "the windows never tiled: \(tiles)")
            try await Task.sleep(for: .milliseconds(300))  // the last clamps land
            tiles = await listed()

            let leaf = try #require(arrange.arranger.leafNode(of: refs[0]))
            await arrange.zoom(to: .node(leaf), displayUUID: screen.uuid)
            var zoomed: [Rect] = []
            let parked = await waitUntil(timeout: .seconds(3)) {
                zoomed = await listed()
                return zoomed.count == 3 && zoomed.dropFirst().allSatisfy { Recovery.isStranded($0, displays: [screen]) }
            }
            try #require(parked, "zooming in did not park windows 1 and 2: \(zoomed)")
            _ = await waitUntil(timeout: .seconds(3)) { arrange.zoomController?.isIdle == true }
            crashing = nil  // the crash: no restoreForTermination, no writeCleanExit
        }
        let screen = try #require(display)
        let store = LayoutStore(directory: directory)
        store.load()
        try #require(store.contents?.session.cleanExit == false, "the crashed session left a clean exit")

        let system = AXWindowSystem(appFilter: { pid, _ in pid == fixturePID })
        await system.start()
        let relaunched = ArrangeController(system: system, store: LayoutStore(directory: directory), zoomEnabled: true)
        defer { withExtendedLifetime(relaunched) {} }  // its events loop ends with it
        await relaunched.start()
        var last: [Rect] = []
        let back = await waitUntil(timeout: .seconds(3)) {
            last = await listed()
            return last.count == 3 && last.indices.allSatisfy { near(last[$0], tiles[$0]) && !Recovery.isStranded(last[$0], displays: [screen]) }
        }
        #expect(back, "after the relaunch the windows are at \(last), not back in \(tiles)")
        #expect(relaunched.arranger.view(on: screen.uuid) == .home)
    }
}


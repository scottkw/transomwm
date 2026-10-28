import AppKit
import Foundation
import TransomEngine
@testable import TransomMac
import TransomModel
import Testing

/// Within 2 pt on every side (the fixture reports whole points).
private func near(_ a: Rect, _ b: Rect) -> Bool {
    abs(a.x - b.x) <= 2 && abs(a.y - b.y) <= 2 && abs(a.width - b.width) <= 2 && abs(a.height - b.height) <= 2
}

/// The fixture's current frame for window `index`, from `list`.
private func listedFrame(_ fixture: FixtureProcess, _ index: Int) async throws -> Rect? {
    _ = try await fixture.send("list")
    return fixture.windows.first { $0.index == index }?.frame
}

/// A system tracking only `pids`, started, with every window of `fixtures` tracked. Refs are in fixture, then index order.
@MainActor private func tracking(_ fixtures: [FixtureProcess]) async throws -> (AXWindowSystem, [TransomModel.WindowRef]) {
    let pids = Set(fixtures.map(\.pid))
    let system = AXWindowSystem(appFilter: { pid, _ in pids.contains(pid) })
    await system.start()
    var refs: [TransomModel.WindowRef] = []
    for fixture in fixtures {
        for window in fixture.windows.sorted(by: { $0.index < $1.index }) {
            func find() async -> WindowInfo? {
                await system.inventory().windows.first { $0.window.pid == fixture.pid && $0.window.windowID == window.id && $0.state == .present }
            }
            _ = await waitUntil(timeout: .seconds(3)) { await find() != nil }
            refs.append(try #require(await find(), "window \(window.id) never tracked").window)
        }
    }
    return (system, refs)
}

/// SAFE-01 live (D-15, Pattern 11): the quit restore puts a parked fixture window back at its home frame, and a hung app
/// never holds it past its limit. Fixture windows only; nothing is persisted.
@Suite(.serialized, .enabled(if: IntegrationEnv.trusted, "needs a process with the Accessibility grant"))
@MainActor struct QuitRestoreIntegrationTests {
    /// Window 0 docked, window 1 floating; hiding the Desktop parks window 1. The quit restore brings it home and leaves
    /// the docked window alone.
    @Test(.timeLimit(.minutes(1)))
    func theQuitRestoreReturnsAParkedWindowToItsHomeFrame() async throws {
        let fixture = try await FixtureProcess.launch(["standard", "standard"])
        defer { fixture.terminate() }
        let (system, refs) = try await tracking([fixture])
        try #require(refs.count == 2)
        var arrange: ArrangeController? = ArrangeController(system: system)
        await arrange?.start()
        let controller = try #require(arrange)
        let onDesk = await waitUntil(timeout: .seconds(3)) { refs.allSatisfy { controller.arranger.deskKey(of: $0) != nil } }
        try #require(onDesk, "the fixture windows never reached a desk")

        await controller.dispatch(.dock, focused: refs[0])
        let key = try #require(controller.arranger.deskKey(of: refs[0]))
        try #require(controller.arranger.world[key]?.tree.state(of: refs[0]) == .present, "window 0 did not dock")
        try #require(controller.arranger.isFloating(refs[1]), "window 1 is not floating")
        await controller.dispatch(.toggleDesktop, focused: refs[0])
        let home = try #require(controller.arranger.homeFrames[refs[1].identity], "hiding the Desktop recorded no home frame")
        var parkedAt: Rect?
        let parked = await waitUntil(timeout: .seconds(3)) {
            parkedAt = try? await listedFrame(fixture, 1)
            return parkedAt.map { !near($0, home) } ?? false
        }
        try #require(parked, "window 1 never left its home frame \(home): \(String(describing: parkedAt))")
        let dockedFrame = try #require(try await listedFrame(fixture, 0))

        let restored = controller.restoreForTermination(limit: .seconds(2))
        arrange = nil  // Transom exits after the restore: nothing may react to the move
        #expect(restored == 1)
        let back = try #require(try await listedFrame(fixture, 1))
        #expect(near(back, home), "window 1 is at \(back), not its home frame \(home)")
        let docked = try #require(try await listedFrame(fixture, 0))
        #expect(near(docked, dockedFrame), "the docked window moved from \(dockedFrame) to \(docked)")
    }

    /// D-D, 04-08: three docked windows, zoomed to window 0 (the other two parked). The quit restore puts every one back
    /// in its home tile, and none is left stranded.
    @Test(.timeLimit(.minutes(1)))
    func quitWhileZoomedRestoresHomeTiles() async throws {
        _ = NSApplication.shared  // the stage needs the window server connection (ZoomSettleIntegrationTests)
        let fixture = try await FixtureProcess.launch(["standard", "standard", "standard"])
        defer { fixture.terminate() }
        let (system, refs) = try await tracking([fixture])
        try #require(refs.count == 3)
        var arrange: ArrangeController? = ArrangeController(system: system, zoomEnabled: true)
        await arrange?.start()
        let controller = try #require(arrange)
        let onDesk = await waitUntil(timeout: .seconds(3)) { refs.allSatisfy { controller.arranger.deskKey(of: $0) != nil } }
        try #require(onDesk, "the fixture windows never reached a desk")
        await controller.dispatch(.arrangeAll, focused: refs[0])
        let key = try #require(controller.arranger.deskKey(of: refs[0]))
        try #require(refs.allSatisfy { controller.arranger.world[key]?.tree.state(of: $0) == .present }, "Arrange All did not dock all three")
        let display = try #require(Displays.current().first { $0.uuid == key.displayUUID })
        var tiles: [Rect] = []
        let tiled = await waitUntil(timeout: .seconds(3)) {
            tiles = []
            for index in refs.indices { if let frame = try? await listedFrame(fixture, index) { tiles.append(frame) } }
            return tiles.count == 3 && refs.indices.allSatisfy { i in refs.indices.allSatisfy { j in i == j || !tiles[i].overlaps(tiles[j]) } }
                && tiles.allSatisfy { !Recovery.isStranded($0, displays: [display]) }
        }
        try #require(tiled, "the windows never tiled: \(tiles)")
        try await Task.sleep(for: .milliseconds(300))  // the last clamps land
        tiles = []
        for index in refs.indices { tiles.append(try #require(try await listedFrame(fixture, index))) }

        let leaf = try #require(controller.arranger.leafNode(of: refs[0]))
        await controller.zoom(to: .node(leaf), displayUUID: display.uuid)
        var zoomed: [Rect] = []
        let parked = await waitUntil(timeout: .seconds(3)) {
            zoomed = []
            for index in refs.indices { if let frame = try? await listedFrame(fixture, index) { zoomed.append(frame) } }
            return zoomed.count == 3 && !near(zoomed[0], tiles[0]) && zoomed.dropFirst().allSatisfy { Recovery.isStranded($0, displays: [display]) }
        }
        try #require(parked, "zooming in did not park windows 1 and 2: \(zoomed)")
        _ = await waitUntil(timeout: .seconds(3)) { controller.zoomController?.isIdle == true }

        let restored = controller.restoreForTermination(limit: .seconds(2))
        arrange = nil  // Transom exits after the restore: nothing may react to the move
        #expect(restored == 3)
        for index in refs.indices {
            let back = try #require(try await listedFrame(fixture, index))
            #expect(near(back, tiles[index]), "window \(index) is at \(back), not its home tile \(tiles[index])")
            #expect(!Recovery.isStranded(back, displays: [display]), "window \(index) is stranded at \(back)")
        }
    }

    /// Pitfall 14, T-03-42: with a second app stopped and one of its windows in the plan, the restore still returns
    /// within its limit and moves the first app's window.
    @Test(.timeLimit(.minutes(1)))
    func aHungAppIsAbandonedAtTheDeadline() async throws {
        let first = try await FixtureProcess.launch(["standard"])
        defer { first.terminate() }
        let hung = try await FixtureProcess.launch(["standard"])
        defer { hung.terminate() }
        let (system, refs) = try await tracking([first, hung])
        try #require(refs.count == 2)
        let old = try #require(first.windows.first).frame
        let target = Rect(x: old.x + 60, y: old.y + 40, width: old.width, height: old.height)

        hung.stop()
        defer { hung.resume() }
        let start = ContinuousClock.now
        let restored = system.restoreForTermination([refs[0]: target, refs[1]: old], deadline: .now() + 2.0)
        let elapsed = start.duration(to: .now)
        #expect(elapsed < .milliseconds(2500), "the restore took \(elapsed)")
        #expect(restored == 1)
        let moved = try #require(try await listedFrame(first, 0))
        #expect(near(moved, target), "the responsive window is at \(moved), not \(target)")
    }
}

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

/// SAFE-01 live (D-15, Pattern 11): the quit restore puts a parked fixture window back on screen, and a hung app
/// never holds it past its limit. Fixture windows only; nothing is persisted.
@Suite(.serialized, .enabled(if: IntegrationEnv.trusted, "needs a process with the Accessibility grant"))
@MainActor struct QuitRestoreIntegrationTests {
    /// Window 0 docked, window 1 floating; with Transom paused, window 1 is moved to the park rect. The quit restore brings
    /// it back on screen and leaves the docked window alone.
    @Test(.timeLimit(.minutes(1)))
    func theQuitRestoreBringsAParkedFloaterBackOnScreen() async throws {
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
        let displays = Displays.current()
        let display = try #require(displays.first { $0.uuid == key.displayUUID })
        // The dock's frame write lands a moment after the command: read window 0 once it is at its tile, not mid-move.
        let desk = try #require(controller.arranger.world[key])
        let tile = try #require(try Planner.plan(desk: desk, area: display.visibleFrame, gap: controller.arranger.gap, mins: [:]).frames[refs[0]])
        var dockedAt: Rect?
        let atTile = await waitUntil(timeout: .seconds(3)) {
            dockedAt = try? await listedFrame(fixture, 0)
            return dockedAt.map { near($0, tile) } ?? false
        }
        try #require(atTile, "window 0 never reached its tile \(tile): \(String(describing: dockedAt))")
        let dockedFrame = try #require(dockedAt)
        // Paused, so Transom does not put the floater back itself before the quit.
        await controller.dispatch(.togglePause, focused: nil)
        let floating = try #require(try await listedFrame(fixture, 1))
        let park = display.parkedFrame(size: floating.size, among: displays)
        _ = try await fixture.send("move 1 \(Int(park.x)) \(Int(park.y))")
        let seen = await waitUntil(timeout: .seconds(3)) {
            controller.arranger.windows[refs[1].identity].map { Recovery.isStranded($0.frame, displays: displays) } ?? false
        }
        try #require(seen, "Transom never saw window 1 at the park rect \(park)")

        let restored = controller.restoreForTermination(limit: .seconds(2))
        arrange = nil  // Transom exits after the restore: nothing may react to the move
        #expect(restored == 1)
        let back = try #require(try await listedFrame(fixture, 1))
        #expect(!Recovery.isStranded(back, displays: displays), "window 1 is still parked at \(back)")
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

/// How the bundled app is told to quit from outside. ⌘Q and menu Quit need a status menu, so they stay a guest probe.
enum OutsideQuit: String, CaseIterable, CustomTestStringConvertible {
    case sigterm, appleEvent
    var testDescription: String { rawValue }
}

/// SAFE-01 on the real bundled app (sigterm-quit-hang): each way of asking it to quit from outside restores a stranded
/// window, records the clean exit and ends the process. Run with scripts/vm-quit-check.sh, which stages the app. VM only:
/// it signals the app and replaces Application Support/Transom for the run.
@Suite(.serialized, .enabled(if: IntegrationEnv.trusted && IntegrationEnv.inVM && IntegrationEnv.bundledApp != nil, "needs the VM and a staged Transom Debug.app"))
@MainActor struct OutsideQuitIntegrationTests {
    @Test(.timeLimit(.minutes(1)), arguments: OutsideQuit.allCases)
    func aQuitFromOutsideRestoresRecordsTheCleanExitAndExits(_ route: OutsideQuit) async throws {
        let manager = FileManager.default
        let support = manager.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/Transom")
        let kept = support.appendingPathExtension("before-quit-test")
        if manager.fileExists(atPath: support.path) { try manager.moveItem(at: support, to: kept) }
        defer {
            try? manager.removeItem(at: support)
            try? manager.moveItem(at: kept, to: support)
        }
        try #require(try appPID() == nil, "Transom Debug is already running")
        let fixture = try await FixtureProcess.launch(["standard"])
        defer { fixture.terminate() }

        let app = try #require(IntegrationEnv.bundledApp).path
        try run("/usr/bin/open", [app])
        defer {  // `open` registered this copy; a later URL or `open` should not find it
            try? run("/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister", ["-u", app])
        }
        let layout = support.appendingPathComponent("layout.json")
        let launched = await waitUntil(timeout: .seconds(10)) { manager.fileExists(atPath: layout.path) }
        try #require(launched, "the app wrote no layout.json: is it trusted in this VM?")
        let pid = try #require(try appPID())
        defer { kill(pid, SIGKILL) }
        try await Task.sleep(for: .seconds(3))  // the first sweep tracks the fixture
        _ = try await fixture.send("move 0 5000 5000")
        try await Task.sleep(for: .seconds(2))  // the app sees the move
        let displays = Displays.current()
        let stranded = try #require(try await listedFrame(fixture, 0))
        try #require(Recovery.isStranded(stranded, displays: displays), "the move left the window on screen: \(stranded)")

        switch route {
        case .sigterm: kill(pid, SIGTERM)
        case .appleEvent: try run("/usr/bin/osascript", ["-e", "quit app id \"com.eightabyte.transom.debug\""], wait: false)
        }
        // Bounded by the 2 s restore limit, with room for a slow guest. The bug: alive for minutes.
        let exited = await waitUntil(timeout: .seconds(10)) { kill(pid, 0) != 0 }
        #expect(exited, "still running 10 s after \(route.rawValue)")
        let file = try JSONSerialization.jsonObject(with: Data(contentsOf: layout)) as? [String: Any]
        #expect((file?["session"] as? [String: Any])?["cleanExit"] as? Bool == true, "no clean exit recorded")
        let back = try #require(try await listedFrame(fixture, 0))
        #expect(!Recovery.isStranded(back, displays: displays), "the window is still stranded at \(back)")
    }

    private func run(_ tool: String, _ arguments: [String], wait: Bool = true) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: tool)
        process.arguments = arguments
        try process.run()
        if wait { process.waitUntilExit() }
    }

    private func appPID() throws -> Int32? {
        let process = Process()
        let output = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/pgrep")
        process.arguments = ["-x", "Transom Debug"]
        process.standardOutput = output
        try process.run()
        process.waitUntilExit()
        return Int32(String(decoding: output.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines))
    }
}

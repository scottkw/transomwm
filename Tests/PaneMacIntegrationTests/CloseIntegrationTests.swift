import PaneEngine
import PaneMac
import PaneModel
import Testing

/// WIN-09 / D-09 live: a real close is noticed fast, a freeze removes nothing, a quit removes everything.
/// Only the fixture this test launched is ever stopped, and it is always resumed before it is terminated.
@Suite(.serialized, .enabled(if: IntegrationEnv.trusted, "needs a process with the Accessibility grant"))
@MainActor struct CloseIntegrationTests {
    @Test(.timeLimit(.minutes(1)))
    func closeFreezeHideAndQuitAreDecidedByTwoSources() async throws {
        let fixture = try await FixtureProcess.launch(["standard", "standard"])
        defer { fixture.terminate() }
        let pid = fixture.pid
        let system = AXWindowSystem(appFilter: { candidate, _ in candidate == pid })
        let log = EventLog(system)
        await system.start()

        func info(_ id: UInt32) async -> WindowInfo? {
            await system.inventory().windows.first { $0.window.pid == pid && $0.window.windowID == id }
        }
        let kept = try #require(fixture.windows.first { $0.index == 0 }).id
        let closed = try #require(fixture.windows.first { $0.index == 1 }).id
        #expect(await waitUntil(timeout: .seconds(2)) {
            let both = (await info(kept), await info(closed))
            return both.0 != nil && both.1 != nil
        })

        // A real close: AX -25202 on the cached element and gone from the CG list.
        _ = try await fixture.send("close 1")
        let destroyed = await log.wait(.seconds(1)) {
            if case .windowDestroyed(let ref) = $0 { ref.pid == pid && ref.windowID == closed } else { false }
        }
        #expect(destroyed, "no windowDestroyed for the closed window within 1 s")
        #expect(await info(kept) != nil, "the other window was dropped")

        let reply = try await fixture.send("open standard")
        let opened = try #require(reply.compactMap(FixtureWindow.init(line:)).first).id
        #expect(await waitUntil(timeout: .seconds(2)) { await info(opened) != nil })

        // A freeze: every read times out, nothing is removed.
        fixture.stop()
        for _ in 0..<3 {
            Task { await system.refreshAll() }
            try await Task.sleep(for: .seconds(1))
        }
        #expect(await info(kept) != nil, "a freeze removed a window")
        #expect(await info(opened) != nil, "a freeze removed a window")
        fixture.resume()
        if await system.inventory().degradedPIDs.contains(pid) {
            #expect(await log.wait(.seconds(4)) { $0 == .appResponsiveness(pid: pid, degraded: false) })
        }

        // Hidden app: tracked as absent, then present again.
        _ = try await fixture.send("hide-app")
        #expect(await waitUntil(timeout: .seconds(2)) { await info(kept)?.state == .absent }, "hidden window not .absent")
        _ = try await fixture.send("unhide-app")
        #expect(await waitUntil(timeout: .seconds(2)) { await info(kept)?.state == .present }, "unhidden window not .present")

        // A quit: NSWorkspace says terminated and the CG list agrees.
        fixture.terminate()
        let gone = await waitUntil(timeout: .seconds(2)) {
            [kept, opened].allSatisfy { id in log.events.contains(.windowDestroyed(WindowRef(identity: WindowIdentity(windowID: id, pid: pid, bundleID: "unbundled:PaneFixtureApp")))) }
        }
        #expect(gone, "not every fixture window was destroyed within 2 s of the quit")
        #expect(await system.inventory().windows.allSatisfy { $0.window.pid != pid })
    }
}

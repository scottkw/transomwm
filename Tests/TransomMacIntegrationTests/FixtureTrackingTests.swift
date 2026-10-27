import TransomEngine
import TransomMac
import TransomModel
import Testing

@Suite(.serialized, .enabled(if: IntegrationEnv.trusted, "needs a process with the Accessibility grant"))
@MainActor struct FixtureTrackingTests {
    @Test(.timeLimit(.minutes(1)))
    func aFixtureWindowIsTrackedWithItsRealIDPidFrameAndState() async throws {
        let fixture = try await FixtureProcess.launch(["standard"])
        defer { fixture.terminate() }
        let printed = try #require(fixture.windows.first)
        let pid = fixture.pid

        let system = AXWindowSystem(appFilter: { candidate, _ in candidate == pid })
        await system.start()
        #expect(await system.inventory().initialRefreshComplete)
        // The window can reach AXWindows a moment after the fixture prints it.
        _ = await waitUntil(timeout: .seconds(5)) {
            if await system.inventory().windows.isEmpty { await system.refreshAll() }
            return await !system.inventory().windows.isEmpty
        }

        let windows = await system.inventory().windows
        #expect(windows.count == 1)
        let info = try #require(windows.first)
        #expect(info.window.windowID == printed.id)
        #expect(info.window.pid == pid)
        #expect(info.window.bundleID == "unbundled:TransomFixtureApp")
        #expect(info.state == .present)
        #expect(info.idSource == .axPrivate)
        #expect(abs(info.frame.x - printed.frame.x) <= 1)
        #expect(abs(info.frame.y - printed.frame.y) <= 1)
        #expect(abs(info.frame.width - printed.frame.width) <= 1)
        #expect(abs(info.frame.height - printed.frame.height) <= 1)
        #expect(await system.windowInfo(info.window) == info)
    }
}

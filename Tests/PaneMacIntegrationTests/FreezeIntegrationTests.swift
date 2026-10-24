import PaneEngine
import PaneMac
import PaneModel
import Testing

/// WIN-03 / ROADMAP SC4: one fixture app frozen with SIGSTOP while another keeps being tracked.
/// Only the fixture this test launched is ever stopped, and it is always resumed before it is terminated.
@Suite(.serialized, .enabled(if: IntegrationEnv.trusted, "needs a process with the Accessibility grant"))
@MainActor struct FreezeIntegrationTests {
    @Test(.timeLimit(.minutes(1)))
    func aStoppedAppNeitherStallsPaneNorDelaysAnotherApp() async throws {
        let frozen = try await FixtureProcess.launch(["standard"])
        defer {
            frozen.resume()
            frozen.terminate()
        }
        let other = try await FixtureProcess.launch(["standard"])
        defer { other.terminate() }
        let pids: Set<Int32> = [frozen.pid, other.pid]
        let system = AXWindowSystem(appFilter: { pid, _ in pids.contains(pid) })
        let log = EventLog(system)
        await system.start()

        let frozenID = try #require(frozen.windows.first).id
        let otherID = try #require(other.windows.first).id
        func tracked(_ pid: Int32, _ id: UInt32) async -> Bool {
            await system.inventory().windows.contains { $0.window.pid == pid && $0.window.windowID == id }
        }
        #expect(await waitUntil(timeout: .seconds(2)) { await tracked(frozen.pid, frozenID) })
        #expect(await waitUntil(timeout: .seconds(2)) { await tracked(other.pid, otherID) })

        frozen.stop()
        // What the 5 s sweep does, started now instead of up to 5 s later, and not awaited (like the sweep task).
        Task { await system.refreshAll() }
        let clock = ContinuousClock()
        let inventoryTime = await clock.measure { _ = await system.inventory() }
        #expect(inventoryTime < .milliseconds(50), "inventory() took \(inventoryTime) during a freeze")

        let reply = try await other.send("open standard")
        let opened = try #require(reply.compactMap(FixtureWindow.init(line:)).first)
        #expect(await waitUntil(timeout: .seconds(1)) { await tracked(other.pid, opened.id) },
                "the other app's new window was not tracked within 1 s")

        let frozenPID = frozen.pid
        let degraded = await log.wait(.seconds(5)) { $0 == .appResponsiveness(pid: frozenPID, degraded: true) }
        #expect(degraded, "the stopped app was not reported degraded within 5 s")
        #expect(await system.inventory().degradedPIDs == [frozenPID])
        #expect(await tracked(frozenPID, frozenID), "a timeout removed the stopped app's window")
        // A degraded app is never awaited: a full sweep costs only the responsive app.
        let sweepTime = await clock.measure { await system.refreshAll() }
        #expect(sweepTime < .milliseconds(500), "refreshAll() took \(sweepTime) with a degraded app")
        let duringFreeze = await clock.measure { _ = await system.inventory() }
        #expect(duringFreeze < .milliseconds(50))

        frozen.resume()
        let recovered = await log.wait(.seconds(4)) { $0 == .appResponsiveness(pid: frozenPID, degraded: false) }
        #expect(recovered, "the resumed app was not reported recovered within 4 s")
        #expect(await system.inventory().degradedPIDs.isEmpty)
        #expect(await tracked(frozenPID, frozenID))
    }
}

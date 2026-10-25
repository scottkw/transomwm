import PaneEngine
import PaneMac
import PaneModel
import Testing

/// SAFE-05 / D-15 live: with window-ID lookup forced off, the fixture's windows are identified by matching their
/// frames to the CG window list, identical windows get distinct identities, and closes still need two sources.
@Suite(.serialized, .enabled(if: IntegrationEnv.trusted, "needs a process with the Accessibility grant"))
@MainActor struct FallbackIntegrationTests {
    @Test(.timeLimit(.minutes(1)))
    func everyWindowIsTrackedByItsCGWindowWithoutTheLookup() async throws {
        let fixture = try await FixtureProcess.launch(["standard", "standard", "tabs:2"])
        defer { fixture.terminate() }
        let pid = fixture.pid
        let system = AXWindowSystem(appFilter: { candidate, _ in candidate == pid }, forceWindowIDFallback: true)
        await system.start()

        func tracked() async -> [WindowInfo] { await system.inventory().windows.filter { $0.window.pid == pid } }
        #expect(await waitUntil(timeout: .seconds(2)) { await tracked().count == 3 }, "expected 2 windows and 1 tab group")
        let windows = await tracked()
        for standard in fixture.windows where standard.kind == "standard" {
            let info = windows.first { $0.window.windowID == standard.id }
            #expect(info?.idSource == .cgFrameMatch, "window \(standard.index) was not matched to its CG window")
        }
        let tabIDs = Set(fixture.windows.filter { $0.kind == "tabs:2" }.map(\.id))
        let onscreenTab = try #require(CGWindowList.snapshot().first { tabIDs.contains($0.windowID) && $0.onScreen }?.windowID)
        let group = try #require(windows.first { $0.tabCount == 2 }, "the tab group was not tracked as one window")
        #expect(group.idSource == .cgFrameMatch)
        #expect(group.visibleMemberID == onscreenTab)
        #expect(!windows.contains { $0.window.identity.isSyntheticWindowID })
    }

    @Test(.timeLimit(.minutes(1)))
    func identicalWindowsGetDistinctIdentitiesAndCloseOneAtATime() async throws {
        let fixture = try await FixtureProcess.launch(["standard", "standard"])
        defer { fixture.terminate() }
        let pid = fixture.pid
        let first = try #require(fixture.windows.first { $0.index == 0 })
        _ = try await fixture.send("move 1 \(Int(first.frame.x)) \(Int(first.frame.y))")
        // Same title too, so even readable CG names (Screen Recording) cannot tell them apart: synthetic IDs.
        _ = try await fixture.send("title 0 Twin")
        _ = try await fixture.send("title 1 Twin")
        let fixtureIDs = Set(fixture.windows.map(\.id))
        let stacked = await waitUntil(timeout: .seconds(2)) {
            Set(CGWindowList.snapshot().filter { fixtureIDs.contains($0.windowID) }.map(\.bounds)).count == 1
        }
        #expect(stacked, "the two fixture windows never reached identical CG bounds")

        let system = AXWindowSystem(appFilter: { candidate, _ in candidate == pid }, forceWindowIDFallback: true)
        let log = EventLog(system)
        await system.start()
        func tracked() async -> [WindowInfo] { await system.inventory().windows.filter { $0.window.pid == pid } }
        #expect(await waitUntil(timeout: .seconds(2)) { await tracked().count == 2 }, "two identical windows were not tracked as two")
        let windows = await tracked()
        #expect(Set(windows.map(\.window.identity)).count == 2)
        for info in windows {
            #expect(info.idSource == .synthetic)
            #expect(info.window.windowID >= WindowIdentity.syntheticIDBase)
            #expect(!fixtureIDs.contains(info.window.windowID))
        }

        func destroyed() -> [PaneModel.WindowRef] {
            log.events.compactMap { if case .windowDestroyed(let ref) = $0, ref.pid == pid { ref } else { nil } }
        }
        _ = try await fixture.send("close 1")
        #expect(await waitUntil(timeout: .seconds(2)) { !destroyed().isEmpty }, "no windowDestroyed within 2 s of the close")
        try await Task.sleep(for: .milliseconds(750))
        #expect(destroyed().count == 1, "closing one of two identical windows destroyed \(destroyed().count)")
        let remaining = await tracked()
        #expect(remaining.count == 1)
        #expect(remaining.first.map { $0.window.identity } != destroyed().first?.identity)
    }
}

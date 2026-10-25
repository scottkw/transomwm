import ApplicationServices
import PaneEngine
@testable import PaneMac
import PanePrivate
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
        let onscreenTab = try #require(CGWindowList.snapshot()?.first { tabIDs.contains($0.windowID) && $0.onScreen }?.windowID)
        let group = try #require(windows.first { $0.tabCount == 2 }, "the tab group was not tracked as one window")
        #expect(group.idSource == .cgFrameMatch)
        #expect(group.visibleMemberID == onscreenTab)
        #expect(!windows.contains { $0.window.identity.isSyntheticWindowID })
    }

    @Test(.timeLimit(.minutes(1)))
    func identicalWindowsGetDistinctIdentitiesAndCloseOneAtATime() async throws {
        let fixture = try await stackedTwins()
        defer { fixture.terminate() }
        let pid = fixture.pid
        let fixtureIDs = Set(fixture.windows.map(\.id))

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

    /// WR-04: an element cached under a fallback ID is looked up again while the lookup works. It is reported under
    /// its real ID, with the fallback ID as `replacesWindowID`, and the element map holds only the real ID.
    @Test(.timeLimit(.minutes(1)))
    func anElementCachedUnderAFallbackIDIsReportedUnderItsRealIDOnceTheLookupWorks() async throws {
        try #require(Capabilities.isAvailable(.axWindowID), "needs the private lookup")
        let fixture = try await FixtureProcess.launch(["standard"])
        defer { fixture.terminate() }
        let realID = try #require(fixture.windows.first).id
        let app = AXUIElementCreateApplication(fixture.pid)
        var value: CFTypeRef?
        #expect(AXUIElementCopyAttributeValue(app, kAXWindowsAttribute as CFString, &value) == .success)
        let element = try #require((value as? [AXUIElement])?.first)
        let synthetic = WindowIdentity.syntheticIDBase | 1
        let read = try #require(AXSnapshotReader.observeApp(
            app, pid: fixture.pid, bundleID: "test.fallback", hidden: false,
            cache: [synthetic: CachedWindow(element: element, source: .synthetic)]
        ))
        #expect(read.observation.windows.map(\.windowID) == [realID])
        #expect(read.observation.windows.map(\.idSource) == [.axPrivate])
        #expect(read.observation.windows.map(\.replacesWindowID) == [synthetic])
        #expect(read.elements.map { Array($0.keys) } == [realID])
    }

    /// SAFE-05, WIN-02 (lead decision 2026-10-25): two identical windows tracked under synthetic IDs are re-keyed to
    /// their real CGWindowIDs once the lookup works, as two windowRekeyed and never a destroy and create pair.
    @Test(.timeLimit(.minutes(1)))
    func syntheticIDsAreRekeyedToTheRealIDsOnceTheLookupWorks() async throws {
        try #require(Capabilities.isAvailable(.axWindowID), "needs the private lookup")
        let fixture = try await stackedTwins()
        defer { fixture.terminate() }
        let pid = fixture.pid
        let fixtureIDs = Set(fixture.windows.map(\.id))
        let system = AXWindowSystem(appFilter: { candidate, _ in candidate == pid }, forceWindowIDFallback: true)
        let log = EventLog(system)
        await system.start()
        func tracked() async -> [WindowInfo] { await system.inventory().windows.filter { $0.window.pid == pid } }
        #expect(await waitUntil(timeout: .seconds(2)) { await tracked().filter { $0.idSource == .synthetic }.count == 2 })
        // The log reads the event stream asynchronously: wait for both creates before marking the flip.
        #expect(await waitUntil(timeout: .seconds(2)) {
            log.events.filter { if case .windowCreated(let info) = $0 { info.window.pid == pid } else { false } }.count == 2
        })

        let flip = log.events.count
        system.setForceWindowIDFallback(false)
        await system.refreshAll()
        let rekeyed = await waitUntil(timeout: .seconds(2)) {
            let windows = await tracked()
            return Set(windows.map(\.window.windowID)) == fixtureIDs && windows.count == 2 && windows.allSatisfy { $0.idSource == .axPrivate }
        }
        let now = await tracked().map { ($0.window.windowID, $0.idSource) }
        #expect(rekeyed, "tracked \(now), fixture \(fixtureIDs)")
        // Room for a late create (after the settle delay) or destroy to show up.
        try await Task.sleep(for: .milliseconds(750))
        let since = log.events.dropFirst(flip)
        let rekeys = since.filter { if case .windowRekeyed(let from, _) = $0 { from.pid == pid } else { false } }
        let lifecycle = since.filter {
            switch $0 {
            case .windowCreated(let info): info.window.pid == pid
            case .windowDestroyed(let ref): ref.pid == pid
            default: false
            }
        }
        #expect(rekeys.count == 2)
        #expect(lifecycle.isEmpty, "\(lifecycle)")
    }
}

/// Two fixture windows with identical frames and titles, so even readable CG names cannot tell them apart.
@MainActor private func stackedTwins() async throws -> FixtureProcess {
    let fixture = try await FixtureProcess.launch(["standard", "standard"])
    let first = try #require(fixture.windows.first { $0.index == 0 })
    _ = try await fixture.send("move 1 \(Int(first.frame.x)) \(Int(first.frame.y))")
    _ = try await fixture.send("title 0 Twin")
    _ = try await fixture.send("title 1 Twin")
    let fixtureIDs = Set(fixture.windows.map(\.id))
    let stacked = await waitUntil(timeout: .seconds(2)) {
        Set((CGWindowList.snapshot() ?? []).filter { fixtureIDs.contains($0.windowID) }.map(\.bounds)).count == 1
    }
    #expect(stacked, "the two fixture windows never reached identical CG bounds")
    return fixture
}

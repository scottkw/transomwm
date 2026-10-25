import PaneEngine
import PaneMac
import PaneModel
import Testing

/// WIN-06 / D-08 live: the fixture's three-tab window is one tracked window that follows its visible tab, and a
/// tab switch or a closed tab never looks like a window closing and another opening.
@Suite(.serialized, .enabled(if: IntegrationEnv.trusted, "needs a process with the Accessibility grant"))
@MainActor struct TabsIntegrationTests {
    @Test(.timeLimit(.minutes(1)))
    func aTabbedWindowIsOneWindowThatFollowsItsVisibleTab() async throws {
        let fixture = try await FixtureProcess.launch(["tabs:3"])
        defer { fixture.terminate() }
        let pid = fixture.pid
        let system = AXWindowSystem(appFilter: { candidate, _ in candidate == pid })
        let log = EventLog(system)
        await system.start()

        func tracked() async -> [WindowInfo] {
            await system.inventory().windows.filter { $0.window.pid == pid }
        }
        func churn(since mark: Int) -> [WindowEvent] {
            log.events.dropFirst(mark).filter {
                switch $0 {
                case .windowCreated(let info): info.window.pid == pid
                case .windowDestroyed(let ref): ref.pid == pid
                default: false
                }
            }
        }
        let tabIDs = Set(fixture.windows.map(\.id))
        #expect(tabIDs.count == 3)
        #expect(await waitUntil(timeout: .seconds(2)) { await tracked().first?.tabCount == 3 }, "no tracked window with 3 tabs")
        let windows = await tracked()
        #expect(windows.count == 1, "three tabs were tracked as \(windows.count) windows")
        let group = try #require(windows.first)
        let shown = try #require(group.visibleMemberID)
        #expect(tabIDs.contains(shown))

        // Switch to a tab that is not showing: the same window follows it.
        let target = try #require(fixture.windows.first { $0.id != shown })
        var mark = log.events.count
        _ = try await fixture.send("select-tab \(target.index)")
        let switched = await waitUntil(timeout: .seconds(1)) { await tracked().first?.visibleMemberID == target.id }
        #expect(switched, "visibleMemberID did not follow the selected tab within 1 s")
        #expect(await tracked().map(\.window.identity) == [group.window.identity])
        #expect(churn(since: mark).isEmpty, "a tab switch created or destroyed a window")

        // Close the visible tab: the group lives on with two tabs.
        mark = log.events.count
        _ = try await fixture.send("close \(target.index)")
        let shrunk = await waitUntil(timeout: .seconds(1)) { await tracked().first?.tabCount == 2 }
        #expect(shrunk, "tabCount did not drop to 2 within 1 s of closing the visible tab")
        #expect(await tracked().map(\.window.identity) == [group.window.identity])
        #expect(churn(since: mark).isEmpty, "closing one tab created or destroyed a window")
    }
}

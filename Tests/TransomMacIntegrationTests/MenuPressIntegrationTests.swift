@testable import TransomMac
import Testing

/// Pattern 14 live: the AX press of a ⌘N menu item, against the fixture's File ▸ New Window only (never Finder).
@Suite(.serialized, .enabled(if: IntegrationEnv.trusted, "needs a process with the Accessibility grant"))
@MainActor struct MenuPressIntegrationTests {
    @Test(.timeLimit(.minutes(1)))
    func pressingTheFixturesCommandNItemOpensANewWindow() async throws {
        let fixture = try await FixtureProcess.launch(["standard"])
        defer { fixture.terminate() }
        let system = AXWindowSystem(appFilter: { pid, _ in pid == fixture.pid })
        await system.start()
        let window = try #require(fixture.windows.first)
        let tracked = await waitUntil(timeout: .seconds(2)) {
            await system.inventory().windows.contains { $0.window.pid == fixture.pid && $0.window.windowID == window.id }
        }
        #expect(tracked, "the fixture's window was never tracked")

        #expect(await system.pressNewWindowItem(pid: fixture.pid), "no ⌘N menu item was pressed")
        let opened = await waitUntil(timeout: .seconds(2)) { fixture.allLines().contains { $0.hasPrefix("window index=1 ") } }
        #expect(opened, "no new window within 2 s: \(fixture.allLines())")
        #expect(await system.pressNewWindowItem(pid: -1) == false, "an untracked pid was pressed")
    }
}

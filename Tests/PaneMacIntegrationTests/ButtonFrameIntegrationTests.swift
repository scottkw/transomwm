import PaneEngine
@testable import PaneMac
import PaneModel
import Testing

/// RESEARCH Pattern 5 live: the batched AX read gives a fixture window's green button, stored as an offset from the
/// window's top-left, inside its title bar.
@Suite(.serialized, .enabled(if: IntegrationEnv.trusted, "needs a process with the Accessibility grant"))
@MainActor struct ButtonFrameIntegrationTests {
    @Test(.timeLimit(.minutes(1)))
    func aStandardWindowsGreenButtonLiesInItsTitleBar() async throws {
        let fixture = try await FixtureProcess.launch(["standard"])
        defer { fixture.terminate() }
        let fixturePID = fixture.pid
        let id = try #require(fixture.windows.first).id
        let system = AXWindowSystem(appFilter: { pid, _ in pid == fixturePID })
        await system.start()
        func find() async -> WindowInfo? {
            await system.inventory().windows.first { $0.window.pid == fixturePID && $0.window.windowID == id }
        }
        _ = await waitUntil(timeout: .seconds(3)) { await find()?.greenButton != nil }
        let info = try #require(await find(), "window \(id) never tracked")
        let offset = try #require(info.greenButton, "no green button read for \(info.window)")
        let button = Rect(x: info.frame.x + offset.x, y: info.frame.y + offset.y, width: offset.width, height: offset.height)
        #expect(offset.width > 0 && offset.height > 0)
        #expect(button.minX >= info.frame.minX && button.maxX <= info.frame.maxX, "button \(button) outside \(info.frame)")
        #expect(button.minY >= info.frame.minY && button.maxY <= info.frame.minY + 32, "button \(button) not in the title bar of \(info.frame)")
    }
}

import PaneEngine
import PaneMac
import PaneModel
import Testing

private func near(_ a: Rect, _ b: Rect) -> Bool {
    [abs(a.x - b.x), abs(a.y - b.y), abs(a.width - b.width), abs(a.height - b.height)].allSatisfy { $0 <= 1 }
}

/// D-01 live, on a fixture window this test launched: `focusedWindow(of:)` finds it, and Nudge's two presses
/// move and shrink it, then put it back.
@Suite(.serialized, .enabled(if: IntegrationEnv.trusted, "needs a process with the Accessibility grant"))
@MainActor struct NudgeIntegrationTests {
    @Test(.timeLimit(.minutes(1)))
    func theFocusedFixtureWindowIsNudgedAndRestored() async throws {
        let fixture = try await FixtureProcess.launch(["standard"])
        defer { fixture.terminate() }
        let pid = fixture.pid
        let id = try #require(fixture.windows.first).id
        let system = AXWindowSystem(appFilter: { candidate, _ in candidate == pid })
        await system.start()
        let found = await waitUntil(timeout: .seconds(2)) { system.focusedWindow(of: pid) != nil }
        let focused = try #require(found ? system.focusedWindow(of: pid) : nil, "no focused window for the fixture")
        #expect(focused.window.windowID == id)
        let original = focused.frame

        var planner = NudgePlanner()
        let nudged = planner.target(for: focused.window.identity, current: original)
        await system.perform([.setFrame(focused.window, nudged)])
        #expect(await waitUntil(timeout: .seconds(1)) { await system.windowInfo(focused.window).map { near($0.frame, nudged) } == true })

        let current = try #require(await system.windowInfo(focused.window)).frame
        await system.perform([.setFrame(focused.window, planner.target(for: focused.window.identity, current: current))])
        #expect(await waitUntil(timeout: .seconds(1)) { await system.windowInfo(focused.window).map { near($0.frame, original) } == true })
        _ = try await fixture.send("list")
        let reported = try #require(fixture.windows.first { $0.id == id }).frame
        #expect(near(reported, original), "the fixture ends at \(reported)")
    }
}

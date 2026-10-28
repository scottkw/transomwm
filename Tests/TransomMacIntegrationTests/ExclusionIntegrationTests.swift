import TransomEngine
import TransomMac
import TransomModel
import Testing

private func near(_ a: Rect, _ b: Rect) -> Bool {
    [abs(a.x - b.x), abs(a.y - b.y), abs(a.width - b.width), abs(a.height - b.height)].allSatisfy { $0 <= 1 }
}

/// WIN-08 / ROADMAP SC3 live: a setFrame for an excluded fixture app never reaches it; un-excluded, it does.
/// Frames are written only to the fixture window this test launched.
@Suite(.serialized, .enabled(if: IntegrationEnv.trusted, "needs a process with the Accessibility grant"))
@MainActor struct ExclusionIntegrationTests {
    @Test(.timeLimit(.minutes(1)))
    func anExcludedAppIsNeverMovedAndIsMovedOnceUnexcluded() async throws {
        let fixture = try await FixtureProcess.launch(["standard"])
        defer { fixture.terminate() }
        let pid = fixture.pid
        let id = try #require(fixture.windows.first).id
        let original = try #require(fixture.windows.first).frame
        let system = AXWindowSystem(appFilter: { candidate, _ in candidate == pid })
        let log = EventLog(system)
        await system.start()
        func find() async -> WindowInfo? {
            await system.inventory().windows.first { $0.window.pid == pid && $0.window.windowID == id }
        }
        _ = await waitUntil(timeout: .seconds(2)) { await find() != nil }
        let ref = try #require(await find(), "fixture window never tracked").window
        let target = Rect(x: 300, y: 300, width: 400, height: 300)

        // The system takes any key; only the store validates what the user types.
        system.setExcludedBundleIDs(["unbundled:TransomFixtureApp"])
        #expect(try #require(await find()).isExcluded)
        await system.perform([.setFrame(ref, target)])
        let written = await log.wait(.seconds(1)) { if case .frameApplied(ref, _, _) = $0 { true } else { false } }
        #expect(!written, "an excluded app's window was written")
        _ = try await fixture.send("list")
        let reported = try #require(fixture.windows.first { $0.id == id }).frame
        #expect(near(reported, original), "the excluded fixture moved to \(reported)")

        system.setExcludedBundleIDs([])
        #expect(try #require(await find()).isExcluded == false)
        await system.perform([.setFrame(ref, target)])
        // None was applied while excluded, so any frameApplied now comes from this setFrame.
        #expect(await log.wait(.seconds(1)) { if case .frameApplied(ref, _, _) = $0 { true } else { false } }, "no frameApplied within 1 s once un-excluded")
    }
}

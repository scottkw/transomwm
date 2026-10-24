import PaneEngine
import PaneMac
import PaneModel
import Testing

@Suite(.serialized, .enabled(if: IntegrationEnv.trusted, "needs a process with the Accessibility grant"))
@MainActor struct ClassificationIntegrationTests {
    @Test(.timeLimit(.minutes(1)))
    func fixtureWindowsArriveClassified() async throws {
        let fixture = try await FixtureProcess.launch(["standard", "nofullscreen", "borderless-floating", "utility-panel", "sheet"])
        defer { fixture.terminate() }
        func id(_ kind: String) throws -> UInt32 { try #require(fixture.windows.first { $0.kind == kind }).id }
        let expected: [UInt32: WindowKind] = [
            try id("standard"): .dockable,
            try id("sheet"): .dockable,
            try id("nofullscreen"): .neverDock(.noFullscreenButton),
            try id("borderless-floating"): .neverDock(.floatingLevel),
        ]
        let sheetChild = try id("sheet-child")
        let panel = try id("utility-panel")

        let pid = fixture.pid
        let system = AXWindowSystem(appFilter: { candidate, _ in candidate == pid })
        await system.start()
        // Windows can reach AXWindows a moment after the fixture prints them; late ones settle for 250 ms.
        _ = await waitUntil(timeout: .seconds(10)) {
            let ids = Set(await system.inventory().windows.map(\.window.windowID))
            if !Set(expected.keys).isSubset(of: ids) { await system.refreshAll() }
            return Set(expected.keys).isSubset(of: ids)
        }

        let windows = await system.inventory().windows
        let kinds = Dictionary(windows.map { ($0.window.windowID, $0.kind) }, uniquingKeysWith: { first, _ in first })
        for (windowID, kind) in expected {
            #expect(kinds[windowID] == kind, "window \(windowID)")
        }
        // Sheets are not in AXWindows, so the sheet child is never a tracked window.
        #expect(kinds[sheetChild] == nil)
        // An inactive app's floating utility panel is absent from AXWindows; if it shows up it must not dock.
        if let panelKind = kinds[panel] {
            #expect(panelKind != .dockable)
        }
        // Every tracked window is one of the fixture's AXWindow-role windows (no desktop or scroll areas).
        let known = Set(fixture.windows.map(\.id)).subtracting([sheetChild])
        #expect(windows.allSatisfy { known.contains($0.window.windowID) })
        print("utility-panel: \(kinds[panel].map { "tracked as \($0)" } ?? "absent from the inventory")")
    }
}

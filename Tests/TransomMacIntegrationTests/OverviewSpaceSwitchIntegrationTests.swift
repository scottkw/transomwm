import AppKit
import Foundation
import TransomEngine
@testable import TransomMac
import TransomModel
import TransomPrivate
import Testing

/// D-04 / D-16 live: picking another Space in the overview's strip closes it and macOS switches to that Space within
/// 1 s. VM only: it posts Mission Control chords and switches Spaces. Every test starts and ends on the first desktop.
@Suite(.serialized, .enabled(if: IntegrationEnv.trusted, "needs a process with the Accessibility grant"))
@MainActor struct OverviewSpaceSwitchIntegrationTests {
    /// Connects to the window server first (see ZoomSettleIntegrationTests).
    init() { _ = NSApplication.shared }

    /// The main display, its first desktop and the next one; the guest needs at least two desktops.
    private func desktops() throws -> (display: String, first: UInt64, second: UInt64) {
        let main = try #require(Displays.current().first?.uuid)
        let list = try #require(SpacesProvider.snapshot()?.displays.first { $0.displayUUID == main }, "Spaces lookup unavailable")
        let ids = list.spaces.filter { $0.kind == .desktop }.map(\.id)
        try #require(ids.count >= 2, "the guest needs two desktops, has \(ids)")
        return (main, ids[0], ids[1])
    }

    /// Back to the first desktop with the switcher (the default ⌃← chords with fn), waiting until it shows.
    private func returnToFirst() async throws {
        let (display, first, _) = try desktops()
        guard SkyLightSpaces.currentSpace(displayUUID: display) != first else { return }
        _ = await SpaceSwitcher(spaces: { SpacesProvider.snapshot() }).switchTo(space: first, on: display)
        let back = await waitUntil(timeout: .seconds(3)) { SkyLightSpaces.currentSpace(displayUUID: display) == first }
        try #require(back, "could not return to the first desktop")
    }

    @Test(.timeLimit(.minutes(1)))
    func pickingAnotherSpacesThumbnailSwitchesThereAndCloses() async throws {
        try await returnToFirst()
        let (display, _, second) = try desktops()
        let fixture = try await FixtureProcess.launch(["standard"])
        defer { fixture.terminate() }
        let fixturePID = fixture.pid
        let system = AXWindowSystem(appFilter: { pid, _ in pid == fixturePID })
        await system.start()
        let arrange = ArrangeController(system: system, zoomEnabled: true)
        defer { withExtendedLifetime(arrange) {} }
        await arrange.start()

        await arrange.dispatch(.camera(.overview))
        let overview = try #require(arrange.overviewController)
        try #require(await waitUntil(timeout: .seconds(2)) { !overview.openPanels.isEmpty }, "the overview never opened")
        let started = ContinuousClock.now
        overview.pick(.thumbnail(space: second))
        #expect(!overview.isOpen, "the pick did not close the overview")
        let switched = await waitUntil(timeout: .milliseconds(1500)) { SkyLightSpaces.currentSpace(displayUUID: display) == second }
        let ms = (ContinuousClock.now - started) / .milliseconds(1)
        print("OverviewSpaceSwitchIntegrationTests: thumbnail pick switched=\(switched) after \(Int(ms)) ms")
        #expect(switched, "the main display never showed Space \(second)")
        try await returnToFirst()
    }
}

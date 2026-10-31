import AppKit
import Foundation
import TransomEngine
@testable import TransomMac
import TransomModel
import TransomPrivate
import Testing

/// D-04 / D-16 live: picking another Space's thumbnail or mini tile in the overview's strip closes it, macOS switches to
/// that Space within 1 s, and a mini tile's window gets focus. VM only: it posts Mission Control chords and switches
/// Spaces. Every test starts and ends on the first desktop.
@Suite(
    .serialized, .enabled(if: IntegrationEnv.trusted, "needs a process with the Accessibility grant"),
    .enabled(if: IntegrationEnv.inVM, "VM only: posts Mission Control chords and switches Spaces"))
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

    /// Modifier keys the HID state reports down; a posted chord must leave none (nobody types in the VM run).
    private func heldModifiers() -> [CGKeyCode] { SpaceSwitcher.modifierKeys.filter { CGEventSource.keyState(.hidSystemState, key: $0) } }

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
        var refused: String?
        overview.onSwitchFailed = { refused = $0 }
        overview.pick(.thumbnail(space: second))
        #expect(!overview.isOpen, "the pick did not close the overview")
        let switched = await waitUntil(timeout: .milliseconds(1500)) { SkyLightSpaces.currentSpace(displayUUID: display) == second }
        let ms = (ContinuousClock.now - started) / .milliseconds(1)
        print("OverviewSpaceSwitchIntegrationTests: thumbnail pick switched=\(switched) after \(Int(ms)) ms")
        #expect(switched, "the main display never showed Space \(second)")
        #expect(refused == nil, "the switcher gave up after 1 s: \(refused ?? "")")
        #expect(heldModifiers().isEmpty, "a posted chord left modifier keys down: \(heldModifiers())")
        try await returnToFirst()
    }

    @Test(.timeLimit(.minutes(1)))
    func pickingAMiniTileOnAnotherSpaceSwitchesThereAndFocusesItsWindow() async throws {
        try await returnToFirst()
        let (display, _, second) = try desktops()
        // The window to pick opens on the second desktop, tracked from there; the test then comes back.
        _ = await SpaceSwitcher(spaces: { SpacesProvider.snapshot() }).switchTo(space: second, on: display)
        try #require(await waitUntil(timeout: .seconds(3)) { SkyLightSpaces.currentSpace(displayUUID: display) == second })
        let fixture = try await FixtureProcess.launch(["standard"])
        defer { fixture.terminate() }
        let fixturePID = fixture.pid
        let system = AXWindowSystem(appFilter: { pid, _ in pid == fixturePID })
        await system.start()
        let arrange = ArrangeController(system: system, zoomEnabled: true)
        defer { withExtendedLifetime(arrange) {} }
        await arrange.start()
        let id = try #require(fixture.windows.first?.id)
        let tracked = await waitUntil(timeout: .seconds(3)) { arrange.arranger.windows.values.contains { $0.window.windowID == id } }
        let window = try #require(tracked ? arrange.arranger.windows.values.first { $0.window.windowID == id }?.window : nil, "never tracked")
        try await returnToFirst()
        // Another app frontmost on the first desktop, so the focus is the pick's doing.
        let other = try await FixtureProcess.launch(["standard"])
        defer { other.terminate() }
        print("OverviewSpaceSwitchIntegrationTests: before the pick the fixture answers \((try? await fixture.send("frontmost")) ?? [])")

        await arrange.dispatch(.camera(.overview))
        let overview = try #require(arrange.overviewController)
        try #require(await waitUntil(timeout: .seconds(2)) { !overview.openPanels.isEmpty }, "the overview never opened")
        var refused: String?
        overview.onSwitchFailed = { refused = $0 }
        overview.pick(.miniTile(window, space: second))
        #expect(!overview.isOpen, "the pick did not close the overview")
        let switched = await waitUntil(timeout: .milliseconds(1500)) { SkyLightSpaces.currentSpace(displayUUID: display) == second }
        #expect(switched, "the main display never showed Space \(second)")
        #expect(refused == nil, "the switcher gave up after 1 s: \(refused ?? "")")
        #expect(heldModifiers().isEmpty, "a posted chord left modifier keys down: \(heldModifiers())")
        var reply: [String] = []
        let focused = await waitUntil(timeout: .seconds(2)) {
            reply = (try? await fixture.send("frontmost")) ?? []
            return reply.contains("frontmost index=0")
        }
        #expect(focused, "the picked window is not focused: \(reply)")
        // D-03: 1 s after the change settles, the visit's windows are captured into the cache (Screen Recording only).
        if SnapshotCapture.isGranted() {
            let cached = await waitUntil(timeout: .seconds(4)) { arrange.zoomController?.cachedSnapshot(id) != nil }
            #expect(cached, "the visit to Space \(second) did not capture window \(id)")
        } else {
            print("OverviewSpaceSwitchIntegrationTests: no Screen Recording grant, visit capture not checked")
        }
        try await returnToFirst()
    }
}

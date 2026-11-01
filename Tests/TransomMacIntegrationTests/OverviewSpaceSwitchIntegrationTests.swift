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

    /// VM UAT B1 (2026-10-31): with windows already on the second desktop and Transom started on the first, the first
    /// visit's capture 1 s after arrival found none of them, so the strip kept app icons for that Space. AX lists a
    /// Space's windows only while it shows, so nothing was tracked there yet when the capture ran.
    @Test(.timeLimit(.minutes(1)))
    func theFirstVisitToASpaceNotYetReadCapturesItsWindows() async throws {
        try #require(SnapshotCapture.isGranted(), "needs Screen Recording (the VM's SSH session has it)")
        try await returnToFirst()
        let (display, _, second) = try desktops()
        _ = await SpaceSwitcher(spaces: { SpacesProvider.snapshot() }).switchTo(space: second, on: display)
        try #require(await waitUntil(timeout: .seconds(3)) { SkyLightSpaces.currentSpace(displayUUID: display) == second })
        let fixture = try await FixtureProcess.launch(["standard", "standard"])
        defer { fixture.terminate() }
        let ids = fixture.windows.map(\.id)
        try #require(ids.count == 2)
        try await returnToFirst()
        let fixturePID = fixture.pid
        let system = AXWindowSystem(appFilter: { pid, _ in pid == fixturePID })
        await system.start()
        let arrange = ArrangeController(system: system, zoomEnabled: true)
        defer { withExtendedLifetime(arrange) {} }
        await arrange.start()
        let tracked = { arrange.arranger.windows.values.filter { ids.contains($0.window.windowID) }.count }
        print("OverviewSpaceSwitchIntegrationTests: before the visit \(tracked()) of 2 windows tracked")

        _ = await SpaceSwitcher(spaces: { SpacesProvider.snapshot() }).switchTo(space: second, on: display)
        try #require(await waitUntil(timeout: .seconds(3)) { SkyLightSpaces.currentSpace(displayUUID: display) == second })
        let arrived = ContinuousClock.now
        var trackedAfter: Duration?
        // The capture runs 1 s after the change, with up to 2 s for its snapshots.
        let cached = await waitUntil(timeout: .seconds(3)) {
            if trackedAfter == nil, tracked() == 2 { trackedAfter = ContinuousClock.now - arrived }
            return ids.allSatisfy { arrange.zoomController?.cachedSnapshot($0) != nil }
        }
        print("OverviewSpaceSwitchIntegrationTests: tracked \(trackedAfter.map { "\($0 / .milliseconds(1)) ms" } ?? "never") after arrival, cached=\(cached)")
        #expect(cached, "the first visit to Space \(second) did not capture windows \(ids)")
        try await returnToFirst()
    }

    /// The window server's view: ordered in on the Space that shows now.
    private func isOnScreen(_ panel: NSPanel) -> Bool {
        let info = (CGWindowListCopyWindowInfo([.optionIncludingWindow], CGWindowID(panel.windowNumber)) as? [[String: Any]])?.first
        return info?[kCGWindowIsOnscreen as String] as? Bool ?? false
    }

    /// Host 2026-11-01 (macOS 27.2): after a screen lock, the overview's panel was left on the Space shown during the
    /// lock although it asks for every Space, so from another Space the overview never showed until a relaunch. The
    /// macOS 15 guest does not strand it on its own, so the test does: the panel left ordered in on the first desktop
    /// without .canJoinAllSpaces. The next open on the second desktop must be on screen and leave nothing behind.
    @Test(.timeLimit(.minutes(1)))
    func aPanelStrandedOnAnotherSpaceDoesNotHideTheNextOpen() async throws {
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
        overview.interrupt(reason: .command)
        try await Task.sleep(for: .milliseconds(400))  // past the fade-out
        let stranded = try #require(overview.panels[display])
        stranded.collectionBehavior = [.ignoresCycle]
        stranded.alphaValue = 0
        stranded.orderFrontRegardless()
        _ = await SpaceSwitcher(spaces: { SpacesProvider.snapshot() }).switchTo(space: second, on: display)
        try #require(await waitUntil(timeout: .seconds(3)) { SkyLightSpaces.currentSpace(displayUUID: display) == second })
        // The Arranger hears of the switch too, so its Space-change interrupt cannot close the open below.
        try #require(await waitUntil(timeout: .seconds(3)) { arrange.arranger.displays.first { $0.uuid == display }?.currentSpaceID == second })
        try await Task.sleep(for: .milliseconds(300))
        try #require(!stranded.isOnActiveSpace, "the setup did not leave the panel on the first desktop")

        await arrange.dispatch(.camera(.overview))
        try #require(await waitUntil(timeout: .seconds(2)) { !overview.openPanels.isEmpty }, "the overview never opened on the second desktop")
        let panel = try #require(overview.panels[display])
        #expect(await waitUntil(timeout: .seconds(2)) { isOnScreen(panel) }, "the overview is not on screen on the second desktop")
        #expect(stranded === panel || !stranded.isVisible, "the old panel is still ordered in on the first desktop")
        overview.interrupt(reason: .command)
        try await Task.sleep(for: .milliseconds(400))
        // A panel already on the shown Space is kept: no new window per open.
        await arrange.dispatch(.camera(.overview))
        try #require(await waitUntil(timeout: .seconds(2)) { !overview.openPanels.isEmpty }, "the overview did not open again")
        #expect(overview.panels[display] === panel, "a panel on the shown Space was replaced")
        overview.interrupt(reason: .command)
        try await Task.sleep(for: .milliseconds(400))
        try await returnToFirst()
    }
}

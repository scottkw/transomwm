import AppKit
import Foundation
@testable import TransomEngine
@testable import TransomMac
import TransomModel
import TransomPrivate
import Testing

/// UI-SPEC Surface 2, Space changes (Pitfall 8) live: a group's strip shows only on its group's Space. VM only: it
/// switches Spaces. It starts and ends on the first desktop; lock / unlock stays a UAT item.
@Suite(
    .serialized, .enabled(if: IntegrationEnv.trusted, "needs a process with the Accessibility grant"),
    .enabled(if: IntegrationEnv.inVM, "VM only: switches Spaces"))
@MainActor struct TabStripSpaceIntegrationTests {
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

    /// Switches the main display to `space`, waiting until it shows.
    private func show(_ space: UInt64, on display: String) async -> Bool {
        guard SkyLightSpaces.currentSpace(displayUUID: display) != space else { return true }
        _ = await SpaceSwitcher(spaces: { SpacesProvider.snapshot() }).switchTo(space: space, on: display)
        return await waitUntil(timeout: .seconds(3)) { SkyLightSpaces.currentSpace(displayUUID: display) == space }
    }

    /// The controller's strip panels, shown or ordered out.
    private func strips(_ arrange: ArrangeController) -> [NSWindow] {
        let numbers = arrange.tabStripPanels.windowNumbers
        return NSApp.windows.filter { numbers.contains($0.windowNumber) }
    }

    @Test(.timeLimit(.minutes(1)))
    func theStripShowsOnlyOnItsGroupsSpace() async throws {
        let (display, first, second) = try desktops()
        let relay = SpaceChangeRelay(display: display)  // D-17: the strip panels hear Space changes over SSH on 27.2
        defer { relay.stop() }
        try #require(await show(first, on: display), "could not start on the first desktop")
        let group = try await SavedGroup.start()
        defer { group.close() }
        defer { withExtendedLifetime(group.arrange) {} }
        let (formed, last, _) = await group.formed()
        try #require(formed, "the group never formed: windows at \(last)")
        var before: NSWindow?
        let shown = await waitUntil(timeout: .seconds(3)) {
            before = strips(group.arrange).first { $0.isVisible && $0.isOnActiveSpace }
            return before != nil
        }
        try #require(shown, "no strip on the first desktop")

        // From here every check is an #expect, so the test always gets back to the first desktop.
        #expect(await show(second, on: display), "could not switch to the second desktop")
        let hidden = await waitUntil(timeout: .milliseconds(1500)) {
            before?.isVisible == false && strips(group.arrange).allSatisfy { !$0.isVisible }
        }
        #expect(hidden, "a strip stayed ordered in on the second desktop")

        #expect(await show(first, on: display), "could not switch back to the first desktop")
        var after: NSWindow?
        let again = await waitUntil(timeout: .milliseconds(1500)) {
            after = strips(group.arrange).first { $0.isVisible && $0.isOnActiveSpace }
            return after != nil
        }
        #expect(again, "the strip did not come back on its group's Space")
        print("TabStripSpaceIntegrationTests: strip back=\(again), same panel reused=\(after.map { $0 === before } ?? false)")
        #expect(await show(first, on: display), "could not return to the first desktop")
    }
}

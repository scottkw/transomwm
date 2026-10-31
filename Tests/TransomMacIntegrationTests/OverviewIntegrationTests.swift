import AppKit
import Foundation
import TransomEngine
@testable import TransomMac
import TransomModel
import Testing

/// OVER-01 / D-01 / D-02 live: Show Overview opens one panel per display with a tile per fixture window, the windows
/// never move, and Show Overview again or Esc closes it. Fixture windows only, VM only (it posts an Esc key event).
@Suite(.serialized, .enabled(if: IntegrationEnv.trusted, "needs a process with the Accessibility grant"))
@MainActor struct OverviewIntegrationTests {
    /// Connects to the window server first (see ZoomSettleIntegrationTests).
    init() { _ = NSApplication.shared }

    @Test(.timeLimit(.minutes(1)))
    func overviewOpensPerDisplayAndCloses() async throws {
        let fixture = try await FixtureProcess.launch(["standard", "standard"])
        defer { fixture.terminate() }
        let fixturePID = fixture.pid
        let system = AXWindowSystem(appFilter: { pid, _ in pid == fixturePID })
        await system.start()
        let arrange = ArrangeController(system: system, zoomEnabled: true)
        defer { withExtendedLifetime(arrange) {} }  // its events loop ends with it
        await arrange.start()

        let tracked = await waitUntil(timeout: .seconds(3)) {
            fixture.windows.allSatisfy { window in arrange.arranger.windows.values.contains { $0.window.pid == fixturePID && $0.window.windowID == window.id } }
        }
        try #require(tracked, "the fixture windows were never tracked")
        func frames() async throws -> [Rect] {
            _ = try await fixture.send("list")
            return fixture.windows.sorted { $0.index < $1.index }.map(\.frame)
        }
        let before = try await frames()
        let main = try #require(arrange.arranger.displays.first?.uuid)
        let displayCount = arrange.arranger.displays.count

        await arrange.dispatch(.camera(.overview))
        let opened = await waitUntil(timeout: .seconds(2)) {
            arrange.overviewController?.isOpen == true && arrange.overviewController?.openPanels.count == displayCount
        }
        let overview = try #require(arrange.overviewController)
        try #require(opened, "the overview never opened on \(displayCount) displays: \(overview.openPanels)")
        #expect(overview.tileCount(display: main) >= 2)
        try await Task.sleep(for: .milliseconds(400))  // past the 250 ms move
        #expect(try await frames() == before, "the real windows moved while the overview was open")

        await arrange.dispatch(.camera(.overview))
        #expect(!overview.isOpen, "Show Overview again did not close it")

        await arrange.dispatch(.camera(.overview))
        try #require(await waitUntil(timeout: .seconds(2)) { overview.openPanels.count == displayCount }, "the overview did not open again")
        for down in [true, false] {
            CGEvent(keyboardEventSource: nil, virtualKey: 53, keyDown: down)?.post(tap: .cghidEventTap)  // Esc
        }
        // The Esc hotkey is a Carbon event: this process has no running NSApplication, so the test pumps AppKit's queue.
        let escaped = await waitUntil(timeout: .seconds(2)) {
            if let event = NSApp.nextEvent(matching: .any, until: Date(timeIntervalSinceNow: 0.02), inMode: .default, dequeue: true) {
                NSApp.sendEvent(event)
            }
            return !overview.isOpen
        }
        #expect(escaped, "Esc did not close the overview")
        try await Task.sleep(for: .milliseconds(400))
        #expect(try await frames() == before, "the real windows moved")
    }
}

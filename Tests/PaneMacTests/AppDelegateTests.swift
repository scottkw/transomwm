import AppKit
import PaneEngine
@testable import PaneMac
import Testing

/// SAFE-01, Pattern 11: a quit waits for the restore, then records the clean exit, then lets AppKit terminate.
/// SAFE-03, TILE-15, TILE-17: pane:// URLs reach the dispatcher only when strictly valid, at most once a second.
@Suite @MainActor struct AppDelegateTests {
    @Test func quittingRestoresThenWritesTheCleanExitThenReplies() async {
        var steps: [String] = []
        let delegate = AppDelegate(
            restore: { steps.append("restore") }, writeCleanExit: { steps.append("cleanExit") }, open: { _ in },
            urlScheme: "pane", reply: { steps.append("reply \($0)") })
        #expect(delegate.applicationShouldTerminate(NSApplication.shared) == .terminateLater)
        let replied = await waitFor { steps.count == 3 }
        #expect(replied)
        #expect(steps == ["restore", "cleanExit", "reply true"])
    }

    @Test func aValidURLDispatchesOnceAndAnythingElseNothing() throws {
        var opened: [Command] = []
        let delegate = AppDelegate(restore: {}, writeCleanExit: {}, open: { opened.append($0) }, urlScheme: "pane-debug")
        let urls = try ["pane-debug://restore", "pane-debug://restore?x=1", "pane://toggle-desktop", "pane-debug://zoom",
            "pane-debug://restore", "pane-debug://split-finder"].map { try #require(URL(string: $0)) }
        delegate.application(NSApplication.shared, open: urls)
        // The second restore is inside the same second.
        #expect(opened == [.restoreAll, .finderSplit])
    }

    @Test func withNoRegisteredSchemeEveryURLIsRejected() throws {
        var opened: [Command] = []
        let delegate = AppDelegate(restore: {}, writeCleanExit: {}, open: { opened.append($0) }, urlScheme: nil)
        delegate.application(NSApplication.shared, open: [try #require(URL(string: "pane://restore"))])
        #expect(opened.isEmpty)
    }

    /// Pitfall 21: a URL command that cannot act does nothing and does not beep; the same refusal from a hotkey beeps.
    @Test func aRefusedURLCommandDoesNotBeep() async {
        let arrange = ArrangeController(system: AXWindowSystem())
        var beeps = 0
        arrange.beep = { beeps += 1 }
        // Not started: no display, so Hide Desktop Tile has no desk to act on.
        await arrange.dispatch(.toggleDesktop, from: .url)
        #expect(beeps == 0)
        await arrange.dispatch(.toggleDesktop, from: .hotkey)
        #expect(beeps == 1)
    }

    private func waitFor(_ condition: () -> Bool) async -> Bool {
        for _ in 0..<100 where !condition() { try? await Task.sleep(for: .milliseconds(10)) }
        return condition()
    }
}

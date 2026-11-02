import AppKit
import TransomEngine
@testable import TransomMac
import Testing

/// SAFE-01, Pattern 11: a quit waits for the restore, then records the clean exit, then lets AppKit terminate.
/// SAFE-03, TILE-15, TILE-17: transom:// URLs reach the dispatcher only when strictly valid, at most once a second.
@Suite @MainActor struct AppDelegateTests {
    @Test func quittingRestoresThenWritesTheCleanExitThenReplies() async {
        var steps: [String] = []
        let delegate = AppDelegate(
            restore: { steps.append("restore") }, writeCleanExit: { steps.append("cleanExit") }, open: { _ in },
            urlScheme: "transom", reply: { steps.append("reply \($0)") })
        #expect(delegate.applicationShouldTerminate(NSApplication.shared) == .terminateLater)
        let replied = await waitFor { steps.count == 3 }
        #expect(replied)
        #expect(steps == ["restore", "cleanExit", "reply true"])
    }

    @Test func aValidURLDispatchesOnceAndAnythingElseNothing() throws {
        var opened: [Command] = []
        let delegate = AppDelegate(restore: {}, writeCleanExit: {}, open: { opened.append($0) }, urlScheme: "transom-debug")
        let urls = try ["transom-debug://restore", "transom-debug://restore?x=1", "transom://toggle-desktop", "transom-debug://zoom",
            "transom-debug://restore", "transom-debug://split-finder"].map { try #require(URL(string: $0)) }
        delegate.application(NSApplication.shared, open: urls)
        // The second restore is inside the same second.
        #expect(opened == [.restoreAll, .finderSplit])
    }

    @Test func withNoRegisteredSchemeEveryURLIsRejected() throws {
        var opened: [Command] = []
        let delegate = AppDelegate(restore: {}, writeCleanExit: {}, open: { opened.append($0) }, urlScheme: nil)
        delegate.application(NSApplication.shared, open: [try #require(URL(string: "transom://restore"))])
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

    /// 07 UAT Bug 2: `open` activates Transom to deliver a URL, so a URL acts on the app frontmost before Transom; with
    /// `open -g` Transom stays in the background and the frontmost app is used, as hotkeys and the menu always do.
    @Test func aURLActsOnTheAppFrontmostBeforeTransom() {
        let own: Int32 = 100
        #expect(ArrangeController.commandPID(frontmost: own, beforeTransom: 7, from: .url, own: own) == 7)
        #expect(ArrangeController.commandPID(frontmost: own, beforeTransom: nil, from: .url, own: own) == nil)
        #expect(ArrangeController.commandPID(frontmost: 8, beforeTransom: 7, from: .url, own: own) == 8)
        #expect(ArrangeController.commandPID(frontmost: nil, beforeTransom: 7, from: .url, own: own) == nil)
        #expect(ArrangeController.commandPID(frontmost: own, beforeTransom: 7, from: .hotkey, own: own) == own)
        #expect(ArrangeController.commandPID(frontmost: own, beforeTransom: 7, from: .menu, own: own) == own)
    }

    private func waitFor(_ condition: () -> Bool) async -> Bool {
        for _ in 0..<100 where !condition() { try? await Task.sleep(for: .milliseconds(10)) }
        return condition()
    }
}

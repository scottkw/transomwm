import AppKit
import TransomEngine
@testable import TransomMac
import Testing

/// SAFE-01, Pattern 11: a quit runs the restore, then records the clean exit, before AppKit is told to terminate.
/// SAFE-03, TILE-15, TILE-17: transom:// URLs reach the dispatcher only when strictly valid, at most once a second.
@Suite @MainActor struct AppDelegateTests {
    /// The work is done by the time the delegate answers, so no quit depends on a later turn of the main queue: the SIGTERM
    /// source calls terminate from inside that queue, where a block queued for later never runs (sigterm-quit-hang).
    @Test func quittingRestoresThenWritesTheCleanExitBeforeAnswering() {
        var steps: [String] = []
        let delegate = AppDelegate(
            restore: { steps.append("restore") }, writeCleanExit: { steps.append("cleanExit") }, open: { _ in },
            gate: CommandGate(scheme: "transom"))
        #expect(delegate.applicationShouldTerminate(NSApplication.shared) == .terminateNow)
        #expect(steps == ["restore", "cleanExit"])
    }

    @Test func aValidURLDispatchesOnceAndAnythingElseNothing() throws {
        var opened: [Command] = []
        let delegate = AppDelegate(restore: {}, writeCleanExit: {}, open: { opened.append($0) }, gate: CommandGate(scheme: "transom-debug"))
        let urls = try ["transom-debug://restore", "transom-debug://restore?x=1", "transom://float-all", "transom-debug://zoom",
            "transom-debug://restore", "transom-debug://split-finder"].map { try #require(URL(string: $0)) }
        delegate.application(NSApplication.shared, open: urls)
        // The second restore is inside the same second.
        #expect(opened == [.restoreAll, .finderSplit])
    }

    /// WR-09: anything can open a URL, so cycling through the ten dock URLs still gets one edit a second, and the 50-step
    /// undo history survives a page that does it.
    @Test func theDockURLsShareOneSecond() throws {
        var opened: [Command] = []
        let delegate = AppDelegate(restore: {}, writeCleanExit: {}, open: { opened.append($0) }, gate: CommandGate(scheme: "transom"))
        let urls = try ["transom://dock-column-1", "transom://dock-column-2", "transom://dock-row-middle", "transom://restore"].map { try #require(URL(string: $0)) }
        delegate.application(NSApplication.shared, open: urls)
        #expect(opened == [.dockFourth(.first, .horizontal), .restoreAll])
    }

    @Test func withNoRegisteredSchemeEveryURLIsRejected() throws {
        var opened: [Command] = []
        let delegate = AppDelegate(restore: {}, writeCleanExit: {}, open: { opened.append($0) }, gate: CommandGate(scheme: nil))
        delegate.application(NSApplication.shared, open: [try #require(URL(string: "transom://restore"))])
        #expect(opened.isEmpty)
    }

    /// Pitfall 21: a URL command that cannot act does nothing and does not beep; the same refusal from a hotkey beeps.
    @Test func aRefusedURLCommandDoesNotBeep() async {
        let arrange = ArrangeController(system: AXWindowSystem())
        var beeps = 0
        arrange.beep = { beeps += 1 }
        // Not started: no display, so Float All has no desk to act on.
        await arrange.dispatch(.floatAll, from: .url)
        #expect(beeps == 0)
        await arrange.dispatch(.floatAll, from: .hotkey)
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
        #expect(ArrangeController.commandPID(frontmost: own, beforeTransom: 7, from: .cli, own: own) == 7)
    }
}

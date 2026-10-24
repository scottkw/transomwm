import AppKit
import PaneMac
import Testing

/// A gate over private notification centers, with the session dictionary and frontmost app under test control.
@MainActor final class GateHarness {
    let workspace = NotificationCenter()
    let distributed = NotificationCenter()
    var dictionary: [String: Any]? = [:]
    var frontmost: String? = "com.apple.finder"
    private(set) var pauses = 0
    private(set) var resumes = 0
    private(set) var gate: SessionGate!

    init() {
        gate = SessionGate(
            workspaceCenter: workspace, distributedCenter: distributed,
            sessionDictionary: { [unowned self] in dictionary }, frontmostBundleID: { [unowned self] in frontmost },
            onPause: { [unowned self] in pauses += 1 }, onResume: { [unowned self] in resumes += 1 }
        )
    }

    func distributed(_ name: String) { distributed.post(name: Notification.Name(name), object: nil) }
    func workspace(_ name: Notification.Name) { workspace.post(name: name, object: nil) }
}

@MainActor @Suite struct SessionGateTests {
    @Test func aScreenLockPausesOnce() {
        let h = GateHarness()
        h.distributed("com.apple.screenIsLocked")
        #expect(h.gate.isPaused)
        #expect(h.pauses == 1)
        h.distributed("com.apple.screenIsLocked")
        #expect(h.pauses == 1)
    }

    @Test func unlockAloneDoesNotClearSleep() {
        let h = GateHarness()
        h.distributed("com.apple.screenIsLocked")
        h.workspace(NSWorkspace.willSleepNotification)
        h.distributed("com.apple.screenIsUnlocked")
        #expect(h.gate.isPaused)
        #expect(h.resumes == 0)
        h.workspace(NSWorkspace.didWakeNotification)
        #expect(!h.gate.isPaused)
        #expect(h.pauses == 1)
        #expect(h.resumes == 1)
    }

    @Test func displaySleepPausesUntilTheScreensWake() {
        let h = GateHarness()
        h.workspace(NSWorkspace.screensDidSleepNotification)
        #expect(h.gate.isPaused)
        h.workspace(NSWorkspace.screensDidWakeNotification)
        #expect(!h.gate.isPaused)
        #expect(h.resumes == 1)
    }

    @Test func theLoginWindowInFrontPauses() {
        let h = GateHarness()
        h.frontmost = "com.apple.loginwindow"
        h.gate.evaluate()
        #expect(h.gate.isPaused)
        h.frontmost = "com.apple.finder"
        h.workspace(NSWorkspace.didActivateApplicationNotification)
        #expect(!h.gate.isPaused)
        #expect(h.resumes == 1)
    }

    @Test func theSessionLockFlagPauses() {
        let h = GateHarness()
        h.dictionary = ["CGSSessionScreenIsLocked": true]
        h.gate.evaluate()
        #expect(h.gate.isPaused)
        #expect(h.pauses == 1)
    }

    @Test func anEmptySessionDictionaryDoesNotPause() {
        let h = GateHarness()
        h.dictionary = [:]
        h.gate.evaluate()
        #expect(!h.gate.isPaused)
        #expect(h.pauses == 0)
    }

    @Test func fastUserSwitchingPausesUntilTheSessionIsActiveAgain() {
        let h = GateHarness()
        h.workspace(NSWorkspace.sessionDidResignActiveNotification)
        #expect(h.gate.isPaused)
        h.workspace(NSWorkspace.sessionDidBecomeActiveNotification)
        #expect(!h.gate.isPaused)
        #expect(h.resumes == 1)
    }
}

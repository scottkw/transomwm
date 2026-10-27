import Darwin
import Foundation
import TransomMac
import Testing

/// Never sends a real signal: every FreezeTest here gets a recording signal function.
@MainActor @Suite struct FreezeTestTests {
    final class Recorder {
        var calls: [(pid: pid_t, signal: Int32, storedPID: Int)] = []
    }

    let suiteName = "transom-test-\(UUID().uuidString)"
    let defaults: UserDefaults
    let recorder = Recorder()

    init() { defaults = UserDefaults(suiteName: suiteName)! }

    func make(resumeAfter: Duration = .seconds(10)) -> FreezeTest {
        let defaults = defaults, recorder = recorder
        return FreezeTest(defaults: defaults, signal: { pid, signal in
            recorder.calls.append((pid, signal, defaults.integer(forKey: FreezeTest.defaultsKey)))
            return 0
        }, resumeAfter: resumeAfter)
    }

    func cleanUp() { UserDefaults().removePersistentDomain(forName: suiteName) }

    @Test(arguments: ["com.apple.loginwindow", "com.apple.finder", "com.apple.dock", "com.apple.systemuiserver", "com.apple.Finder", "COM.APPLE.DOCK"])
    func systemProcessesAreRefused(_ bundleID: String) {
        #expect(!FreezeTest.isAllowed(pid: 500, bundleID: bundleID, ownPID: 100))
    }

    @Test func ownPIDAndLowPIDsAreRefused() {
        #expect(!FreezeTest.isAllowed(pid: 100, bundleID: "com.example.app", ownPID: 100))
        #expect(!FreezeTest.isAllowed(pid: 1, bundleID: "com.example.app", ownPID: 100))
        #expect(!FreezeTest.isAllowed(pid: 0, bundleID: nil, ownPID: 100))
        #expect(FreezeTest.isAllowed(pid: 500, bundleID: "com.apple.TextEdit", ownPID: 100))
    }

    @Test func freezeRecordsThePIDBeforeStopping() {
        defer { cleanUp() }
        let freeze = make()
        #expect(freeze.freeze(pid: 4242))
        #expect(recorder.calls.count == 1)
        #expect(recorder.calls.first?.pid == 4242)
        #expect(recorder.calls.first?.signal == SIGSTOP)
        #expect(recorder.calls.first?.storedPID == 4242)
        #expect(freeze.frozenPID == 4242)
        freeze.resumeNow()
    }

    @Test func itResumesByItself() async throws {
        defer { cleanUp() }
        let freeze = make(resumeAfter: .milliseconds(50))
        freeze.freeze(pid: 4242)
        let deadline = ContinuousClock.now + .seconds(1)
        while freeze.frozenPID != nil, ContinuousClock.now < deadline { try await Task.sleep(for: .milliseconds(10)) }
        #expect(recorder.calls.map(\.signal) == [SIGSTOP, SIGCONT])
        #expect(recorder.calls.last?.pid == 4242)
        #expect(freeze.frozenPID == nil)
        #expect(defaults.object(forKey: FreezeTest.defaultsKey) == nil)
    }

    @Test func resumeNowContinuesAtOnceAndASecondFreezeIsRefused() {
        defer { cleanUp() }
        let freeze = make()
        #expect(freeze.freeze(pid: 4242))
        #expect(!freeze.freeze(pid: 4343))
        #expect(freeze.frozenPID == 4242)
        freeze.resumeNow()
        #expect(recorder.calls.map(\.signal) == [SIGSTOP, SIGCONT])
        #expect(recorder.calls.last?.pid == 4242)
        #expect(freeze.frozenPID == nil)
        #expect(defaults.object(forKey: FreezeTest.defaultsKey) == nil)
    }

    @Test func aRecordedPIDIsResumedAtLaunch() {
        defer { cleanUp() }
        defaults.set(4242, forKey: FreezeTest.defaultsKey)
        make().resumeRecordedPID()
        #expect(recorder.calls.map(\.pid) == [4242])
        #expect(recorder.calls.map(\.signal) == [SIGCONT])
        #expect(defaults.object(forKey: FreezeTest.defaultsKey) == nil)
    }

    @Test func nothingRecordedSendsNothing() {
        defer { cleanUp() }
        make().resumeRecordedPID()
        #expect(recorder.calls.isEmpty)
    }

    @Test func freezeCopyUsesTheAppName() {
        #expect(MenuCopy.freezeItem(appName: "Safari") == "Freeze \u{201C}Safari\u{201D} for 10 Seconds\u{2026}")
        #expect(MenuCopy.freezeNotAllowed == "Freeze Frontmost App (not allowed)")
        #expect(MenuCopy.resumeItem(appName: "Safari") == "Resume \u{201C}Safari\u{201D} Now")
        #expect(MenuCopy.freezeAlertMessage(appName: "Safari") == "Freeze \u{201C}Safari\u{201D} for 10 seconds?")
    }
}

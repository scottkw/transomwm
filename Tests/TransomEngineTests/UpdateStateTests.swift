import Foundation
import TransomEngine
import Testing

/// gifsmith `services/updates.go` `Check`: one operation at a time, and a failure puts back the status from before it.
struct UpdateStateTests {
    static let release = UpdateRelease(
        version: "1.0.0", url: URL(string: "https://github.com/scottkw/transomwm/releases/download/v1.0.0/x")!, size: 1,
        sha256: String(repeating: "ab", count: 32))

    /// A machine showing `status`, reached through a successful check.
    static func machine(_ status: UpdateStatus) -> UpdateMachine {
        var machine = UpdateMachine()
        if status != .idle {
            let started = machine.begin(.check)
            #expect(started)
            machine.succeed(status)
        }
        return machine
    }

    @Test func aSecondCheckWhileCheckingIsRefused() {
        for status in [UpdateStatus.idle, .current("0.9.0"), .available(Self.release)] {
            var machine = Self.machine(status)
            #expect(!machine.isBusy)
            let started = machine.begin(.check)
            #expect(started)
            #expect(machine.status == .checking)
            #expect(machine.isBusy)
            let before = machine
            let refused = machine.begin(.check)
            #expect(!refused)
            #expect(machine == before)
        }
    }

    @Test func aFailedManualCheckRestoresAndShowsTheError() {
        var machine = Self.machine(.available(Self.release))
        let started = machine.begin(.check)
        #expect(started)
        machine.fail(.checkFailed, manual: true)
        #expect(machine.status == .available(Self.release))
        #expect(machine.error == .checkFailed)
        #expect(!machine.isBusy)
    }

    @Test func aFailedAutomaticCheckRestoresSilently() {
        var machine = Self.machine(.available(Self.release))
        let started = machine.begin(.check)
        #expect(started)
        machine.fail(.checkFailed, manual: false)
        #expect(machine.status == .available(Self.release))
        #expect(machine.error == nil)
        var fresh = UpdateMachine()
        let freshStarted = fresh.begin(.check)
        #expect(freshStarted)
        fresh.fail(.checkFailed, manual: false)
        #expect(fresh.status == .idle)
    }

    @Test func successClearsAnOldError() {
        var machine = UpdateMachine()
        let started = machine.begin(.check)
        #expect(started)
        machine.fail(.checkFailed, manual: true)
        #expect(machine.error == .checkFailed)
        let again = machine.begin(.check)
        #expect(again)
        machine.succeed(.current("0.9.0"))
        #expect(machine.status == .current("0.9.0"))
        #expect(machine.error == nil)
    }
}

/// gifsmith `services/updates.go` `Download`: only from available or opened, busy until it ends, failures go back to
/// available.
extension UpdateStateTests {
    @Test func aDownloadStartsOnlyFromAvailableOrOpened() {
        let release = UpdateStateTests.release
        for status in [UpdateStatus.idle, .current("0.9.0")] {
            var machine = UpdateStateTests.machine(status)
            let started = machine.begin(.download)
            #expect(!started)
            #expect(machine.status == status)
        }
        var machine = UpdateStateTests.machine(.available(release))
        let started = machine.begin(.download)
        #expect(started)
        #expect(machine.status == .downloading(release, fraction: nil))
        for op in [UpdateMachine.Operation.check, .download] {
            let refused = machine.begin(op)
            #expect(!refused)
        }
        machine.succeed(.verifying(release))
        #expect(machine.isBusy)
        machine.succeed(.opened(release))
        #expect(!machine.isBusy)
        let again = machine.begin(.download)
        #expect(again)
        machine.fail(.verifyFailed, manual: true)
        #expect(machine.status == .available(release))
        #expect(machine.error == .verifyFailed)
    }
}

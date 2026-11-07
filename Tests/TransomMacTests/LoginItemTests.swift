import Foundation
@testable import TransomMac
import Testing

/// Stands in for the system login item: the host's real one is never registered from a test (T-09-16).
private final class FakeLoginItem: LoginItemService {
    struct Refused: Error {}

    var status: LoginItemStatus
    /// What `register()` leaves `status` at when it succeeds.
    var statusAfterRegister: LoginItemStatus = .enabled
    var registerError: (any Error)?
    var registers = 0
    var unregisters = 0

    init(status: LoginItemStatus) { self.status = status }

    func register() throws {
        registers += 1
        if let registerError { throw registerError }
        status = statusAfterRegister
    }

    func unregister() throws {
        unregisters += 1
        status = .notRegistered
    }

    func openSystemSettingsLoginItems() {}
}

/// SHIP-03: Settings ▸ General ▸ "Open Transom at login" over the login item service.
@Suite @MainActor struct LoginItemTests {
    @Test func turningItOnRegistersAndShowsEnabled() {
        let fake = FakeLoginItem(status: .notRegistered)
        let toggle = LoginItemToggle.toggled(true, service: fake)
        #expect(fake.registers == 1)
        #expect(toggle.isOn)
        #expect(!toggle.needsApproval)
        #expect(toggle.footer == nil)
    }

    @Test func requiresApprovalKeepsItOnAndAsksForApproval() {
        let fake = FakeLoginItem(status: .notRegistered)
        fake.statusAfterRegister = .requiresApproval
        let toggle = LoginItemToggle.toggled(true, service: fake)
        #expect(toggle.isOn)
        #expect(toggle.needsApproval)
        #expect(toggle.footer == nil)
        // The status read when the tab shows says the same.
        #expect(LoginItemToggle(status: .requiresApproval).isOn)
    }

    @Test func aRegisterErrorLeavesTheToggleOff() {
        let fake = FakeLoginItem(status: .notRegistered)
        fake.registerError = FakeLoginItem.Refused()
        let toggle = LoginItemToggle.toggled(true, service: fake)
        #expect(fake.registers == 1)
        #expect(!toggle.isOn)
        #expect(toggle.footer == SettingsCopy.loginItemFailed)
    }

    @Test func turningItOffUnregisters() {
        let fake = FakeLoginItem(status: .enabled)
        let toggle = LoginItemToggle.toggled(false, service: fake)
        #expect(fake.unregisters == 1)
        #expect(fake.registers == 0)
        #expect(!toggle.isOn)
        #expect(toggle.footer == nil)
    }
}

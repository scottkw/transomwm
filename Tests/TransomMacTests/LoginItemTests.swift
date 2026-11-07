import Foundation
@testable import TransomMac
import Testing

/// Stands in for the system login item: the host's real one is never registered from a test (T-09-16).
final class FakeLoginItem: LoginItemService {
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

    @Test func theDebugLineNamesEveryStatus() {
        #expect(SettingsCopy.loginItemDebugLine(.enabled) == "Login item: enabled")
        #expect(SettingsCopy.loginItemDebugLine(.notRegistered) == "Login item: not registered")
        #expect(SettingsCopy.loginItemDebugLine(.requiresApproval) == "Login item: needs approval")
        #expect(SettingsCopy.loginItemDebugLine(.notFound) == "Login item: not found")
    }

    @Test func theCLIPathPrefersHomebrewsBin() {
        let both: Set<String> = ["/opt/homebrew/bin/transom", "/usr/local/bin/transom"]
        #expect(GeneralTab.installedCLIPath(exists: { both.contains($0) }) == "/opt/homebrew/bin/transom")
        #expect(GeneralTab.installedCLIPath(exists: { $0 == "/usr/local/bin/transom" }) == "/usr/local/bin/transom")
        #expect(GeneralTab.installedCLIPath(exists: { _ in false }) == nil)
    }
}

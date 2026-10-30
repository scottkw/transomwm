import Foundation
@testable import TransomMac
import TransomPrivate
import Testing

/// 05-07 in the VM, which has no multitouch device (Tart's pointer is not one): the real shim loads, lists nothing,
/// and start, wake rescan and stop all run without a device and without a crash. VM only (TRANSOM_LIVE=1); never on
/// the host, where it would open the built-in trackpad.
@Suite(.serialized, .enabled(if: IntegrationEnv.trusted, "VM only: opens multitouch devices when any exist"))
@MainActor struct MultitouchIntegrationTests {
    @Test func noDevicesIsGracefulThroughTheRealShim() throws {
        #expect(MultitouchSupport.isLoaded, "12 of 12 symbols resolved in the VM spike")
        #expect(Capabilities.isAvailable(.multitouch) == !MultitouchCanary.tripped)
        let name = "transom.mt.vm.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let devices = MultitouchDevices(canary: MultitouchCanary(defaults: defaults), available: { MultitouchSupport.isLoaded })
        devices.start()
        #expect(devices.isRunning)
        #expect(devices.count == 0)
        #expect(devices.status == .available(0))
        #expect(GestureCopy.multitouchLine(devices.status) == "Multitouch: available, no trackpad found")
        devices.rescan(afterWake: true)
        #expect(devices.isRunning)
        #expect(devices.count == 0)
        devices.stop()
        #expect(!devices.isRunning)
        #expect(defaults.object(forKey: MultitouchCanary.key) == nil, "a clean stop clears the canary")
    }
}

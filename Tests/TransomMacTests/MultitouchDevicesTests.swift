import Foundation
@testable import TransomMac
import TransomPrivate
import Testing

/// A scripted device list: each `open` returns the next list. No multitouch device exists here.
@MainActor private final class FakeBackend: MultitouchBackend {
    var lists: [[MultitouchSupport.Info]]
    var calls: [String] = []
    var onFrame: (@MainActor @Sendable (MultitouchSupport.Frame, MultitouchSupport.Info) -> Void)?

    init(_ lists: [[MultitouchSupport.Info]]) { self.lists = lists }

    func open(onFrame: @escaping @MainActor @Sendable (MultitouchSupport.Frame, MultitouchSupport.Info) -> Void) -> [MultitouchSupport.Info] {
        calls.append("open")
        self.onFrame = onFrame
        return lists.count > 1 ? lists.removeFirst() : lists.first ?? []
    }

    func close() { calls.append("close") }
}

private func device(_ registry: UInt64, family: Int32 = 110, builtIn: Bool = true) -> MultitouchSupport.Info {
    MultitouchSupport.Info(
        index: 0, builtIn: builtIn, family: family, deviceID: registry, registryID: registry, widthMM: 100, heightMM: 70, driverType: 0)
}

/// 05-07 device lifecycle with a fake backend (M3: hot-plug can't be tried on the host, and the VM has no device).
@Suite(.serialized) @MainActor struct MultitouchDevicesTests {
    private func canary() -> (MultitouchCanary, UserDefaults) {
        let name = "transom.mt.test.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return (MultitouchCanary(defaults: defaults, osBuild: "B", appVersion: "V"), defaults)
    }

    @Test func startListsOnceArmsTheCanaryAndCountsTrackpadsOnly() {
        let backend = FakeBackend([[device(1), device(2, family: 112, builtIn: false)]])
        let (canary, defaults) = canary()
        let devices = MultitouchDevices(backend: backend, canary: canary, available: { true })
        devices.start()
        devices.start()
        #expect(backend.calls == ["open"])
        #expect(devices.count == 1, "a Magic Mouse is not a trackpad")
        #expect(devices.status == .available(1))
        #expect(defaults.object(forKey: MultitouchCanary.key) != nil, "armed before the first risky call")
        devices.stop()
        #expect(backend.calls == ["open", "close"])
        #expect(!devices.isRunning)
        #expect(defaults.object(forKey: MultitouchCanary.key) == nil, "a clean stop clears it")
    }

    @Test func aRescanStopsTheOldListBeforeListingAgain() {
        let backend = FakeBackend([[device(1)], [device(1), device(3, builtIn: false)], [device(3, builtIn: false)]])
        let devices = MultitouchDevices(backend: backend, canary: canary().0, available: { true })
        devices.start()
        devices.rescan(afterWake: false)  // a second trackpad appeared
        #expect(devices.count == 2)
        devices.rescan(afterWake: true)  // the built-in one went
        #expect(devices.devices.map(\.registryID) == [3])
        #expect(backend.calls == ["open", "close", "open", "close", "open"])
        devices.stop()
    }

    @Test func noDevicesIsAvailableWithNoTrackpad() {
        let devices = MultitouchDevices(backend: FakeBackend([[]]), canary: canary().0, available: { true })
        devices.start()
        #expect(devices.isRunning)
        #expect(devices.status == .available(0))
        devices.stop()
    }

    @Test func unavailableOpensNothingAndRescanIsANoOpWhenStopped() {
        let backend = FakeBackend([[device(1)]])
        let devices = MultitouchDevices(backend: backend, canary: canary().0, available: { false })
        devices.start()
        devices.rescan(afterWake: true)
        #expect(backend.calls.isEmpty)
        #expect(!devices.isRunning)
        #expect(devices.status == (MultitouchCanary.tripped ? .offAfterCrash : .off))
    }

    @Test func framesReachTheHandlerAndTwoHealthySecondsClearTheCanary() async throws {
        let backend = FakeBackend([[device(1)]])
        let (canary, defaults) = canary()
        let devices = MultitouchDevices(backend: backend, canary: canary, available: { true })
        var received = 0
        devices.onFrame = { _, _ in received += 1 }
        devices.start()
        let frame = MultitouchSupport.Frame(device: 256, t: 0, deviceTime: 0, frame: 1, rawCount: 0, touches: [], mainThread: true)
        backend.onFrame?(frame, device(1))
        #expect(received == 1)
        #expect(defaults.object(forKey: MultitouchCanary.key) != nil)
        try await Task.sleep(for: .milliseconds(2300))
        #expect(defaults.object(forKey: MultitouchCanary.key) == nil)
        #expect(devices.isRunning, "clearing the canary does not stop anything")
        devices.stop()
        backend.onFrame?(frame, device(1))
        #expect(received == 1, "no frame is handled after stop")
    }
}

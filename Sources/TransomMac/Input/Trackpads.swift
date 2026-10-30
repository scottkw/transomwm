import Foundation
import IOKit

/// One multitouch trackpad in the IOKit registry. `registryID` is what gesture events carry in field 87 (05-SPIKE T6).
nonisolated struct Trackpad: Equatable, Sendable {
    let registryID: UInt64
    let familyID: Int
}

/// The trackpads, from public IOKit only (E-04, RESEARCH Pattern 5).
nonisolated enum Trackpads {
    /// Magic Mouse family: a multitouch device whose scrolls are a mouse's (RESEARCH Pitfall 9).
    static let magicMouseFamily = 112

    static func current() -> [Trackpad] {
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("AppleMultitouchDevice"), &iterator) == KERN_SUCCESS
        else { return [] }
        defer { IOObjectRelease(iterator) }
        var pads: [Trackpad] = []
        while case let service = IOIteratorNext(iterator), service != 0 {
            defer { IOObjectRelease(service) }
            var id: UInt64 = 0
            guard IORegistryEntryGetRegistryEntryID(service, &id) == KERN_SUCCESS else { continue }
            let family = IORegistryEntryCreateCFProperty(service, "Family ID" as CFString, kCFAllocatorDefault, 0)?
                .takeRetainedValue() as? Int ?? 0
            if family != magicMouseFamily { pads.append(Trackpad(registryID: id, familyID: family)) }
        }
        return pads
    }
}

/// Calls `onChange` on main when a multitouch device appears or goes (IOKit first-match and terminated notifications).
@MainActor final class TrackpadWatcher {
    private var port: IONotificationPortRef?
    private var iterators: [io_iterator_t] = []
    private let onChange: @MainActor () -> Void

    init(onChange: @escaping @MainActor () -> Void) {
        self.onChange = onChange
        guard let port = IONotificationPortCreate(kIOMainPortDefault) else { return }
        self.port = port
        CFRunLoopAddSource(CFRunLoopGetMain(), IONotificationPortGetRunLoopSource(port).takeUnretainedValue(), .commonModes)
        let refcon = Unmanaged.passUnretained(self).toOpaque()
        for type in [kIOFirstMatchNotification, kIOTerminatedNotification] {
            var iterator: io_iterator_t = 0
            guard IOServiceAddMatchingNotification(port, type, IOServiceMatching("AppleMultitouchDevice"), Self.callback, refcon, &iterator)
                == KERN_SUCCESS
            else { continue }
            Self.drain(iterator)  // arms the notification; the devices already there are not a change
            iterators.append(iterator)
        }
    }

    isolated deinit { stop() }

    func stop() {
        for iterator in iterators { IOObjectRelease(iterator) }
        iterators = []
        if let port { IONotificationPortDestroy(port) }
        port = nil
    }

    /// Runs on the main run loop, where the port's source is.
    nonisolated private static let callback: IOServiceMatchingCallback = { refcon, iterator in
        drain(iterator)  // required to re-arm
        guard let refcon else { return }
        let watcher = Unmanaged<TrackpadWatcher>.fromOpaque(refcon).takeUnretainedValue()
        MainActor.assumeIsolated { watcher.onChange() }
    }

    nonisolated private static func drain(_ iterator: io_iterator_t) {
        while case let service = IOIteratorNext(iterator), service != 0 { IOObjectRelease(service) }
    }
}

import AppKit
import TransomPrivate
import os

/// What `MultitouchDevices` drives: the shim, or a fake in tests, so the device-list and rescan logic runs headless (no
/// multitouch device exists in unit tests or the VM).
@MainActor protocol MultitouchBackend: AnyObject {
    /// Lists the devices and starts every trackpad of the new list. Its frames reach `onFrame` on main.
    func open(onFrame: @escaping @MainActor @Sendable (MultitouchSupport.Frame, MultitouchSupport.Info) -> Void) -> [MultitouchSupport.Info]
    /// Stops and unregisters every started device, then drops the list, which owns them. Never releases a device.
    func close()
}

/// The real backend: the TransomPrivate shim on its own CFRunLoop thread, made at the first open only.
@MainActor final class ShimMultitouchBackend: MultitouchBackend {
    private lazy var worker = MultitouchSupport.Worker()
    private var list: MultitouchSupport.DeviceList?
    private var generation = 0

    func open(onFrame: @escaping @MainActor @Sendable (MultitouchSupport.Frame, MultitouchSupport.Info) -> Void) -> [MultitouchSupport.Info] {
        generation += 1
        let list = MultitouchSupport.DeviceList()
        self.list = list
        // Each list's frames carry its own tag base, so a late frame from a list a rescan dropped is ignored.
        let base = generation << 8
        let pads = Dictionary(uniqueKeysWithValues: list.infos.filter(\.isTrackpad).map { (base + $0.index, $0) })
        MultitouchSupport.setHandler(Self.frameHandler(pads: pads, onFrame: onFrame))
        _ = MultitouchSupport.startStreaming(list, on: worker, tagBase: base)
        return list.infos
    }

    /// What the shim calls on main per frame: a frame whose tag is not this list's is dropped.
    static func frameHandler(
        pads: [Int: MultitouchSupport.Info], onFrame: @escaping @MainActor @Sendable (MultitouchSupport.Frame, MultitouchSupport.Info) -> Void
    ) -> (MultitouchSupport.Frame) -> Void {
        { frame in if let info = pads[frame.device] { onFrame(frame, info) } }
    }

    func close() {
        guard let list else { return }
        MultitouchSupport.stopStreaming(list, on: worker)
        MultitouchSupport.setHandler(nil)
        self.list = nil  // dropped only after every device stopped (Pitfall 7)
    }
}

/// The multitouch devices while the gesture tap runs (05-07, D-07: none is opened while zoom is off). Re-enumerates on
/// IOKit kIOFirstMatchNotification / kIOTerminatedNotification for AppleMultitouchDevice (through `TrackpadWatcher`)
/// and on wake. Arms the crash canary before each device list and clears it only at a clean stop: the 05-08 UAT crash
/// came minutes into streaming, long after a "2 s of healthy frames" clear, so any crash while streaming trips it.
@MainActor final class MultitouchDevices {
    private let backend: any MultitouchBackend
    private let canary: MultitouchCanary
    private let available: () -> Bool
    private let log = Logger(subsystem: "com.eightabyte.transom", category: "gesture")
    private(set) var isRunning = false
    /// Every device of the current list, Magic Mouse included; only trackpads stream.
    private(set) var devices: [MultitouchSupport.Info] = []
    var count: Int { devices.filter(\.isTrackpad).count }
    /// Each frame, on main.
    var onFrame: (MultitouchSupport.Frame, MultitouchSupport.Info) -> Void = { _, _ in }
    private var watcher: TrackpadWatcher?
    private var wakeObserver: (any NSObjectProtocol)?

    init(
        backend: any MultitouchBackend = ShimMultitouchBackend(), canary: MultitouchCanary = MultitouchCanary(),
        available: @escaping () -> Bool = { Capabilities.isAvailable(.multitouch) }
    ) {
        self.backend = backend
        self.canary = canary
        self.available = available
    }

    /// The G4 Debug value; `count` when running, else the trackpads IOKit lists (no device opened for it).
    var status: GestureCopy.Multitouch {
        guard available() else { return MultitouchCanary.tripped ? .offAfterCrash : .off }
        return .available(isRunning ? count : Trackpads.current().count)
    }

    func start() {
        guard !isRunning, available() else { return }
        isRunning = true
        open()
        log.info("multitouch: \(self.count, privacy: .public) devices")
        watcher = TrackpadWatcher { [weak self] in self?.rescan(afterWake: false) }
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) {
            [weak self] _ in MainActor.assumeIsolated { self?.rescan(afterWake: true) }
        }
    }

    func stop() {
        guard isRunning else { return }
        isRunning = false
        watcher?.stop()
        watcher = nil
        if let wakeObserver { NSWorkspace.shared.notificationCenter.removeObserver(wakeObserver) }
        wakeObserver = nil
        backend.close()
        devices = []
        canary.clear()
    }

    /// Stops and drops the old list, then lists again (device added, removed, or wake).
    func rescan(afterWake: Bool) {
        guard isRunning else { return }
        if afterWake { log.info("multitouch: rescan after wake") }
        let before = devices.filter(\.isTrackpad)
        backend.close()
        open()
        let after = devices.filter(\.isTrackpad)
        for info in after where !before.contains(where: { $0.registryID == info.registryID }) {
            log.info("multitouch: added \(info.builtIn ? "built-in" : "external", privacy: .public) family \(info.family, privacy: .public)")
        }
        for info in before where !after.contains(where: { $0.registryID == info.registryID }) {
            log.info("multitouch: removed registry \(String(info.registryID, radix: 16), privacy: .public)")
        }
    }

    private func open() {
        canary.arm()
        devices = backend.open { [weak self] frame, info in self?.frame(frame, info) }
    }

    private func frame(_ frame: MultitouchSupport.Frame, _ info: MultitouchSupport.Info) {
        guard isRunning else { return }
        onFrame(frame, info)
    }
}

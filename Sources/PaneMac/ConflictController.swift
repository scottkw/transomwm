import AppKit
import PaneEngine
import os

/// Watches the macOS features that fight Pane (SAFE-04, D-19 to D-22): polls com.apple.WindowManager every 2 s and on
/// activation, pauses arranging while Stage Manager is on, and turns a feature off on request, recording each key's
/// original once, before the first write, and reading the write back. `ConflictPolicy` decides; this does the I/O.
@MainActor final class ConflictController {
    static let originalsKey = "windowManagerOriginals"

    /// `.setPaused(.stageManager, on)`, sent when Stage Manager's state first becomes known and on every change.
    var setStageManagerPaused: (Bool) -> Void = { _ in }
    /// Toasts N7 and N8.
    var post: (Notice) -> Void = { _ in }
    var openSettings: (URL) -> Void = { NSWorkspace.shared.open($0) }
    static let desktopAndDock = URL(string: "x-apple.systempreferences:com.apple.Desktop-Settings.extension")!
    private(set) var active: Set<Conflict> = []
    /// Each written key's value before Pane first wrote it; `.absent` means Restore deletes the key.
    private(set) var originals: [String: PrefValue]

    private let store: any PreferencesStore
    private let defaults: UserDefaults
    private let osMajor: Int
    private let readBackDelay: Duration
    private var reportedStageManager: Bool?
    private var reportedBadKeys: Set<String> = []
    private var pollTask: Task<Void, Never>?
    private var activationObserver: NSObjectProtocol?
    private static let logger = Logger(subsystem: "com.eightabyte.pane", category: "conflicts")

    /// Edge tiling exists from macOS 15 (Pitfall 12): gated on the OS version, never on key presence.
    init(
        store: any PreferencesStore, defaults: UserDefaults = .standard,
        osMajor: Int = ProcessInfo.processInfo.isOperatingSystemAtLeast(OperatingSystemVersion(majorVersion: 15, minorVersion: 0, patchVersion: 0))
            ? 15 : 14,
        readBackDelay: Duration = .seconds(1)
    ) {
        self.store = store
        self.defaults = defaults
        self.osMajor = osMajor
        self.readBackDelay = readBackDelay
        originals = Self.loadOriginals(defaults)
    }

    /// Polls now, every 2 s, and whenever Pane becomes active.
    func start() {
        poll()
        guard pollTask == nil else { return }
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(2))
                guard let self else { return }
                self.poll()
            }
        }
        activationObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.poll() }
        }
    }

    /// Reads every allow-listed key and updates the active set. Never writes.
    func poll() {
        store.synchronize()
        let values = Dictionary(uniqueKeysWithValues: ConflictPolicy.allKeys.map { ($0, store.value($0)) })
        let bad = Set(ConflictPolicy.badKeys(values: values))
        for key in bad.subtracting(reportedBadKeys) {
            Self.logger.error("\(key, privacy: .public) is not a boolean; treated as off and never written")
        }
        reportedBadKeys = bad
        active = ConflictPolicy.active(values: values, osMajor: osMajor)
        let stageManager = active.contains(.stageManager)
        if stageManager != reportedStageManager {
            reportedStageManager = stageManager
            setStageManagerPaused(stageManager)
        }
    }

    /// Turn Off (a menu line or an alert): records originals not yet recorded, writes false, and about 1 s later reads
    /// the values back. A key holding a non-boolean is never written over.
    func turnOff(_ conflict: Conflict) async {
        store.synchronize()
        let writes = ConflictPolicy.turnOffWrites(for: conflict)
        let keys = ConflictPolicy.keys(for: conflict).filter { store.value($0) != .other }
        for key in keys where originals[key] == nil { originals[key] = store.value(key) }
        saveOriginals()
        for key in keys { store.set(key, writes[key]) }
        try? await Task.sleep(for: readBackDelay)
        store.synchronize()
        if keys.contains(where: { store.value($0) != writes[$0].map(PrefValue.bool) }) {
            Self.logger.error("turning off \(conflict.rawValue, privacy: .public) did not take; opening Desktop & Dock")
            openSettings(Self.desktopAndDock)
            post(.turnOffFailed(conflict))
        }
        poll()
    }

    /// Restore macOS Window Settings is enabled only with something recorded.
    var canRestore: Bool { !originals.isEmpty }

    /// Writes every recorded original back (deleting keys that were absent), forgets them and shows N8 (D-21). The
    /// features this turns back on raise no alert.
    func restore() {
        guard canRestore else { return }
        for (key, value) in ConflictPolicy.restoreWrites(originals: originals).sorted(by: { $0.key < $1.key }) { store.set(key, value) }
        originals = [:]
        defaults.removeObject(forKey: Self.originalsKey)
        post(.settingsRestored)
        poll()
    }

    private func saveOriginals() {
        do {
            defaults.set(try JSONEncoder().encode(originals), forKey: Self.originalsKey)
        } catch {
            Self.logger.error("could not record the original settings: \(String(describing: error), privacy: .public)")
        }
    }

    /// The plist is user-writable (T-03-45): only allow-listed keys holding a boolean or absent survive, so a crafted
    /// value cannot make Restore write any other key.
    private static func loadOriginals(_ defaults: UserDefaults) -> [String: PrefValue] {
        guard let data = defaults.data(forKey: originalsKey) else { return [:] }
        let decoded: [String: PrefValue]
        do {
            decoded = try JSONDecoder().decode([String: PrefValue].self, from: data)
        } catch {
            logger.error("dropped unreadable recorded originals: \(String(describing: error), privacy: .public)")
            return [:]
        }
        let kept = decoded.filter { ConflictPolicy.allKeys.contains($0.key) && $0.value != .other }
        if kept.count != decoded.count { logger.error("dropped \(decoded.count - kept.count, privacy: .public) invalid recorded originals") }
        return kept
    }
}

import Foundation
import KeyboardShortcuts
import TransomEngine
import TransomPrivate
import os

/// `takeover.originals` in UserDefaults: each taken hotkey's enabled state from before the first disable, keyed by ID.
final class UserDefaultsTakeoverStore: TakeoverStore {
    static let key = "takeover.originals"
    private let defaults: UserDefaults

    init(defaults: UserDefaults) { self.defaults = defaults }

    var originals: [Int32: Bool]? {
        guard let raw = defaults.object(forKey: Self.key) else { return nil }
        guard let stored = raw as? [String: Bool] else {
            Logger(subsystem: "com.eightabyte.transom", category: "missionControl").error("takeover originals unreadable; ignored")
            return nil
        }
        // Only the takeover's own IDs: the value decides which system shortcuts get switched on (trust boundary).
        return Dictionary(uniqueKeysWithValues: stored.compactMap { key, value in
            Int32(key).flatMap { TakeoverPolicy.candidateIDs.contains($0) ? ($0, value) : nil }
        })
    }

    func setOriginals(_ originals: [Int32: Bool]) {
        defaults.set(Dictionary(uniqueKeysWithValues: originals.map { (String($0.key), $0.value) }), forKey: Self.key)
        defaults.synchronize()  // out of process before the first disable: a crash right after must still find them
    }

    func clearOriginals() { defaults.removeObject(forKey: Self.key) }
}

/// The Mission Control takeover (OVER-02, D-05, D-07): disables macOS's Mission Control shortcuts and catches their
/// chords as Carbon hotkeys, so they reach `onTrigger`. The only writer of symbolic-hotkey state. Every disable is
/// preceded by stored originals and followed by a read-back (TakeoverPolicy).
@MainActor final class MissionControlTakeover {
    enum State: Equatable {
        case off, on(keys: [Int32]), liftedForZoom, offAfterCrash, offApplyFailed, unavailable
    }

    enum LiftReason { case toggleOff, zoomOff, restoreSettings, quit }

    private(set) var state: State = .off
    /// A taken chord was pressed.
    var onTrigger: () -> Void = {}

    private let store: UserDefaultsTakeoverStore
    private var keyTasks: [Task<Void, Never>] = []
    private let log = Logger(subsystem: "com.eightabyte.transom", category: "missionControl")

    init(defaults: UserDefaults = .standard) {
        store = UserDefaultsTakeoverStore(defaults: defaults)
    }

    /// The stored originals (tests and the Debug line).
    var storedOriginals: [Int32: Bool]? { store.originals }

    /// Stores originals, disables, reads back; only then registers the freed chords. A read-back still showing a taken
    /// hotkey on restores the originals and leaves the takeover off.
    @discardableResult func apply() -> Bool {
        if case .on = state { return true }
        guard Capabilities.isAvailable(.symbolicHotKeys) else {
            state = .unavailable
            log.error("takeover unavailable: SymbolicHotKeys missing")
            return false
        }
        let ids = TakeoverPolicy.takenIDs(
            hotkey32Enabled: SymbolicHotKeys.isEnabled(SymbolicHotKeys.missionControl) == true,
            extra: TakeoverPolicy.spikeExtra.filter { SymbolicHotKeys.isEnabled($0) == true })
        let current = Dictionary(uniqueKeysWithValues: ids.map { ($0, SymbolicHotKeys.isEnabled($0) ?? true) })
        // Read before the disable: each chord is registered as it was.
        let shortcuts = Set(ids.compactMap(Self.shortcut))
        for step in TakeoverPolicy.apply(ids: ids, current: current, store: store) {
            switch step {
            case .storeOriginals(let originals): store.setOriginals(originals)
            case .disable(let id): SymbolicHotKeys.setEnabled(id, false)
            }
        }
        switch TakeoverPolicy.afterReadBack(readBack(ids), store: store) {
        case .applied:
            state = .on(keys: ids)
            keyTasks = shortcuts.map { shortcut in
                let events = KeyboardShortcuts.events(for: shortcut)  // registers here, not when the task first runs
                return Task { [weak self] in
                    for await event in events where event == .keyDown { self?.triggered() }
                }
            }
            log.info("takeover on: disabled \(Self.describe(ids), privacy: .public)")
            return true
        case .applyFailed(let originals):
            let state = readBack(ids)
            restore(originals)
            self.state = .offApplyFailed
            log.error("takeover apply failed: read-back \(String(describing: state), privacy: .public); originals restored")
            return false
        }
    }

    /// Unregisters the chords first, then restores the stored originals, reads back and clears the store.
    func lift(reason: LiftReason) {
        keyTasks.forEach { $0.cancel() }  // KeyboardShortcuts unregisters on its next main-actor turn; `state` gates triggers until then
        keyTasks = []
        state = reason == .zoomOff ? .liftedForZoom : .off
        let originals = TakeoverPolicy.lift(store: store)
        guard !originals.isEmpty else { return }
        restore(originals)
        log.info("\(reason == .zoomOff ? "takeover lifted: zoom off" : "takeover off: restored originals", privacy: .public)")
    }

    private func triggered() {
        guard case .on = state else { return }
        onTrigger()
    }

    /// Restores `originals`, reads back and clears the store when all match; a mismatch keeps them for the next launch.
    @discardableResult private func restore(_ originals: [Int32: Bool]) -> Bool {
        for (id, enabled) in originals { SymbolicHotKeys.setEnabled(id, enabled) }
        let readBack = readBack(Array(originals.keys))
        guard TakeoverPolicy.afterRestore(readBack, store: store) else {
            log.error("takeover restore read-back \(String(describing: readBack), privacy: .public) differs from originals; kept for the next launch")
            return false
        }
        return true
    }

    private func readBack(_ ids: [Int32]) -> [Int32: Bool?] {
        Dictionary(uniqueKeysWithValues: ids.map { ($0, SymbolicHotKeys.isEnabled($0)) })
    }

    /// The hotkey's live chord as a Carbon shortcut; the Mission Control key falls back to key code 160.
    private static func shortcut(_ id: Int32) -> KeyboardShortcuts.Shortcut? {
        if let value = SymbolicHotKeys.value(id) {
            return KeyboardShortcuts.Shortcut(carbonKeyCode: Int(value.keyCode), carbonModifiers: TakeoverKeys.carbonModifiers(nx: value.modifiers))
        }
        return id == SymbolicHotKeys.missionControlKey ? KeyboardShortcuts.Shortcut(carbonKeyCode: TakeoverKeys.missionControlKeyCode) : nil
    }

    private static func describe(_ ids: [Int32]) -> String { ids.map(String.init).joined(separator: ", ") }
}

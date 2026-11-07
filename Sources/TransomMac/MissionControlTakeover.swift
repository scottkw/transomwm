import Foundation
import KeyboardShortcuts
import Observation
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
        // Only canonical keys ("32", never "032" or "+32"), so no two keys parse to one ID (WR-01).
        let pairs = stored.compactMap { key, value in
            Int32(key).flatMap { String($0) == key && TakeoverPolicy.candidateIDs.contains($0) ? ($0, value) : nil }
        }
        if pairs.count != stored.count {
            Logger(subsystem: "com.eightabyte.transom", category: "missionControl").error("takeover originals: ignored \(stored.count - pairs.count) unknown or non-canonical keys")
        }
        return Dictionary(uniqueKeysWithValues: pairs)
    }

    func setOriginals(_ originals: [Int32: Bool]) {
        defaults.set(Dictionary(uniqueKeysWithValues: originals.map { (String($0.key), $0.value) }), forKey: Self.key)
        defaults.synchronize()  // out of process before the first disable: a crash right after must still find them
    }

    func clearOriginals() { defaults.removeObject(forKey: Self.key) }
}

/// Every symbolic-hotkey and Carbon-hotkey call the takeover makes. Host tests inject a fake, so no test can change the
/// user's real Mission Control shortcuts or register a hotkey.
@MainActor protocol HotKeyBackend {
    var isAvailable: Bool { get }
    func isEnabled(_ id: Int32) -> Bool?
    func setEnabled(_ id: Int32, _ enabled: Bool)
    func value(_ id: Int32) -> SymbolicHotKeys.Value?
    /// Registers `shortcut` as a Carbon hotkey right away; cancelling the stream's task unregisters it.
    func events(for shortcut: KeyboardShortcuts.Shortcut) -> AsyncStream<KeyboardShortcuts.EventType>
}

/// SkyLight's symbolic hotkeys and KeyboardShortcuts' Carbon hotkeys (the app's only backend).
struct LiveHotKeyBackend: HotKeyBackend {
    var isAvailable: Bool { Capabilities.isAvailable(.symbolicHotKeys) }
    func isEnabled(_ id: Int32) -> Bool? { SymbolicHotKeys.isEnabled(id) }
    func setEnabled(_ id: Int32, _ enabled: Bool) { SymbolicHotKeys.setEnabled(id, enabled) }
    func value(_ id: Int32) -> SymbolicHotKeys.Value? { SymbolicHotKeys.value(id) }
    func events(for shortcut: KeyboardShortcuts.Shortcut) -> AsyncStream<KeyboardShortcuts.EventType> { KeyboardShortcuts.events(for: shortcut) }
}

/// The Mission Control takeover (OVER-02, D-05, D-07): disables macOS's Mission Control shortcuts and catches their
/// chords as Carbon hotkeys, so they reach `onTrigger`. The only writer of symbolic-hotkey state. Every disable is
/// preceded by stored originals and followed by a read-back (TakeoverPolicy). Observable so Settings ▸ Zoom & Gestures
/// and the Arranging tab's Restore button follow `state`.
@Observable @MainActor final class MissionControlTakeover {
    enum State: Equatable {
        case off, on(keys: [Int32]), liftedForZoom, offAfterCrash, offApplyFailed, unavailable
    }

    enum LiftReason { case toggleOff, zoomOff, restoreSettings, quit }

    /// Replace Mission Control (off by default, D-06). Only the Settings toggle (09-07) and tests write it; no URL.
    static let enabledKey = "takeover.enabled"
    /// The explanation alert was confirmed once (Surface 5); saved only on confirm.
    static let explainedKey = "takeover.explained"

    private(set) var state: State = .off
    /// The canary tripped at launch and N10 has not shown for it yet (06-11 posts it, then calls `crashNoticeShown`).
    private(set) var pendingCrashNotice = false
    /// A taken chord was pressed (after the drift check).
    @ObservationIgnored var onTrigger: () -> Void = {}
    /// Queues a toast (N10, N11); set by ArrangeController.
    @ObservationIgnored var post: (Notice) -> Void = { _ in }
    /// A VoiceOver announcement; set by ArrangeController.
    @ObservationIgnored var announce: (String) -> Void = { _ in }

    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let backend: any HotKeyBackend
    @ObservationIgnored private let store: UserDefaultsTakeoverStore
    @ObservationIgnored private let canary: MissionControlCanary
    private var zoomOn: Bool
    @ObservationIgnored private var keyTasks: [Task<Void, Never>] = []
    @ObservationIgnored private let log = Logger(subsystem: "com.eightabyte.transom", category: "missionControl")

    init(defaults: UserDefaults = .standard, backend: any HotKeyBackend = LiveHotKeyBackend(), zoomOn: Bool) {
        self.defaults = defaults
        self.backend = backend
        self.zoomOn = zoomOn
        store = UserDefaultsTakeoverStore(defaults: defaults)
        canary = MissionControlCanary(defaults: defaults)
    }

    var preferenceOn: Bool { defaults.bool(forKey: Self.enabledKey) }
    var isOn: Bool { if case .on = state { true } else { false } }
    /// The private symbols resolve (the Settings toggle is disabled otherwise).
    var isAvailable: Bool { backend.isAvailable }

    /// OVER-03, before the Arranger starts: stored originals mean the last run did not lift, so they are restored
    /// first; then a tripped canary keeps the takeover off, otherwise the preference, capability and zoom decide.
    func launchRestore() {
        let actions = TakeoverPolicy.launch(
            store: store, canaryTripped: canary.isTripped(), crashNoticed: canary.noticed, preferenceOn: preferenceOn, zoomOn: zoomOn,
            available: backend.isAvailable)
        for action in actions {
            switch action {
            case .restore(let originals):
                if restore(originals) {
                    log.notice("restored originals from last run (unclean exit)")
                } else {
                    log.error("Mission Control shortcuts still off after the launch restore; Restore macOS Window Settings retries it")
                }
            case .stayOff: state = .offAfterCrash
            case .queueCrashNotice: pendingCrashNotice = true
            case .off: state = .off
            case .unavailable: state = .unavailable
            case .liftedForZoom: state = .liftedForZoom
            case .apply: apply()
            }
        }
    }

    /// The preference: on clears a tripped canary and applies (or waits for zoom); off lifts.
    func setPreference(_ on: Bool) {
        defaults.set(on, forKey: Self.enabledKey)
        guard on else { return lift(reason: .toggleOff) }
        canary.turnBackOn()
        pendingCrashNotice = false
        if zoomOn { apply() } else { state = .liftedForZoom }
    }

    /// The Settings toggle (Surface 5, D-04): on turns off at once; off turns on after the one-time explanation, unless it was confirmed
    /// before or a crash turned the takeover off. `explain` shows the alert and answers whether the user confirmed.
    func choose(explain: (_ answered: @escaping (Bool) -> Void) -> Void) {
        if isOn {
            setPreference(false)
            return announce(OverviewCopy.takeoverOffAnnouncement)
        }
        guard defaults.bool(forKey: Self.explainedKey) || state == .offAfterCrash else {
            return explain { [weak self] confirmed in
                guard confirmed, let self else { return }
                self.defaults.set(true, forKey: Self.explainedKey)
                self.turnOn()
            }
        }
        turnOn()
    }

    private func turnOn() {
        setPreference(true)
        if isOn { announce(OverviewCopy.takeoverOnAnnouncement) }
    }

    /// What macOS has for Mission Control (hotkey 32) right now: the alert's {Keys}.
    var currentChord: OverviewCopy.Chord {
        backend.isEnabled(SymbolicHotKeys.missionControl) == true ? chord() : .off
    }

    /// Debug S5.
    var debugLine: OverviewCopy.TakeoverLine {
        guard backend.isAvailable else { return .unavailable }  // the policy reports it only with the preference on
        return switch state {
        case .off: .off
        case .on(let keys): .on(keys.contains(SymbolicHotKeys.missionControl) ? chord() : .off)
        case .liftedForZoom: .liftedForZoom
        case .offAfterCrash: .offAfterCrash
        case .offApplyFailed: .offApplyFailed
        case .unavailable: .unavailable
        }
    }

    /// Hotkey 32's chord: the macOS default ⌃↑, or the user's in glyphs. No value reads as the default.
    private func chord() -> OverviewCopy.Chord {
        guard let value = backend.value(SymbolicHotKeys.missionControl) else { return .standard }
        let carbon = TakeoverKeys.carbonModifiers(nx: value.modifiers)
        if value.keyCode == 126, carbon == 0x1000 { return .standard }
        return .custom(KeyboardShortcuts.Shortcut(carbonKeyCode: Int(value.keyCode), carbonModifiers: carbon).description)
    }

    /// N10 once, after the launch's crash notices (N2/N3) so it queues behind them.
    func postCrashNotice() {
        guard pendingCrashNotice else { return }
        post(.takeoverCrashed)
        crashNoticeShown()
    }

    func crashNoticeShown() {
        pendingCrashNotice = false
        canary.markNoticed()
    }

    /// Zoom off lifts the takeover (the preference stays); zoom on re-applies it silently when the preference is on.
    func zoomChanged(on: Bool) {
        zoomOn = on
        if !on {
            if case .on = state { lift(reason: .zoomOff) }
        } else if state == .liftedForZoom, preferenceOn {
            apply()
        }
    }

    /// A taken hotkey found enabled again (System Settings, A11) is disabled again; the stored originals stay.
    func checkDrift() {
        guard case .on(let keys) = state else { return }
        let drifted = TakeoverPolicy.drift(taken: keys, enabledNow: Dictionary(uniqueKeysWithValues: keys.map { ($0, backend.isEnabled($0) ?? false) }))
        guard !drifted.isEmpty else { return }
        for id in drifted { backend.setEnabled(id, false) }
        log.info("takeover drift: disabled \(Self.describe(drifted), privacy: .public) again")
    }

    /// Restore macOS Window Settings with the takeover off (WR-02): retries a launch or lift restore macOS refused, so
    /// the shortcuts need not wait for the next launch.
    func retryRestore() {
        guard !isOn, let originals = store.originals, !originals.isEmpty else { return }
        if restore(originals) { log.notice("takeover originals restored on retry") }
    }

    /// The stored originals (tests and the Debug line).
    var storedOriginals: [Int32: Bool]? { store.originals }

    /// Stores originals, disables, reads back; only then registers the freed chords. A read-back still showing a taken
    /// hotkey on restores the originals and leaves the takeover off.
    @discardableResult func apply() -> Bool {
        if case .on = state { return true }
        guard backend.isAvailable else {
            state = .unavailable
            log.error("takeover unavailable: SymbolicHotKeys missing")
            return false
        }
        let ids = TakeoverPolicy.takenIDs(
            hotkey32Enabled: backend.isEnabled(SymbolicHotKeys.missionControl) == true,
            extra: TakeoverPolicy.spikeExtra.filter { backend.isEnabled($0) == true })
        let current = Dictionary(uniqueKeysWithValues: ids.map { ($0, backend.isEnabled($0) ?? true) })
        // Read before the disable: each chord is registered as it was.
        let shortcuts = Set(ids.compactMap(shortcut))
        for step in TakeoverPolicy.apply(ids: ids, current: current, store: store) {
            switch step {
            case .storeOriginals(let originals): store.setOriginals(originals)
            case .disable(let id): backend.setEnabled(id, false)
            }
        }
        switch TakeoverPolicy.afterReadBack(readBack(ids), store: store) {
        case .applied:
            state = .on(keys: ids)
            canary.arm()
            keyTasks = shortcuts.map { shortcut in
                let events = backend.events(for: shortcut)  // registers here, not when the task first runs
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
            defaults.set(false, forKey: Self.enabledKey)  // WR-03: Settings can turn it on again; N11 does not repeat every launch
            log.error("takeover apply failed: read-back \(String(describing: state), privacy: .public); originals restored")
            post(.takeoverApplyFailed)
            return false
        }
    }

    /// Unregisters the chords first, then restores the stored originals, reads back and clears the store.
    func lift(reason: LiftReason) {
        keyTasks.forEach { $0.cancel() }  // KeyboardShortcuts unregisters on its next main-actor turn; `state` gates triggers until then
        keyTasks = []
        if case .on = state { canary.clear() }  // a tripped canary stays until the user turns the takeover on again
        state = reason == .zoomOff ? .liftedForZoom : .off
        let originals = TakeoverPolicy.lift(store: store)
        guard !originals.isEmpty else { return }
        restore(originals)
        log.info("\(reason == .zoomOff ? "takeover lifted: zoom off" : "takeover off: restored originals", privacy: .public)")
    }

    private func triggered() {
        guard case .on = state else { return }
        checkDrift()
        onTrigger()
    }

    /// Restores `originals`, reads back and clears the store when all match; a mismatch keeps them for the next launch.
    @discardableResult private func restore(_ originals: [Int32: Bool]) -> Bool {
        for (id, enabled) in originals { backend.setEnabled(id, enabled) }
        let readBack = readBack(Array(originals.keys))
        guard TakeoverPolicy.afterRestore(readBack, store: store) else {
            log.error("takeover restore read-back \(String(describing: readBack), privacy: .public) differs from originals; kept for the next launch")
            return false
        }
        return true
    }

    private func readBack(_ ids: [Int32]) -> [Int32: Bool?] {
        Dictionary(uniqueKeysWithValues: ids.map { ($0, backend.isEnabled($0)) })
    }

    /// The hotkey's live chord as a Carbon shortcut; the Mission Control key falls back to key code 160.
    private func shortcut(_ id: Int32) -> KeyboardShortcuts.Shortcut? {
        if let value = backend.value(id) {
            return KeyboardShortcuts.Shortcut(carbonKeyCode: Int(value.keyCode), carbonModifiers: TakeoverKeys.carbonModifiers(nx: value.modifiers))
        }
        return id == SymbolicHotKeys.missionControlKey ? KeyboardShortcuts.Shortcut(carbonKeyCode: TakeoverKeys.missionControlKeyCode) : nil
    }

    private static func describe(_ ids: [Int32]) -> String { ids.map(String.init).joined(separator: ", ") }
}

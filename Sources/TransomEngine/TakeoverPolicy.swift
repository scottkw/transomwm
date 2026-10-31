import Foundation

/// Where the takeover keeps each taken hotkey's enabled state from before the first disable (`takeover.originals`).
/// Present means the takeover is on, or the last run did not lift it (D-07).
public protocol TakeoverStore: AnyObject {
    var originals: [Int32: Bool]? { get }
    func setOriginals(_ originals: [Int32: Bool])
    func clearOriginals()
}

/// The Mission Control takeover's decisions (OVER-02, OVER-03, D-07, RESEARCH Pattern 4). The shell executes them
/// against SymbolicHotKeys; disabling a symbolic hotkey is WindowServer session state that outlives the process, so the
/// order is fixed and originals are never overwritten.
///
/// | Event   | Decision                                                                                          |
/// |---------|---------------------------------------------------------------------------------------------------|
/// | apply   | store current states only for IDs not stored yet (never overwrite) → disable each taken ID        |
/// | read-back | every taken ID disabled → applied (then Carbon keys, canary); any still on or unreadable → applyFailed |
/// | lift    | restore the stored originals ([] when none) → read back → clear the store only if all match      |
/// | launch  | stored originals → restore first, whatever follows (OVER-03); then canary tripped → stay off, N10 once; preference off → off; capability off → unavailable; zoom off → lifted for zoom; else apply |
/// | trigger | overview open → dismiss; can open → open; CoreDock → macOS Mission Control; else refuse (beep)   |
/// | drift   | a taken ID found enabled again → disable it again, stored originals untouched                     |
public enum TakeoverPolicy {
    public enum LaunchAction: Equatable, Sendable {
        /// Restore, read back, clear the store when all match.
        case restore([Int32: Bool])
        case stayOff, queueCrashNotice, off, unavailable, liftedForZoom, apply
    }

    public enum TriggerAction: Equatable, Sendable {
        case dismiss, open, missionControl, refuse
    }

    public static func launch(
        store: some TakeoverStore, canaryTripped: Bool, crashNoticed: Bool, preferenceOn: Bool, zoomOn: Bool, available: Bool
    ) -> [LaunchAction] {
        let restore: [LaunchAction] = store.originals.map { [.restore($0)] } ?? []
        if canaryTripped { return restore + [.stayOff] + (crashNoticed ? [] : [.queueCrashNotice]) }
        guard preferenceOn else { return restore + [.off] }
        guard available else { return restore + [.unavailable] }
        return restore + [zoomOn ? .apply : .liftedForZoom]
    }

    public static func trigger(overviewOpen: Bool, canOpen: Bool, coreDockAvailable: Bool) -> TriggerAction {
        overviewOpen ? .dismiss : canOpen ? .open : coreDockAvailable ? .missionControl : .refuse
    }

    /// The taken IDs System Settings (or anything else) switched back on while the takeover was on.
    public static func drift(taken: [Int32], enabledNow: [Int32: Bool]) -> [Int32] {
        taken.filter { enabledNow[$0] == true }
    }

    public enum ApplyStep: Equatable, Sendable {
        case storeOriginals([Int32: Bool])
        case disable(Int32)
    }

    public enum ApplyOutcome: Equatable, Sendable {
        case applied
        /// Restore these stored originals and keep the takeover off (N11).
        case applyFailed(restore: [Int32: Bool])
    }

    /// IDs the takeover may take besides 32 and 108 (D-08: 33, 35, 79-82, 115 and 117 never).
    static let allowedExtra: Set<Int32> = [34, 113]
    /// 06-SPIKE "Takeover ID set": ⇧F3 (113) still opened Mission Control with 32 and 108 off; ⌃⇧↑ (34) did not.
    public static let spikeExtra: [Int32] = [113]
    /// Every ID a stored original may name; anything else in UserDefaults is ignored.
    public static let candidateIDs: Set<Int32> = allowedExtra.union([32, 108])

    /// 32 (⌃↑) only while the user has it on (nothing to take or restore otherwise), 108 (the Mission Control key)
    /// always, plus the allowed extras.
    public static func takenIDs(hotkey32Enabled: Bool, extra: [Int32]) -> [Int32] {
        Set((hotkey32Enabled ? [32] : []) + [108] + extra.filter(allowedExtra.contains)).sorted()
    }

    /// The steps that take `ids`, given their `current` enabled states.
    public static func apply(ids: [Int32], current: [Int32: Bool], store: some TakeoverStore) -> [ApplyStep] {
        let stored = store.originals ?? [:]
        // A second apply after a failed restore must not record "disabled" as an original (T-06-27).
        let missing = ids.filter { stored[$0] == nil }.reduce(into: stored) { $0[$1] = current[$1] ?? true }
        return (missing == stored ? [] : [.storeOriginals(missing)]) + ids.map { .disable($0) }
    }

    /// `readBack` maps each taken ID to its enabled state after the disable (nil: unreadable, counted as on).
    public static func afterReadBack(_ readBack: [Int32: Bool?], store: some TakeoverStore) -> ApplyOutcome {
        readBack.values.allSatisfy { $0 == false } ? .applied : .applyFailed(restore: store.originals ?? [:])
    }

    /// What a lift restores.
    public static func lift(store: some TakeoverStore) -> [Int32: Bool] { store.originals ?? [:] }

    /// After restoring: clears the store when every ID read back its original, and says so. Otherwise the originals stay
    /// for the next launch's restore.
    @discardableResult
    public static func afterRestore(_ readBack: [Int32: Bool?], store: some TakeoverStore) -> Bool {
        let originals = store.originals ?? [:]
        guard originals.allSatisfy({ readBack[$0.key] == $0.value }) else { return false }
        store.clearOriginals()
        return true
    }
}

/// The freed chords as Carbon hotkeys.
public enum TakeoverKeys {
    /// The Mission Control key (F3 on Apple keyboards).
    public static let missionControlKeyCode = 160

    /// NX device-independent flags → Carbon modifiers (⇧ 0x200, ⌃ 0x1000, ⌥ 0x800, ⌘ 0x100); fn (0x800000) is dropped.
    public static func carbonModifiers(nx: UInt32) -> Int {
        [(0x20000, 0x200), (0x40000, 0x1000), (0x80000, 0x800), (0x100000, 0x100)].reduce(0) { carbon, pair in
            nx & UInt32(pair.0) != 0 ? carbon | pair.1 : carbon
        }
    }
}

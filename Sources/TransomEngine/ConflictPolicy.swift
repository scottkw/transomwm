/// One com.apple.WindowManager value as read: missing, a CFBoolean, or anything else.
public enum PrefValue: Equatable, Codable, Sendable {
    case absent, bool(Bool), other
}

/// A macOS feature that fights Transom, in the fixed order of the menu lines.
public enum Conflict: String, CaseIterable, Codable, Sendable {
    case stageManager, edgeTiling, clickWallpaper
}

/// What the conflicting macOS features are set to and what Transom writes to turn them off or back (SAFE-04, RESEARCH
/// Pattern 13). Pure: the shell reads and writes the values. Only the keys below are ever written, and only booleans.
/// `EnableTilingOptionAccelerator` (hold ⌥ to tile) is left as the user set it (D-05).
public enum ConflictPolicy {
    public static let domain = "com.apple.WindowManager"

    public static func keys(for conflict: Conflict) -> [String] {
        switch conflict {
        case .stageManager: ["GloballyEnabled"]
        case .edgeTiling: ["EnableTilingByEdgeDrag", "EnableTopTilingByEdgeDrag"]
        case .clickWallpaper: ["EnableStandardClickToShowDesktop"]
        }
    }

    /// Every key Transom reads, writes or restores: the allow-list (T-03-44, T-03-45).
    public static let allKeys: [String] = Conflict.allCases.flatMap(keys(for:))

    /// The features that are on. A missing key is `.absent`. Stage Manager is off when absent; edge tiling (macOS 15+
    /// only, Pitfall 12) and click wallpaper are on when absent, the system default (A10). `.other` counts as off.
    public static func active(values: [String: PrefValue], osMajor: Int) -> Set<Conflict> {
        func value(_ key: String) -> PrefValue { values[key] ?? .absent }
        func onWhenAbsent(_ key: String) -> Bool { [.bool(true), .absent].contains(value(key)) }
        var on: Set<Conflict> = []
        if value("GloballyEnabled") == .bool(true) { on.insert(.stageManager) }
        if osMajor >= 15, keys(for: .edgeTiling).contains(where: onWhenAbsent) { on.insert(.edgeTiling) }
        if onWhenAbsent("EnableStandardClickToShowDesktop") { on.insert(.clickWallpaper) }
        return on
    }

    /// Allow-listed keys holding something that is not a boolean, in key-table order (logged, never written over).
    public static func badKeys(values: [String: PrefValue]) -> [String] {
        allKeys.filter { values[$0] == .other }
    }

    /// Restore: each recorded boolean back, and nil (delete the key, so the system default applies) for a key that was
    /// absent. Keys outside the allow-list and `.other` are never written.
    public static func restoreWrites(originals: [String: PrefValue]) -> [String: Bool?] {
        var writes: [String: Bool?] = [:]
        for (key, value) in originals where allKeys.contains(key) {
            switch value {
            case .bool(let on): writes[key] = .some(on)
            case .absent: writes[key] = .some(nil)
            case .other: break
            }
        }
        return writes
    }

    /// One alert per on-episode (D-19): a feature on now that was off at the last poll (or this is the first), unless
    /// the user said Not Now or Transom itself turned it back on. In the fixed order.
    public static func alertsDue(active: Set<Conflict>, previous: Set<Conflict>, notNow: Set<Conflict>, restoredByTransom: Set<Conflict>)
        -> [Conflict]
    {
        Conflict.allCases.filter { active.contains($0) && !previous.contains($0) && !notNow.contains($0) && !restoredByTransom.contains($0) }
    }

    /// Turn Off: false to each of the feature's keys.
    public static func turnOffWrites(for conflict: Conflict) -> [String: Bool] {
        Dictionary(uniqueKeysWithValues: keys(for: conflict).map { ($0, false) })
    }
}

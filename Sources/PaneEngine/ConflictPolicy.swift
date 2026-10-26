/// One com.apple.WindowManager value as read: missing, a CFBoolean, or anything else.
public enum PrefValue: Equatable, Codable, Sendable {
    case absent, bool(Bool), other
}

/// A macOS feature that fights Pane, in the fixed order of the menu lines.
public enum Conflict: String, CaseIterable, Codable, Sendable {
    case stageManager, edgeTiling, clickWallpaper
}

public enum ConflictPolicy {
    public static let domain = "com.apple.WindowManager"
    public static func keys(for conflict: Conflict) -> [String] { [] }
    public static func active(values: [String: PrefValue], osMajor: Int) -> Set<Conflict> { [] }
    public static func badKeys(values: [String: PrefValue]) -> [String] { [] }
    public static func turnOffWrites(for conflict: Conflict) -> [String: Bool] { [:] }
}

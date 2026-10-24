import PaneEngine

/// Status-menu copy from the UI-SPEC Copywriting Contract. Pure strings, no AppKit types.
nonisolated public enum MenuCopy {
    public static let maxAppNameLength = 32

    /// "No windows to track", "Tracking 1 window in 1 app", "Tracking 12 windows in 5 apps".
    public static func header(windows: Int, apps: Int) -> String {
        if windows == 0 { return "No windows to track" }
        return "Tracking \(count(windows, "window")) in \(count(apps, "app"))"
    }

    /// nil at 0, else "1 app not responding" / "N apps not responding".
    public static func degradedLine(count apps: Int) -> String? {
        apps == 0 ? nil : "\(count(apps, "app")) not responding"
    }

    public static func capabilityItem(windowIDLookupAvailable: Bool) -> String {
        windowIDLookupAvailable ? "Window ID lookup: available" : "Window ID lookup: off, matching by frame"
    }

    /// Names over 32 graphemes become their first 32 plus "…", so menu width stays bounded.
    public static func truncatedAppName(_ name: String) -> String {
        name.count <= maxAppNameLength ? name : name.prefix(maxAppNameLength) + "\u{2026}"
    }

    public static func permissionHeader(_ phase: PermissionPhase) -> String? { nil }

    public static func permissionItem(stale: Bool) -> String { "" }

    public static func resetFailedBody(code: Int32, appName: String) -> String { "" }

    private static func count(_ n: Int, _ noun: String) -> String {
        n == 1 ? "1 \(noun)" : "\(n) \(noun)s"
    }
}

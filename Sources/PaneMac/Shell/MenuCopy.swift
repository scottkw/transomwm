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

    /// Item 1 of the menu while not ready; nil when ready (the tracking header shows instead).
    public static func permissionHeader(_ phase: PermissionPhase) -> String? {
        switch phase {
        case .ready: nil
        case .notTrusted, .waitingForGrant: "Accessibility access needed"
        case .probing: "Checking Accessibility access\u{2026}"
        // A reset only starts from a stale form.
        case .staleTrustedButFailing, .resetting: "Accessibility access isn't working"
        }
    }

    public static func permissionItem(stale: Bool) -> String {
        stale ? "Fix Accessibility Access\u{2026}" : "Grant Accessibility Access\u{2026}"
    }

    /// Callout E body (UI-SPEC error state).
    public static func resetFailedBody(code: Int32, appName: String) -> String {
        "tccutil stopped with code \(code). In System Settings \u{25B8} Privacy & Security \u{25B8} Accessibility, "
            + "select \u{201C}\(appName)\u{201D}, click the minus button, then turn \(appName) on again."
    }

    /// Pass the name through `truncatedAppName` first.
    public static func dontArrange(appName: String) -> String { "Don't Arrange \u{201C}\(appName)\u{201D}" }
    public static let dontArrangeFallback = "Don't Arrange Frontmost App"
    public static let noExclusions = "No apps excluded"

    /// Nudge copy (Debug submenu, all builds).
    public static let nudgeItem = "Nudge Focused Window"
    public static let nudgeExcluded = "Nudge Focused Window (app excluded)"
    public static let nudgeNoWindow = "Nudge Focused Window (no window)"

    /// Freeze-test copy (Debug submenu, Surface 4). Pass names through `truncatedAppName` first.
    public static func freezeItem(appName: String) -> String { "Freeze \u{201C}\(appName)\u{201D} for 10 Seconds\u{2026}" }
    public static let freezeNotAllowed = "Freeze Frontmost App (not allowed)"
    public static func resumeItem(appName: String) -> String { "Resume \u{201C}\(appName)\u{201D} Now" }
    public static func freezeAlertMessage(appName: String) -> String { "Freeze \u{201C}\(appName)\u{201D} for 10 seconds?" }
    public static func freezeAlertInfo(appName: String) -> String {
        "Pane will pause \(appName) to check that a frozen app can't stall it. \(appName) resumes by itself after "
            + "10 seconds, or choose Debug \u{25B8} Resume \u{201C}\(appName)\u{201D} Now."
    }

    private static func count(_ n: Int, _ noun: String) -> String {
        n == 1 ? "1 \(noun)" : "\(n) \(noun)s"
    }
}

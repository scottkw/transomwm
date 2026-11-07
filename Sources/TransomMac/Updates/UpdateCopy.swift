import TransomEngine

/// Settings ▸ Updates copy (09 UI-SPEC Surface 3). Pure strings, no AppKit types.
nonisolated public enum UpdateCopy {
    public static let checkForUpdates = "Check for Updates"
    public static let releaseNotes = "Release Notes"
    public static let automaticToggle = "Check for updates automatically"
    public static let automaticFooter =
        "Transom asks GitHub for the latest release when it opens and once a day. Nothing about you or your Mac is sent."

    /// "Transom 0.9.0 (1)".
    public static func versionLine(_ version: String, _ build: String) -> String { "Transom \(version) (\(build))" }

    /// Replaces the status line after a failed manual action.
    public static func errorLine(_ error: UpdateError) -> String {
        switch error {
        case .checkFailed: "Couldn't check for updates. Check your connection, then try again."
        }
    }

    /// The status line under the version; idle has none. `current` is the running version.
    public static func statusLine(_ status: UpdateStatus, current: String) -> String? {
        switch status {
        case .idle: nil
        case .checking: "Checking for updates\u{2026}"
        case .current(let version): "Transom \(version) is up to date."
        case .available(let release): "Transom \(release.version) is available. You have \(current)."
        }
    }
}

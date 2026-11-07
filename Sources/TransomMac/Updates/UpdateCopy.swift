import TransomEngine

/// Settings ▸ Updates copy (09 UI-SPEC Surface 3). Pure strings, no AppKit types.
nonisolated public enum UpdateCopy {
    public static let checkForUpdates = "Check for Updates"
    public static let releaseNotes = "Release Notes"

    /// "Transom 0.9.0 (1)".
    public static func versionLine(_ version: String, _ build: String) -> String { "Transom \(version) (\(build))" }

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

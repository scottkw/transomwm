import Foundation
import TransomEngine

/// Settings ▸ Updates copy (09 UI-SPEC Surface 3). Pure strings, no AppKit types.
nonisolated public enum UpdateCopy {
    public static let checkForUpdates = "Check for Updates"
    public static let releaseNotes = "Release Notes"
    public static let downloadAndOpen = "Download and Open"
    public static let copyCommand = "Copy Command"
    public static let quitTransom = "Quit Transom"
    public static let homebrewIntro = "Transom was installed with Homebrew. To update, run this in Terminal:"
    public static let homebrewCommand = "brew upgrade --cask transom"
    public static let automaticToggle = "Check for updates automatically"
    public static let automaticFooter =
        "Transom asks GitHub for the latest release when it opens and once a day. Nothing about you or your Mac is sent."

    /// Appended to the glyph's description and tooltip while the dot shows (Surface 3).
    public static let updateAvailableSuffix = ", update available"
    public static let copyBrewItem = "Copy \u{201C}brew upgrade --cask transom\u{201D}"
    public static let copyBrewTooltip = "Paste it in Terminal to update."
    /// The DMG install's menu item: opens Settings ▸ Updates and starts Download and Open.
    public static func updateTo(_ version: String) -> String { "Update to Transom \(version)\u{2026}" }
    /// The Homebrew install's disabled info line.
    public static func homebrewAvailable(_ version: String) -> String { "Transom \(version) is available" }

    /// The ⌥ Debug line: "Updates: {state}, last checked {HH:mm}" or "never".
    public static func debugLine(status: UpdateStatus, lastChecked: Date?) -> String {
        let state =
            switch status {
            case .idle: "idle"
            case .checking: "checking"
            case .current: "current"
            case .available(let release): "\(release.version) available"
            case .downloading(let release, _): "downloading \(release.version)"
            case .verifying(let release): "verifying \(release.version)"
            case .opened(let release): "\(release.version) opened"
            }
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        let time = lastChecked.map(formatter.string(from:))
        return "Updates: \(state), last checked \(time ?? "never")"
    }

    /// "Transom 0.9.0 (1)".
    public static func versionLine(_ version: String, _ build: String) -> String { "Transom \(version) (\(build))" }

    /// Replaces the status line after a failed manual action.
    public static func errorLine(_ error: UpdateError) -> String {
        switch error {
        case .checkFailed: "Couldn't check for updates. Check your connection, then try again."
        case .downloadFailed(let version): "Couldn't download Transom \(version). Check your connection, then try again."
        case .verifyFailed: "The download didn't pass the signature check, so Transom deleted it. Nothing was opened."
        case .openFailed: "Transom couldn't open the downloaded disk image. Try again."
        }
    }

    /// The status line under the version; idle has none. `current` is the running version.
    public static func statusLine(_ status: UpdateStatus, current: String) -> String? {
        switch status {
        case .idle: nil
        case .checking: "Checking for updates\u{2026}"
        case .current(let version): "Transom \(version) is up to date."
        case .available(let release): "Transom \(release.version) is available. You have \(current)."
        case .downloading(let release, let fraction):
            // The percentage is left out while the size is unknown.
            "Downloading Transom \(release.version)\u{2026}" + (fraction.map { " \(Int(($0 * 100).rounded()))%" } ?? "")
        case .verifying: "Checking the download's signature\u{2026}"
        case .opened(let release):
            "The Transom \(release.version) disk image is open. Quit Transom, then drag the new Transom to Applications and choose Replace."
        }
    }
}

import Foundation
import TransomEngine

/// Report a Problem… (09 UI-SPEC Surface 5, D-15): a prefilled GitHub issue built from versions, counts and capability
/// lines only. Never window titles, app names, bundle IDs, display names, paths or layout contents (T-09-36).
nonisolated public enum ReportProblem {
    public enum Accessibility: String, Sendable {
        case on
        case off
        case notWorking = "not working"
    }

    /// Strings and counts only; nothing here can hold a title or a bundle ID.
    public struct ReportDetails: Equatable, Sendable {
        var version: String
        var build: String
        var homebrew: Bool
        var macOSVersion: String
        var macOSBuild: String
        var appleSilicon: Bool
        var displays: Int
        var windows: Int
        var apps: Int
        var accessibility: Accessibility
        var screenRecording: Bool
        var zoom: Bool
        /// `GestureCopy.gesturesLine`.
        var gestures: String
        /// The Debug submenu's capability, Spaces, tap, takeover and CLI lines, verbatim.
        var lines: [String]
    }

    /// Reads only counts from the inventory; closed windows do not count, as in the menu header.
    public static func details(
        inventory: WindowInventory, version: String, build: String, homebrew: Bool, macOSVersion: String, macOSBuild: String,
        appleSilicon: Bool, accessibility: Accessibility, screenRecording: Bool, zoom: Bool, gestures: String, lines: [String]
    ) -> ReportDetails {
        let open = inventory.windows.filter { $0.state != .closed }
        return ReportDetails(
            version: version, build: build, homebrew: homebrew, macOSVersion: macOSVersion, macOSBuild: macOSBuild,
            appleSilicon: appleSilicon, displays: inventory.displays.count, windows: open.count,
            apps: Set(open.map(\.window.pid)).count, accessibility: accessibility, screenRecording: screenRecording, zoom: zoom,
            gestures: gestures, lines: lines)
    }

    /// The lines under "### Details", also put on the clipboard.
    public static func detailsBlock(_ details: ReportDetails) -> String {
        let onOff = { (on: Bool) -> String in on ? "on" : "off" }
        return ([
            "Transom \(details.version) (\(details.build)), installed \(details.homebrew ? "with Homebrew" : "from the disk image")",
            "macOS \(details.macOSVersion) (\(details.macOSBuild)), \(details.appleSilicon ? "Apple Silicon" : "Intel")",
            "Displays: \(details.displays). \(MenuCopy.header(windows: details.windows, apps: details.apps)).",
            "Accessibility: \(details.accessibility.rawValue). Screen Recording: \(onOff(details.screenRecording)).",
            "Zoom: \(onOff(details.zoom)). \(details.gestures)",
        ] + details.lines).joined(separator: "\n")
    }

    public static func body(_ details: ReportDetails) -> String {
        "### What happened?\n\n\n### What did you expect?\n\n\n### Details\n" + detailsBlock(details)
    }

    /// `.urlQueryAllowed` minus `+&=#` (RESEARCH Pattern 9): a bare `+` may read as a space in GitHub's form decoding.
    public static func issueURL(body: String) -> URL {
        let allowed = CharacterSet.urlQueryAllowed.subtracting(CharacterSet(charactersIn: "+&=#"))
        let encoded = body.addingPercentEncoding(withAllowedCharacters: allowed)!
        return URL(string: "https://github.com/scottkw/transomwm/issues/new?body=" + encoded)!
    }
}

import Foundation
import TransomEngine
import TransomModel

/// One Tracked Windows row, pre-formatted (02-UI-SPEC Surface 3). Titles are shown, never logged.
nonisolated public struct TrackedWindowRow: Identifiable, Equatable, Sendable {
    public var id: WindowIdentity
    public var pid: Int32
    public var appName: String
    public var title: String
    public var isPlaceholderTitle: Bool
    public var idText: String
    public var isSyntheticID: Bool
    public var kindText: String
    public var isNeverDock: Bool
    public var stateText: String
    public var tabsText: String
    public var frameText: String
    public var displayText: String
    public var minSizeText: String
    public var isExcluded: Bool
    public var isNotResponding: Bool
}

nonisolated public enum TrackedWindowsState: Equatable, Sendable {
    case noPermission(stale: Bool), loading, empty, populated
}

/// Pure formatting for the Tracked Windows window, testable without UI.
nonisolated public enum TrackedWindowsModel {
    /// One row per non-closed window, sorted by app name (case- and diacritic-insensitive), then window ID.
    /// `appNames` is pid → `localizedName`; a missing name falls back to the bundle ID.
    public static func rows(
        _ inventory: WindowInventory, exclusions: Set<String>, appNames: [Int32: String], displayNames: [String: String]
    ) -> [TrackedWindowRow] {
        let excluded = Set(exclusions.map { $0.lowercased() })
        let rows = inventory.windows.filter { $0.state != .closed }.map { info in
            let ref = info.window
            let synthetic = info.idSource == .synthetic
            return TrackedWindowRow(
                id: ref.identity, pid: ref.pid, appName: appNames[ref.pid] ?? ref.bundleID,
                title: ref.titleHint.isEmpty ? "Untitled" : ref.titleHint, isPlaceholderTitle: ref.titleHint.isEmpty,
                idText: synthetic ? "by frame" : String(ref.windowID), isSyntheticID: synthetic,
                kindText: kindText(info.kind), isNeverDock: info.kind != .dockable,
                stateText: stateText(info.state), tabsText: info.tabCount >= 2 ? "\(info.tabCount) tabs" : "",
                frameText: frameText(info.frame), displayText: info.displayUUID.flatMap { displayNames[$0] } ?? "—",
                minSizeText: info.learnedMinimum.map { "\(int($0.width)) × \(int($0.height))" } ?? "",
                isExcluded: info.isExcluded || excluded.contains(ref.bundleID.lowercased()),
                isNotResponding: inventory.degradedPIDs.contains(ref.pid)
            )
        }
        return rows.sorted {
            switch $0.appName.compare($1.appName, options: [.caseInsensitive, .diacriticInsensitive]) {
            case .orderedAscending: true
            case .orderedDescending: false
            case .orderedSame: $0.id < $1.id
            }
        }
    }

    /// "14 windows · 6 apps · 3 never dock · 1 excluded · 1 not responding"; segments after apps count
    /// rows and are omitted at zero. Prefixed "Refreshing after wake · " while the session is paused.
    public static func footer(_ inventory: WindowInventory, rows: [TrackedWindowRow]) -> String {
        var parts = [count(rows.count, "window"), count(Set(rows.map(\.pid)).count, "app")]
        for (n, label) in [
            (rows.filter(\.isNeverDock).count, "never dock"), (rows.filter(\.isExcluded).count, "excluded"),
            (rows.filter(\.isNotResponding).count, "not responding"),
        ] where n > 0 {
            parts.append("\(n) \(label)")
        }
        let summary = parts.joined(separator: " · ")
        return inventory.sessionPaused ? "Refreshing after wake · " + summary : summary
    }

    public static func state(permissionReady: Bool, stale: Bool, inventory: WindowInventory) -> TrackedWindowsState {
        guard permissionReady else { return .noPermission(stale: stale) }
        if inventory.windows.contains(where: { $0.state != .closed }) { return .populated }
        return inventory.initialRefreshComplete ? .empty : .loading
    }

    public static func kindText(_ kind: WindowKind) -> String {
        switch kind {
        case .dockable: "Dockable"
        case .neverDock(.floatingLevel): "Never dock · Floating"
        case .neverDock(.subrole): "Never dock · Dialog or panel"
        case .neverDock(.modal): "Never dock · Modal"
        case .neverDock(.noCloseButton): "Never dock · No close button"
        case .neverDock(.noFullscreenButton): "Never dock · No full-screen button"
        }
    }

    /// Top-left global points "x, y  w × h", rounded to the nearest integer (.5 away from zero).
    public static func frameText(_ rect: Rect) -> String {
        "\(int(rect.x)), \(int(rect.y))  \(int(rect.width)) × \(int(rect.height))"
    }

    private static func stateText(_ state: WindowState) -> String {
        switch state {
        case .present: "Present"
        case .absent: "Absent"
        case .fullscreen: "Fullscreen"
        case .closed: "Closed"
        }
    }

    private static func int(_ value: Double) -> Int { Int(value.rounded()) }

    private static func count(_ n: Int, _ noun: String) -> String {
        n == 1 ? "1 \(noun)" : "\(n) \(noun)s"
    }
}

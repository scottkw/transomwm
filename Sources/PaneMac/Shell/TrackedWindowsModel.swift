import Foundation
import PaneEngine
import PaneModel

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
    public static func rows(
        _ inventory: WindowInventory, exclusions: Set<String>, appNames: [Int32: String], displayNames: [String: String]
    ) -> [TrackedWindowRow] { [] }

    public static func footer(_ inventory: WindowInventory, rows: [TrackedWindowRow]) -> String { "" }

    public static func state(permissionReady: Bool, stale: Bool, inventory: WindowInventory) -> TrackedWindowsState {
        .populated
    }

    public static func kindText(_ kind: WindowKind) -> String { "" }

    public static func frameText(_ rect: Rect) -> String { "" }
}

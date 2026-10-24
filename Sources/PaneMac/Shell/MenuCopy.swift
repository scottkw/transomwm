/// Status-menu copy from the UI-SPEC Copywriting Contract. Pure strings, no AppKit types.
nonisolated public enum MenuCopy {
    public static let maxAppNameLength = 32

    public static func header(windows: Int, apps: Int) -> String { "" }

    public static func degradedLine(count: Int) -> String? { "" }

    public static func capabilityItem(windowIDLookupAvailable: Bool) -> String { "" }

    public static func truncatedAppName(_ name: String) -> String { "" }
}

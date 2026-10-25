/// Read-only per-window Space lookup (SkyLight, private). RED stub: always unavailable.
public enum SkyLightSpaces {
    public static var isLoaded: Bool { false }

    public static func spaces(of windowIDs: [UInt32]) -> [UInt32: Set<UInt64>]? { nil }
}

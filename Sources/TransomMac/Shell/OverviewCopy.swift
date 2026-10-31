nonisolated public enum OverviewCopy {
    public enum SpacesLine: Equatable, Sendable { case counts(spaces: Int, displays: Int, shared: Bool), visited(Int) }
    public static func spacesLine(_ line: SpacesLine) -> String { "" }
}

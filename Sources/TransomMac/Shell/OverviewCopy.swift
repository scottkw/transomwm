/// Phase 6 copy from the UI-SPEC (Surface 7, Copywriting Contract). Pure strings, no AppKit types.
nonisolated public enum OverviewCopy {
    // MARK: S1 Spaces

    public enum SpacesLine: Equatable, Sendable {
        /// From the Spaces lookup; `shared` when "Displays have separate Spaces" is off.
        case counts(spaces: Int, displays: Int, shared: Bool)
        /// Lookup off: Spaces visited since launch (co-visibility, D-15).
        case visited(Int)
    }

    /// "Spaces: 3 on 1 display" · "Spaces: 5 across 2 displays" · "Spaces: 4, shared by 2 displays" ·
    /// "Spaces: 2 visited since launch".
    public static func spacesLine(_ line: SpacesLine) -> String {
        switch line {
        case .counts(let spaces, 1, _): "Spaces: \(spaces) on 1 display"
        case .counts(let spaces, let displays, false): "Spaces: \(spaces) across \(displays) displays"
        case .counts(let spaces, let displays, true): "Spaces: \(spaces), shared by \(displays) displays"
        case .visited(let visited): "Spaces: \(visited) visited since launch"
        }
    }
}

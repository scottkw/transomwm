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

    // MARK: S2-S4 Displays

    public enum DisplaysLine: Equatable, Sendable {
        /// `arrangement` is `ArrangementID.shortHash`, the value the `displays` log lines print.
        case settled(displays: Int, arrangement: String)
        /// Within the 1.5 s debounce (D-11).
        case settling
        /// SessionGate holds a change until wake or unlock.
        case waitingForWake
    }

    public static func displaysLine(_ line: DisplaysLine) -> String {
        switch line {
        case .settled(let displays, let arrangement): "Displays: \(displays), arrangement \(arrangement)"
        case .settling: "Displays: settling\u{2026}"
        case .waitingForWake: "Displays: waiting for wake"
        }
    }

    public static func savedArrangementsLine(_ count: Int) -> String {
        count == 0 ? "Saved arrangements: none yet" : "Saved arrangements: \(count)"
    }

    public static func dormantDesksLine(desks: Int, awayDisplays: Int) -> String {
        if desks == 0 { "Dormant desks: none" } else if awayDisplays == 1 { "Dormant desks: \(desks) (1 display away)" } else {
            "Dormant desks: \(desks) (\(awayDisplays) displays away)"
        }
    }
}

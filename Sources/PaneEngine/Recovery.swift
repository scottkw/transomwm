import PaneModel

/// How this launch treats the layout the last session left (D-17, D-18).
public enum LaunchMode: Equatable, Sendable {
    case normal, recovery, crashLoop
}

/// The crash-recovery rules (SAFE-02, SAFE-03, D-17, D-18, RESEARCH Pattern 10). Pure, in CloseRule's style.
public enum Recovery {
    public static let minVisibleFraction = 0.5
    public static let minVisibleSize = Size(width: 40, height: 40)
    public static let crashLoopWindow: Duration = .seconds(60)

    public static func isStranded(_ frame: Rect, displays: [DisplayInfo]) -> Bool {
        false
    }

    public static func destination(for frame: Rect, home: Rect?, display: DisplayInfo) -> Rect {
        frame
    }

    public static func launchMode(previous: SessionRecord?) -> LaunchMode {
        .normal
    }
}

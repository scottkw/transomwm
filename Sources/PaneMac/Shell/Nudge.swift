import PaneModel

/// The Debug menu's Nudge (D-01): the first press moves a window by `offset` and shrinks it by `shrink`, the next
/// restores the frame it had before the first press.
nonisolated public struct NudgePlanner {
    public static let offset: Double = 32
    public static let shrink: Double = 64

    public init() {}

    public mutating func target(for window: WindowIdentity, current: Rect) -> Rect {
        current
    }
}

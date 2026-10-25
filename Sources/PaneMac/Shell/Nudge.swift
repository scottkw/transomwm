import PaneModel

/// The Debug menu's Nudge (D-01): the first press moves a window by `offset` and shrinks it by `shrink`, the next
/// restores the frame it had before the first press.
nonisolated public struct NudgePlanner {
    public static let offset: Double = 32
    public static let shrink: Double = 64

    /// The frame each nudged window had before its first press.
    private var restore: [WindowIdentity: Rect] = [:]

    public init() {}

    /// Where `window` goes on this press, given where it is now.
    public mutating func target(for window: WindowIdentity, current: Rect) -> Rect {
        if let saved = restore.removeValue(forKey: window) { return saved }
        restore[window] = current
        return Rect(
            x: current.x + Self.offset, y: current.y + Self.offset,
            width: max(1, current.width - Self.shrink), height: max(1, current.height - Self.shrink)
        )
    }
}

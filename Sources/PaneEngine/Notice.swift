import PaneModel

/// Something the user is told in a toast (UI-SPEC Surface 4). The Arranger emits these; the shell words them
/// (`NoticeCopy`) and queues them (`NoticeQueue`). Later plans add cases.
public enum Notice: Equatable, Sendable {
    /// N1: docked windows that lost their room after docking (a larger learned minimum, a smaller display) and now
    /// float on the Desktop (D-26). In identity order.
    case lostRoom([WindowRef])
    /// N9: ⌃⌥⌘N pressed Finder's New Finder Window item, but no new Finder window came within 2 s (D-14).
    case finderNoWindow
    /// N4: Float All Windows floated this many windows.
    case floatedAll(count: Int)
    /// N5: Arrange All Windows left this many windows floating, for lack of room.
    case arrangeLeftovers(count: Int)
    /// N2: the launch after a crash put stranded windows back on screen and re-applied the layout; `unplaced` tracked
    /// windows were not in the saved layout and float on the Desktop.
    case crashRecovered(unplaced: Int)
    /// N3: a second unclean exit within about a minute, so this launch started paused (D-18).
    case crashLoop
    case restored(count: Int)

    /// Crash notices (N2/N3) are never replaced by a newer toast and stay up longer.
    public var isCrashNotice: Bool {
        switch self {
        case .crashRecovered, .crashLoop: true
        case .lostRoom, .finderNoWindow, .floatedAll, .arrangeLeftovers, .restored: false
        }
    }
}

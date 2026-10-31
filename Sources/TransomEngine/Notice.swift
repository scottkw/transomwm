import TransomModel

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
    /// N7: a Turn Off did not take on read-back; Transom opened Desktop & Dock (D-20).
    case turnOffFailed(Conflict)
    /// N8: Restore macOS Window Settings wrote every recorded original back (D-21).
    case settingsRestored
    /// N12: displays were disconnected (their names, captured before they left, in UUID order) and this many of their
    /// windows now float on a remaining display (D-10).
    case displaysDisconnected(names: [String], windows: Int)

    /// Crash notices (N2/N3) are never replaced by a newer toast and stay up longer.
    public var isCrashNotice: Bool {
        switch self {
        case .crashRecovered, .crashLoop: true
        case .lostRoom, .finderNoWindow, .floatedAll, .arrangeLeftovers, .restored, .turnOffFailed, .settingsRestored, .displaysDisconnected: false
        }
    }
}

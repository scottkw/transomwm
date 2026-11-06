import TransomModel

/// Something the user is told in a toast (UI-SPEC Surface 4). The Arranger emits these; the shell words them
/// (`NoticeCopy`) and queues them (`NoticeQueue`). Later plans add cases.
public enum Notice: Equatable, Sendable {
    /// N1: docked windows that lost their room after docking (a larger learned minimum, a smaller display) and now
    /// float (D-26). In identity order.
    case lostRoom([WindowRef])
    /// N9: ⌃⌥⌘N pressed Finder's New Finder Window item, but no new Finder window came within 2 s (D-14).
    case finderNoWindow
    /// N4: Float All Windows floated this many windows.
    case floatedAll(count: Int)
    /// N5: Arrange All Windows left this many windows floating, for lack of room.
    case arrangeLeftovers(count: Int)
    /// N2: the launch after a crash put stranded windows back on screen and re-applied the layout; `unplaced` tracked
    /// windows were not in the saved layout and float.
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
    /// N10: the last run crashed with the Mission Control takeover on, so it stays off this launch (D-07). Queued
    /// behind N2/N3, shown once.
    case takeoverCrashed
    /// N11: applying the takeover failed on read-back; the originals are back (D-07).
    case takeoverApplyFailed
    // Saved views (08 UI-SPEC View toasts). Each carries the display its toast belongs on: the pointer display when
    // saving or for an empty slot, the destination display when going; nil falls back to the menu-bar display.
    /// N13 / N14: a view was saved into an empty slot, or replaced the one there (D-15).
    case viewSaved(ViewSlot, replaced: Bool, displayUUID: String?)
    /// N15: going to a view.
    case viewShown(ViewSlot, displayUUID: String?)
    /// N16: going to an empty slot (D-04).
    case viewEmpty(ViewSlot, displayUUID: String?)
    /// N17: every window of the view has closed, so the camera shows the saved desk's home; the slot stays (D-05).
    case viewWindowsClosed(ViewSlot, displayUUID: String?)
    /// N18: every window of the view has closed and its display isn't connected; nothing moved.
    case viewDisplayGone(ViewSlot, displayUUID: String?)
    /// N19: the view to save holds no windows; the slot is unchanged.
    case viewNothingToSave(displayUUID: String?)

    /// Crash notices (N2/N3) are never replaced by a newer toast and stay up longer.
    public var isCrashNotice: Bool {
        switch self {
        case .crashRecovered, .crashLoop: true
        case .lostRoom, .finderNoWindow, .floatedAll, .arrangeLeftovers, .restored, .turnOffFailed, .settingsRestored, .displaysDisconnected, .takeoverCrashed,
            .takeoverApplyFailed, .viewSaved, .viewShown, .viewEmpty, .viewWindowsClosed, .viewDisplayGone, .viewNothingToSave: false
        }
    }

    /// Brief toasts (1.5 s, never queued behind a crash notice): every view notice except N17.
    public var isBrief: Bool {
        switch self {
        case .viewSaved, .viewShown, .viewEmpty, .viewDisplayGone, .viewNothingToSave: true
        case .lostRoom, .finderNoWindow, .floatedAll, .arrangeLeftovers, .crashRecovered, .crashLoop, .restored, .turnOffFailed, .settingsRestored,
            .displaysDisconnected, .takeoverCrashed, .takeoverApplyFailed, .viewWindowsClosed: false
        }
    }
}

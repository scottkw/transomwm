import PaneModel

/// Something the user is told in a toast (UI-SPEC Surface 4). The Arranger emits these; the shell words them
/// (`NoticeCopy`) and queues them (`NoticeQueue`). Later plans add cases.
public enum Notice: Equatable, Sendable {
    /// N1: docked windows that lost their room after docking (a larger learned minimum, a smaller display) and now
    /// float on the Desktop (D-26). In identity order.
    case lostRoom([WindowRef])
    /// N9: ⌃⌥⌘N pressed Finder's New Finder Window item, but no new Finder window came within 2 s (D-14).
    case finderNoWindow

    /// Crash notices (N2/N3, plan 13) are never replaced by a newer toast and stay up longer.
    public var isCrashNotice: Bool {
        switch self {
        case .lostRoom, .finderNoWindow: false
        }
    }
}

import PaneModel

/// The latest focus hint per app, kept until the window it names is tracked (G-03-5).
///
/// A hint names a window ID, or none when the app thread had not cached the element yet: such a hint means "the app's
/// AXMain window". A new window is withheld while it settles, so its hint resolves on a later refresh. A newer hint
/// replaces an older one; a hint that never resolves (an untracked panel) is simply replaced by the next.
public struct PendingFocus: Equatable, Sendable {
    private enum Target: Equatable, Sendable {
        case window(UInt32)
        case main
    }

    private var hints: [Int32: Target] = [:]

    public init() {}

    /// Records the pid's focus hint; a nil `windowID` resolves through AXMain.
    public mutating func hint(pid: Int32, windowID: UInt32?) {
        hints[pid] = windowID.map(Target.window) ?? .main
    }

    /// The tracked window of `pid` the hint names (through a tab group's shown member), consuming the hint; nil keeps
    /// it. `mainID`: the app's AXMain window ID from a successful observation, else nil.
    public mutating func resolve(pid: Int32, mainID: UInt32?, windows: [WindowInfo]) -> WindowRef? {
        let target: UInt32?
        switch hints[pid] {
        case nil: return nil
        case .window(let id): target = id
        case .main: target = mainID
        }
        guard let target,
              let info = windows.first(where: { $0.window.pid == pid && ($0.visibleMemberID ?? $0.window.windowID) == target })
        else { return nil }
        hints[pid] = nil
        return info.window
    }

    public mutating func rekey(pid: Int32, from: UInt32, to: UInt32) {
        if hints[pid] == .window(from) { hints[pid] = .window(to) }
    }

    public mutating func forget(pid: Int32) {
        hints[pid] = nil
    }
}

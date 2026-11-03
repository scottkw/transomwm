import TransomModel

/// The latest focus hint per app, kept until the window it names is tracked (G-03-5).
///
/// A hint names a window ID, or none when the app thread had not cached the element yet: such a hint means "the app's
/// AXMain window". A new window is withheld while it settles, so its hint resolves on a later refresh. A newer hint
/// replaces an older one; a hint that never resolves (an untracked panel) is simply replaced by the next.
public struct PendingFocus: Equatable, Sendable {
    private enum Target: Equatable, Sendable {
        case window(UInt32)
        case main
        /// The app was activated: its AXMain window, which macOS sends no focus change for when it stays the same.
        case activation
    }

    private struct Resolved: Equatable, Sendable {
        let identity: WindowIdentity
        let activation: Bool
        let at: ContinuousClock.Instant
    }

    /// An activation and an AX hint naming the same window this close together are one focus change.
    public static let duplicateWindow: Duration = .milliseconds(500)

    private var hints: [Int32: Target] = [:]
    private var last: Resolved?

    public init() {}

    /// Records the pid's focus hint; a nil `windowID` resolves through AXMain.
    public mutating func hint(pid: Int32, windowID: UInt32?) {
        hints[pid] = windowID.map(Target.window) ?? .main
    }

    /// The app became frontmost (⌘Tab, the Dock, `open -a`): its AXMain window is focused, though macOS reports no focus
    /// change when that window already was its focused one, such as a hidden tab (07 UAT Bug 1, D-08). A pending AX hint
    /// names the window more exactly and stays; another app's unresolved activation can no longer be right and goes.
    public mutating func activated(pid: Int32) {
        hints = hints.filter { $0.value != .activation }
        if hints[pid] == nil { hints[pid] = .activation }
    }

    /// The tracked window of `pid` the hint names (through a tab group's shown member), consuming the hint; nil keeps
    /// it. `mainID`: the app's AXMain window ID from a successful observation, else nil. A resolution that repeats the
    /// previous one within `duplicateWindow`, with an activation on either side, is consumed and returns nil.
    public mutating func resolve(pid: Int32, mainID: UInt32?, windows: [WindowInfo], now: ContinuousClock.Instant = .now) -> WindowRef? {
        let target: UInt32?
        let activation = hints[pid] == .activation
        switch hints[pid] {
        case nil: return nil
        case .window(let id): target = id
        case .main, .activation: target = mainID
        }
        guard let target,
              let info = windows.first(where: { $0.window.pid == pid && ($0.visibleMemberID ?? $0.window.windowID) == target })
        else { return nil }
        hints[pid] = nil
        if let last, last.identity == info.window.identity, activation || last.activation, now - last.at < Self.duplicateWindow {
            return nil
        }
        last = Resolved(identity: info.window.identity, activation: activation, at: now)
        return info.window
    }

    public mutating func rekey(pid: Int32, from: UInt32, to: UInt32) {
        if hints[pid] == .window(from) { hints[pid] = .window(to) }
    }

    public mutating func forget(pid: Int32) {
        hints[pid] = nil
    }
}

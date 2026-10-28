import TransomModel

/// When the stage reveals after a settle (UI-SPEC Surface 1 step 7): the last write's return plus `redraw` once every
/// pending write is back, or `started + cap`, whichever comes first. Pure, with the clock injected.
public struct SettleTracker: Sendable {
    public static let redraw: Duration = .milliseconds(50)
    public static let cap: Duration = .milliseconds(1500)
    private var pending: Set<WindowIdentity>
    private let started: ContinuousClock.Instant
    private var lastReturn: ContinuousClock.Instant?

    public init(pending: Set<WindowIdentity>, started: ContinuousClock.Instant) {
        self.pending = pending
        self.started = started
    }

    /// A write came back; an ID not pending (or already back) changes nothing.
    public mutating func applied(_ id: WindowIdentity, at now: ContinuousClock.Instant) {
        if pending.remove(id) != nil { lastReturn = now }
    }

    public func revealAt() -> ContinuousClock.Instant {
        pending.isEmpty ? min((lastReturn ?? started) + Self.redraw, started + Self.cap) : started + Self.cap
    }

    public var isComplete: Bool { pending.isEmpty }
}

import PaneEngine
import PaneModel

/// A toast `NoticeQueue` can hold.
nonisolated public protocol QueueableNotice: Equatable, Sendable {
    /// Never replaced by a newer toast; shown for `NoticeQueue.crashDuration`.
    var isCrashNotice: Bool { get }
    /// `self` and the newer `other` as one notice when they are the same kind, else nil.
    func merged(with other: Self) -> Self?
}

/// The toast queue rules (UI-SPEC Surface 4). Pure value type; the shell shows what `post` and `expire` return.
nonisolated public struct NoticeQueue<Item: QueueableNotice>: Sendable {
    public enum Change: Equatable, Sendable {
        case unchanged
        case show(Item)
        case hide
    }

    public static var duration: Duration { .seconds(6) }
    public static var crashDuration: Duration { .seconds(10) }
    public static var maxQueued: Int { 3 }

    public private(set) var visible: Item?
    public private(set) var expiresAt: ContinuousClock.Instant?

    public init() {}

    public mutating func post(_ notice: Item, at now: ContinuousClock.Instant) -> Change {
        .unchanged
    }

    public mutating func expire(at now: ContinuousClock.Instant) -> Change {
        .unchanged
    }
}

nonisolated extension Notice: QueueableNotice {
    public func merged(with other: Notice) -> Notice? {
        nil
    }
}

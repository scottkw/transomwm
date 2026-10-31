import TransomEngine
import TransomModel

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

    private var queued: [Item] = []

    public init() {}

    /// A notice merges into the visible one of its kind, or replaces it, unless that one is a crash notice: then it
    /// waits, merged into a queued one of its kind or appended, with the oldest dropped past `maxQueued`.
    public mutating func post(_ notice: Item, at now: ContinuousClock.Instant) -> Change {
        guard let current = visible else { return show(notice, at: now) }
        guard current.isCrashNotice else { return show(current.merged(with: notice) ?? notice, at: now) }
        if let i = queued.firstIndex(where: { $0.merged(with: notice) != nil }), let merged = queued[i].merged(with: notice) {
            queued[i] = merged
        } else {
            queued.append(notice)
            if queued.count > Self.maxQueued { queued.removeFirst() }
        }
        return .unchanged
    }

    /// Once the visible notice's time is up, the oldest queued one shows, or the toast hides.
    public mutating func expire(at now: ContinuousClock.Instant) -> Change {
        guard visible != nil, let expiresAt, now >= expiresAt else { return .unchanged }
        guard queued.isEmpty else { return show(queued.removeFirst(), at: now) }
        visible = nil
        self.expiresAt = nil
        return .hide
    }

    private mutating func show(_ notice: Item, at now: ContinuousClock.Instant) -> Change {
        visible = notice
        expiresAt = now + (notice.isCrashNotice ? Self.crashDuration : Self.duration)
        return .show(notice)
    }
}

nonisolated extension Notice: QueueableNotice {
    /// Two lost-room notices become one naming every window once; two N9s are one; two N12s are one.
    public func merged(with other: Notice) -> Notice? {
        switch (self, other) {
        case (.lostRoom(let windows), .lostRoom(let more)): .lostRoom(windows + more.filter { !windows.contains($0) })
        case (.finderNoWindow, .finderNoWindow): .finderNoWindow
        // Two N12s become the several-displays form.
        case (.displaysDisconnected(let names, let windows), .displaysDisconnected(let more, let moreWindows)):
            .displaysDisconnected(names: names + more, windows: windows + moreWindows)
        // A newer Float All or Arrange All result replaces the older one: its count is the current one.
        case (.lostRoom, _), (.finderNoWindow, _), (.floatedAll, _), (.arrangeLeftovers, _), (.crashRecovered, _), (.crashLoop, _), (.restored, _),
            (.turnOffFailed, _), (.settingsRestored, _), (.displaysDisconnected, _): nil
        }
    }
}

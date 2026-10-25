import PaneModel

/// Learns each window's real minimum size from what its app did with a smaller request (D-13, in memory).
///
/// Apps refuse an undersized `AXSize` silently: the write succeeds and the read-back is clamped. An axis read
/// back more than `tolerance` above the request is a refusal, but one read-back can also be stale (an app that
/// applies size later) or a snap, and a learned value is persisted per bundle. So a refusal is learned only when
/// a later write's read-back is also refused on that axis and agrees within `tolerance`. A read-back that contradicts
/// it (refused at another size, or honoured below it) starts over; an honoured one at or above it does not, since
/// `WindowTracker` skips read-backs still at the pre-write size and the confirming refusal must then come from a
/// later shrink. An axis read back smaller than requested (terminals snapping to whole cells) teaches nothing.
/// Learned values only grow; an unlearned axis reads 0.
public struct MinimumSizeLearner: Equatable, Sendable {
    public static let tolerance: Double = 2
    public static let refusalMargin: Double = 32
    public static let confirmDelay: Duration = .seconds(1)

    private var minimums: [WindowIdentity: Size] = [:]
    /// The last write's refused read-back per axis, waiting for the next write to confirm it.
    private var unconfirmed: [WindowIdentity: Refusal] = [:]

    private struct Refusal: Equatable, Sendable {
        var width: Double?
        var height: Double?
    }

    public init() {}

    /// The new minimum when it changed, else nil. Read-backs are untrusted numbers: a non-finite or
    /// out-of-range one (beyond `Geometry.maxCoordinate`) is ignored.
    public mutating func learn(window: WindowIdentity, requested: Rect, actual: Rect) -> Size? {
        guard requested.isValidGeometry, actual.isValidGeometry else { return nil }
        let old = minimums[window] ?? Size(width: 0, height: 0)
        var new = old
        var refusal = unconfirmed[window] ?? Refusal()
        func axis(_ requested: Double, _ actual: Double, _ last: inout Double?, _ learned: inout Double) {
            guard actual > requested + Self.tolerance else {
                if let refused = last, actual < refused - Self.tolerance { last = nil }
                return
            }
            if let last, abs(actual - last) <= Self.tolerance { learned = max(learned, actual) }
            last = actual
        }
        axis(requested.width, actual.width, &refusal.width, &new.width)
        axis(requested.height, actual.height, &refusal.height, &new.height)
        unconfirmed[window] = refusal == Refusal() ? nil : refusal
        guard new != old else { return nil }
        minimums[window] = new
        return new
    }

    // RED stub (02-15): the old agreement rule behind the new interface.
    public mutating func recordWrite(window: WindowIdentity, requested: Rect, actual: Rect, at: ContinuousClock.Instant) {
        _ = learn(window: window, requested: requested, actual: actual)
    }

    public mutating func confirm(window: WindowIdentity, observed: Size, at: ContinuousClock.Instant) -> Size? { nil }

    public func awaitsConfirmation(_ window: WindowIdentity) -> Bool { false }

    /// Starts `window` from a minimum learned in an earlier session (D-13). Like learning, it only ever raises
    /// the value; a stored size that is not finite or is out of range is ignored.
    public mutating func seed(_ window: WindowIdentity, minimum: Size) {
        guard [minimum.width, minimum.height].allSatisfy({ $0.isFinite && $0 >= 0 && $0 <= Geometry.maxCoordinate }) else { return }
        let old = minimums[window] ?? Size(width: 0, height: 0)
        minimums[window] = Size(width: max(old.width, minimum.width), height: max(old.height, minimum.height))
    }

    public func minimum(for window: WindowIdentity) -> Size? {
        minimums[window]
    }

    public mutating func forget(_ window: WindowIdentity) {
        minimums[window] = nil
        unconfirmed[window] = nil
    }
}

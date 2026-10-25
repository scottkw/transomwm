import PaneModel

/// Learns each window's real minimum size from what its app did with a smaller request (D-13, in memory).
///
/// Apps refuse an undersized `AXSize` silently: the write succeeds and the read-back is clamped. The rule, per axis:
/// a read-back more than `refusalMargin` (32 pt) above the request is a refusal candidate. It is learned, as
/// max(old, read-back), when a refresh at least `confirmDelay` (1 s) after that write, with no newer write to the
/// window in between, still sees the window within `tolerance` (2 pt) of that size. Anything else drops it.
/// The margin keeps grid snaps out: a terminal rounds a size up by less than one cell. The delay keeps late
/// appliers out: an app that animates or applies the size from a busy main thread has caught up by then, while a
/// clamped window has not moved. An axis read back smaller than requested teaches nothing. Learned values only
/// grow; an unlearned axis reads 0.
public struct MinimumSizeLearner: Equatable, Sendable {
    public static let tolerance: Double = 2
    public static let refusalMargin: Double = 32
    public static let confirmDelay: Duration = .seconds(1)

    private var minimums: [WindowIdentity: Size] = [:]
    /// The latest write's refused read-back per axis, waiting for a refresh to confirm it.
    private var candidates: [WindowIdentity: Candidate] = [:]

    private struct Candidate: Equatable, Sendable {
        var width: Double?
        var height: Double?
        var writtenAt: ContinuousClock.Instant
    }

    public init() {}

    /// A finished write replaces the window's candidate. Read-backs are untrusted numbers: a write with a non-finite
    /// or out-of-range value (beyond `Geometry.maxCoordinate`) leaves no candidate.
    public mutating func recordWrite(window: WindowIdentity, requested: Rect, actual: Rect, at: ContinuousClock.Instant) {
        guard requested.isValidGeometry, actual.isValidGeometry else {
            candidates[window] = nil
            return
        }
        func refused(_ requested: Double, _ actual: Double) -> Double? { actual > requested + Self.refusalMargin ? actual : nil }
        let candidate = Candidate(width: refused(requested.width, actual.width), height: refused(requested.height, actual.height), writtenAt: at)
        candidates[window] = candidate.width == nil && candidate.height == nil ? nil : candidate
    }

    /// A refresh saw the window at `observed`. Before `confirmDelay` has passed since the write, nothing happens;
    /// from then on the candidate is decided and removed. The new minimum when it grew, else nil.
    public mutating func confirm(window: WindowIdentity, observed: Size, at: ContinuousClock.Instant) -> Size? {
        guard let candidate = candidates[window], at >= candidate.writtenAt + Self.confirmDelay else { return nil }
        candidates[window] = nil
        guard Self.isValid(observed) else { return nil }
        let old = minimums[window] ?? Size(width: 0, height: 0)
        func learned(_ refused: Double?, _ observed: Double, _ old: Double) -> Double {
            guard let refused, abs(observed - refused) <= Self.tolerance else { return old }
            return max(old, refused)
        }
        let new = Size(width: learned(candidate.width, observed.width, old.width), height: learned(candidate.height, observed.height, old.height))
        guard new != old else { return nil }
        minimums[window] = new
        return new
    }

    public func awaitsConfirmation(_ window: WindowIdentity) -> Bool {
        candidates[window] != nil
    }

    /// Drops the candidates of `pid`'s windows whose confirmation is due but which no refresh decided (the window
    /// was not listed, not present, or had no frame), so none waits forever.
    public mutating func dropDue(pid: Int32, at: ContinuousClock.Instant) {
        candidates = candidates.filter { $0.key.pid != pid || at < $0.value.writtenAt + Self.confirmDelay }
    }

    private static func isValid(_ size: Size) -> Bool {
        [size.width, size.height].allSatisfy { $0.isFinite && $0 >= 0 && $0 <= Geometry.maxCoordinate }
    }

    /// Starts `window` from a minimum learned in an earlier session (D-13). Like learning, it only ever raises
    /// the value; a stored size that is not finite or is out of range is ignored.
    public mutating func seed(_ window: WindowIdentity, minimum: Size) {
        guard Self.isValid(minimum) else { return }
        let old = minimums[window] ?? Size(width: 0, height: 0)
        minimums[window] = Size(width: max(old.width, minimum.width), height: max(old.height, minimum.height))
    }

    public func minimum(for window: WindowIdentity) -> Size? {
        minimums[window]
    }

    /// The window's ID was corrected (WindowTracker.rekey): its minimum and candidate move to `to`.
    /// When `to` already has a minimum (a duplicate merged), it keeps the larger value per axis.
    public mutating func rekey(from: WindowIdentity, to: WindowIdentity) {
        if let moved = minimums.removeValue(forKey: from) {
            let kept = minimums[to] ?? moved
            minimums[to] = Size(width: max(kept.width, moved.width), height: max(kept.height, moved.height))
        }
        if let candidate = candidates.removeValue(forKey: from), candidates[to] == nil { candidates[to] = candidate }
    }

    public mutating func forget(_ window: WindowIdentity) {
        minimums[window] = nil
        candidates[window] = nil
    }
}

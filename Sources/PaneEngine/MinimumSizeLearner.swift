import PaneModel

/// Learns each window's real minimum size from what its app did with a smaller request (D-13, in memory).
///
/// Apps refuse an undersized `AXSize` silently: the write succeeds and the read-back is clamped. The rule, per axis:
/// a read-back more than `refusalMargin` (32 pt) above the request, and more than `tolerance` (2 pt) below the
/// window's size before the write, is a refusal candidate: the app moved toward the request and stopped. A later
/// write read back at that same size keeps it. A refusal that did not move the window (it was already at its
/// minimum, G-03-6) is only recorded; the same clamp read back unmoved again at least `confirmDelay` (1 s) after that
/// record becomes a candidate. It is learned, as max(old, read-back), when a refresh at least `confirmDelay` after
/// the latest write still sees the window within `tolerance` of that size. Anything else drops it. The margin keeps
/// grid snaps out: a terminal rounds a size up by less than one cell. The move, or the repeat a second later, keeps
/// late appliers out: an app that has not applied the size yet still shows its old frame, so a single slow write
/// teaches nothing, and a refresh that sees the window off a recorded clamp drops the record. Known limit: an app
/// lagging more than about 2 s on two writes in a row can be misread. The delay keeps out an app that animates
/// toward the request. Overflow within refusalMargin is tolerated: such a read-back is never learned, and the
/// Arranger never re-sends the tile for it, so a docked window may overlap its tile edge by up to the margin minus
/// the gap. An axis read back smaller than requested teaches nothing. Learned values only grow; an unlearned axis
/// reads 0. An axis learned from an unmoved refusal holds for that window this session only: a fixed-size window
/// (Welcome, About) refuses unmoved too, so it never reaches `persistableMinimum`, the per-bundle hint (CR-02).
public struct MinimumSizeLearner: Equatable, Sendable {
    public static let tolerance: Double = 2
    public static let refusalMargin: Double = 32
    public static let confirmDelay: Duration = .seconds(1)

    private var minimums: [WindowIdentity: Size] = [:]
    /// The part of `minimums` that was seeded or learned from a refusal that moved the window: safe to share per bundle.
    private var persistable: [WindowIdentity: Size] = [:]
    /// The latest write's refused read-back per axis, waiting for a refresh to confirm it.
    private var candidates: [WindowIdentity: Candidate] = [:]

    /// Per axis, an unmoved refusal's clamp and when it was first read back: promoted by a repeat `confirmDelay` later.
    private var unmoved: [WindowIdentity: Unmoved] = [:]

    private struct Clamp: Equatable, Sendable {
        var value: Double
        var since: ContinuousClock.Instant
    }

    private struct Unmoved: Equatable, Sendable {
        var width: Clamp?
        var height: Clamp?
    }

    private struct Candidate: Equatable, Sendable {
        var width: Double?
        var height: Double?
        var writtenAt: ContinuousClock.Instant
        /// Per axis, the value came from an unmoved refusal (session-only, CR-02).
        var widthUnmoved = false
        var heightUnmoved = false
    }

    public init() {}

    /// A finished write replaces the window's candidate; `before` is the window's size just before it. Read-backs are
    /// untrusted numbers: a write with a non-finite or out-of-range value (beyond `Geometry.maxCoordinate`) leaves no
    /// candidate.
    public mutating func recordWrite(window: WindowIdentity, requested: Rect, actual: Rect, before: Size, at: ContinuousClock.Instant) {
        guard requested.isValidGeometry, actual.isValidGeometry, Self.isValid(before) else {
            candidates[window] = nil
            unmoved[window] = nil
            return
        }
        func refused(
            _ requested: Double, _ actual: Double, _ before: Double, _ previous: Double?, _ previousUnmoved: Bool, _ clamp: Clamp?
        ) -> (Double?, unmoved: Bool, Clamp?) {
            guard actual > requested + Self.refusalMargin else { return (nil, false, nil) }
            if actual < before - Self.tolerance { return (actual, false, nil) }
            // Not moved: the same clamp seen again keeps the earlier write's candidate,
            if let previous, abs(actual - previous) <= Self.tolerance { return (previous, previousUnmoved, clamp) }
            // or, once a late applier has had confirmDelay since the clamp was first recorded, becomes one.
            guard let clamp, abs(actual - clamp.value) <= Self.tolerance else { return (nil, false, Clamp(value: actual, since: at)) }
            return at >= clamp.since + Self.confirmDelay ? (actual, true, nil) : (nil, false, clamp)
        }
        let previous = candidates[window], record = unmoved[window]
        let (width, widthUnmoved, widthClamp) = refused(
            requested.width, actual.width, before.width, previous?.width, previous?.widthUnmoved ?? false, record?.width)
        let (height, heightUnmoved, heightClamp) = refused(
            requested.height, actual.height, before.height, previous?.height, previous?.heightUnmoved ?? false, record?.height)
        candidates[window] = width == nil && height == nil
            ? nil
            : Candidate(width: width, height: height, writtenAt: at, widthUnmoved: widthUnmoved, heightUnmoved: heightUnmoved)
        unmoved[window] = widthClamp == nil && heightClamp == nil ? nil : Unmoved(width: widthClamp, height: heightClamp)
    }

    /// A refresh saw the window at `observed`. Before `confirmDelay` has passed since the write, nothing happens;
    /// from then on the candidate is decided and removed. The new minimum when it or `persistableMinimum` grew, else nil.
    public mutating func confirm(window: WindowIdentity, observed: Size, at: ContinuousClock.Instant) -> Size? {
        // Off a recorded unmoved clamp: the app was only late, so that record goes.
        if var record = unmoved[window] {
            if let clamp = record.width, abs(observed.width - clamp.value) > Self.tolerance { record.width = nil }
            if let clamp = record.height, abs(observed.height - clamp.value) > Self.tolerance { record.height = nil }
            unmoved[window] = record.width == nil && record.height == nil ? nil : record
        }
        guard let candidate = candidates[window], at >= candidate.writtenAt + Self.confirmDelay else { return nil }
        candidates[window] = nil
        guard Self.isValid(observed) else { return nil }
        let zero = Size(width: 0, height: 0)
        let old = minimums[window] ?? zero, oldShared = persistable[window] ?? zero
        func learned(_ refused: Double?, _ observed: Double, _ old: Double) -> Double {
            guard let refused, abs(observed - refused) <= Self.tolerance else { return old }
            return max(old, refused)
        }
        let new = Size(width: learned(candidate.width, observed.width, old.width), height: learned(candidate.height, observed.height, old.height))
        let shared = Size(
            width: learned(candidate.widthUnmoved ? nil : candidate.width, observed.width, oldShared.width),
            height: learned(candidate.heightUnmoved ? nil : candidate.height, observed.height, oldShared.height))
        guard new != old || shared != oldShared else { return nil }
        minimums[window] = new
        if shared != oldShared { persistable[window] = shared }
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
        let shared = persistable[window] ?? Size(width: 0, height: 0)
        persistable[window] = Size(width: max(shared.width, minimum.width), height: max(shared.height, minimum.height))
    }

    public func minimum(for window: WindowIdentity) -> Size? {
        minimums[window]
    }

    /// The seeded part of `minimum(for:)` and what refusals that moved the window taught: the per-bundle hint (D-13).
    public func persistableMinimum(for window: WindowIdentity) -> Size? {
        persistable[window]
    }

    /// The window's ID was corrected (WindowTracker.rekey): its minimum, candidate and unmoved record move to `to`.
    /// When `to` already has a minimum (a duplicate merged), it keeps the larger value per axis.
    public mutating func rekey(from: WindowIdentity, to: WindowIdentity) {
        func merge(_ sizes: inout [WindowIdentity: Size]) {
            guard let moved = sizes.removeValue(forKey: from) else { return }
            let kept = sizes[to] ?? moved
            sizes[to] = Size(width: max(kept.width, moved.width), height: max(kept.height, moved.height))
        }
        merge(&minimums)
        merge(&persistable)
        if let candidate = candidates.removeValue(forKey: from), candidates[to] == nil { candidates[to] = candidate }
        if let record = unmoved.removeValue(forKey: from), unmoved[to] == nil { unmoved[to] = record }
    }

    public mutating func forget(_ window: WindowIdentity) {
        minimums[window] = nil
        persistable[window] = nil
        candidates[window] = nil
        unmoved[window] = nil
    }
}

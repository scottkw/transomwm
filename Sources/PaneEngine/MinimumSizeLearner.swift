import PaneModel

/// Learns each window's real minimum size from what its app did with a smaller request (D-13, in memory).
///
/// Apps refuse an undersized `AXSize` silently: the write succeeds and the read-back is clamped. So on each
/// axis where the read-back exceeds the request by more than `tolerance`, the learned minimum becomes the
/// larger of the old value and the read-back. An axis read back smaller than requested (terminals snapping
/// to whole cells) teaches nothing. Learned values only grow; an unlearned axis reads 0.
public struct MinimumSizeLearner: Equatable, Sendable {
    public static let tolerance: Double = 2

    private var minimums: [WindowIdentity: Size] = [:]

    public init() {}

    /// The new minimum when it changed, else nil. Read-backs are untrusted numbers: a non-finite or
    /// out-of-range one (beyond `Geometry.maxCoordinate`) is ignored.
    public mutating func learn(window: WindowIdentity, requested: Rect, actual: Rect) -> Size? {
        guard requested.isValidGeometry, actual.isValidGeometry else { return nil }
        let old = minimums[window] ?? Size(width: 0, height: 0)
        var new = old
        if actual.width > requested.width + Self.tolerance { new.width = max(old.width, actual.width) }
        if actual.height > requested.height + Self.tolerance { new.height = max(old.height, actual.height) }
        guard new != old else { return nil }
        minimums[window] = new
        return new
    }

    public func minimum(for window: WindowIdentity) -> Size? {
        minimums[window]
    }

    public mutating func forget(_ window: WindowIdentity) {
        minimums[window] = nil
    }
}

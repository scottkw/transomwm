/// D-15 fallback while the Spaces lookup is off: each settled Space visit's on-screen window IDs, per display, join the
/// visited Space they overlap most (Jaccard ≥ 0.5), else start a new one with the next synthetic ID.
///
/// Debug-only (RESEARCH Pattern 8, Open Question 2): session-only, never persisted, never a `DeskKey` or
/// `WindowInfo.spaces`. With the lookup off every display keeps its one desk.
public struct CoVisibilitySpaces: Equatable, Sendable {
    /// The reserved high range, so a synthetic ID can never pass for a SkyLight Space ID.
    public static let syntheticBase: UInt64 = 0x8000_0000_0000_0000

    private struct Cluster: Equatable, Sendable {
        let id: UInt64
        var windowIDs: Set<UInt32>
    }

    private var clusters: [String: [Cluster]] = [:]
    private var last: [String: UInt64] = [:]
    private var next: UInt64 = 1

    public init() {}

    /// Distinct Spaces visited since launch, over every display.
    public var visitedCount: Int { clusters.values.reduce(0) { $0 + $1.count } }

    /// The synthetic ID of the Space just shown on `display`. A joined Space takes this visit's windows, so it follows
    /// windows opening and closing. An empty visit says nothing and returns the display's last Space.
    @discardableResult
    public mutating func visit(display: String, windowIDs: Set<UInt32>) -> UInt64 {
        if windowIDs.isEmpty, let id = last[display] { return id }
        var list = clusters[display, default: []]
        let best = list.indices
            .map { (index: $0, shared: list[$0].windowIDs.intersection(windowIDs).count, union: list[$0].windowIDs.union(windowIDs).count) }
            .filter { $0.union > 0 && 2 * $0.shared >= $0.union }
            .max { $0.shared * $1.union < $1.shared * $0.union }
        let id: UInt64
        if let best {
            id = list[best.index].id
            list[best.index].windowIDs = windowIDs
        } else {
            id = Self.syntheticBase | next
            next += 1
            list.append(Cluster(id: id, windowIDs: windowIDs))
        }
        clusters[display] = list
        last[display] = id
        return id
    }

    /// A closed window leaves every visited Space.
    public mutating func forget(windowID: UInt32) {
        for display in clusters.keys {
            for index in clusters[display, default: []].indices { clusters[display]?[index].windowIDs.remove(windowID) }
        }
    }
}

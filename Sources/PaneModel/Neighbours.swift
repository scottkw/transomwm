import Foundation

/// The boundary between children `index` and `index + 1` of `split`.
public struct TreeBoundary: Equatable, Sendable {
    public let split: NodeID
    public let index: Int

    public init(split: NodeID, index: Int) {
        self.split = split
        self.index = index
    }
}

/// Which tile lies across an edge, for the direction commands (D-11, TILE-13), and which split boundary
/// an edge drag moves (D-07).
public enum Neighbours {
    /// The nearest placed leaf (the Desktop tile included) across `edge` of `rect`, or nil. A candidate must
    /// start past `rect`'s edge, less `gap + 1` pt of slack, and overlap it on the perpendicular axis by
    /// more than 0. The smallest edge distance wins; ties go to the earliest entry of `recency`, then the
    /// smaller NodeID. `excluding` is the leaf `rect` belongs to; nil for a floating window's frame.
    public static func neighbour(
        of rect: Rect, excluding leaf: NodeID?, toward edge: Edge, tree: LayoutTree, resolution: Resolution, gap: Double, recency: [NodeID]
    ) -> NodeID? {
        let slack = gap + 1
        var best: (distance: Double, rank: Int, id: NodeID)?
        for (id, other) in resolution.nodeRects where id != leaf {
            if case .split? = tree.node(id) { continue }
            let distance: Double
            let overlap: Double
            switch edge {
            case .right: distance = other.minX - rect.maxX
            case .left: distance = rect.minX - other.maxX
            case .bottom: distance = other.minY - rect.maxY
            case .top: distance = rect.minY - other.maxY
            }
            switch edge.axis {
            case .horizontal: overlap = min(rect.maxY, other.maxY) - max(rect.minY, other.minY)
            case .vertical: overlap = min(rect.maxX, other.maxX) - max(rect.minX, other.minX)
            }
            guard distance >= -slack, overlap > 0 else { continue }
            let candidate = (distance, recency.firstIndex(of: id) ?? Int.max, id)
            if best.map({ candidate < $0 }) ?? true { best = candidate }
        }
        return best?.id
    }

    /// The split boundary on `edge` of `leaf`: the nearest ancestor split laying children along that edge's
    /// axis where the path child has a sibling on that side. Nil for an outer edge (D-07).
    public static func boundary(for leaf: NodeID, edge: Edge, in tree: LayoutTree) -> TreeBoundary? {
        var child = leaf
        // A valid tree is at most maxDepth deep, so this walks at most that many parents.
        while let parent = tree.parent(of: child) {
            if case let .split(axis, children, _)? = tree.node(parent), axis == edge.axis, let i = children.firstIndex(of: child) {
                if edge.isLeading, i > 0 { return TreeBoundary(split: parent, index: i - 1) }
                if !edge.isLeading, i < children.count - 1 { return TreeBoundary(split: parent, index: i) }
            }
            child = parent
        }
        return nil
    }
}

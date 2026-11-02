import Foundation

/// Where on a tile a drop lands (D-20): an edge band docks beside the tile, the centre makes a tab group.
public enum DropZone: Equatable, Sendable {
    case edge(Edge)
    case center
}

public enum DropTarget: Equatable, Sendable {
    case tile(NodeID, DropZone)
    /// Dock along the whole layout's edge.
    case layoutEdge(Edge)
    /// The tree is empty: the drop becomes the root.
    case emptyLayout
}

public enum DropZones {
    // Starting values from yabai; tuned in UAT once drag previews exist (Phase 3).
    /// Outer fraction of a tile on each side that counts as its edge; the middle 50% is the centre.
    public static let edgeBandFraction: Double = 0.25
    /// Points from the area edge that target the whole layout's edge.
    public static let displayEdgeBand: Double = 24

    /// The drop target under `point`, or nil in a gap, over an unplaced tile, or outside `area`.
    public static func target(at point: Point, in area: Rect, tree: LayoutTree, resolution: Resolution) -> DropTarget? {
        guard area.contains(point) else { return nil }
        guard tree.root != nil else { return .emptyLayout }

        let horizontal = min(point.x - area.minX, area.maxX - point.x)
        let vertical = min(point.y - area.minY, area.maxY - point.y)
        if min(horizontal, vertical) < displayEdgeBand {
            return .layoutEdge(horizontal <= vertical
                ? (point.x < area.midX ? .left : .right)
                : (point.y < area.midY ? .top : .bottom))
        }

        // Leaf rects never overlap, so at most one contains the point. Split rects cover the gaps.
        guard let (id, rect) = resolution.nodeRects.first(where: { id, rect in
            if case .split? = tree.node(id) { return false }
            return rect.contains(point)
        }) else { return nil }

        let fx = (point.x - rect.minX) / rect.width
        let fy = (point.y - rect.minY) / rect.height
        let centre = edgeBandFraction...(1 - edgeBandFraction)
        if centre.contains(fx) && centre.contains(fy) { return .tile(id, .center) }
        if min(fx, 1 - fx) <= min(fy, 1 - fy) { return .tile(id, .edge(fx < 0.5 ? .left : .right)) }
        return .tile(id, .edge(fy < 0.5 ? .top : .bottom))
    }
}

extension LayoutTree {
    /// Turns a hit-test result into its edit (D-20). A plain mapping: the edits' own checks and
    /// all-or-nothing commit apply, so a target gone stale since the hit test throws and changes nothing.
    public mutating func applyDrop(_ target: DropTarget, window: WindowRef, ids: inout IDSource) throws(LayoutError) {
        switch target {
        case .emptyLayout: try insertRoot(window, ids: &ids)
        case let .tile(node, .edge(edge)): try insert(window, at: edge, of: node, ids: &ids)
        case let .tile(node, .center): try group(window, into: node)
        case let .layoutEdge(edge):
            if let root { try insert(window, at: edge, of: root, ids: &ids) } else { try insertRoot(window, ids: &ids) }
        }
    }
}

extension LayoutTree {
    /// `applyDrop` for a whole leaf (a panel or a tab group) with its members' states (Pattern 9). A centre throws:
    /// groups never merge (UI-SPEC Surface 1).
    public mutating func applyDrop(
        _ target: DropTarget, leaf node: Node, states: [WindowIdentity: WindowState], ids: inout IDSource
    ) throws(LayoutError) {
        switch target {
        case .emptyLayout: try insertRootLeaf(node, states: states, ids: &ids)
        case let .tile(id, .edge(edge)): try insertLeaf(node, states: states, at: edge, of: id, ids: &ids)
        case let .tile(id, .center): throw .notALeaf(id)
        case let .layoutEdge(edge):
            if let root { try insertLeaf(node, states: states, at: edge, of: root, ids: &ids) } else { try insertRootLeaf(node, states: states, ids: &ids) }
        }
    }
}

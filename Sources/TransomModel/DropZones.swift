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
    /// A share of the whole desk along an axis (D-14).
    case fourth(FourthSlot, Axis)
    /// A corner quarter of the whole desk (8.1.1 D-17).
    case corner(DockCorner)
    /// An empty area (8.1.1 D-16): the drop takes its place.
    case fill(NodeID)
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
        guard let root = tree.root else { return .emptyLayout }

        // Leaf rects never overlap, so at most one contains the point. Split rects cover the gaps.
        func leaf(at p: Point) -> (NodeID, Rect)? {
            resolution.nodeRects.first { id, rect in
                if case .split? = tree.node(id) { return false }
                return rect.contains(p)
            }
        }
        // An empty area is filled from anywhere over it; in the outer gap a point belongs to the leaf nearest it (E6).
        let inner = resolution.nodeRects[root]
        let probe = inner.map { Point(x: min(max(point.x, $0.minX), $0.maxX.nextDown), y: min(max(point.y, $0.minY), $0.maxY.nextDown)) }
        if let (id, _) = leaf(at: probe ?? point), tree.node(id) == .spacer { return .fill(id) }

        let horizontal = min(point.x - area.minX, area.maxX - point.x)
        let vertical = min(point.y - area.minY, area.maxY - point.y)
        if min(horizontal, vertical) < displayEdgeBand {
            return .layoutEdge(horizontal <= vertical
                ? (point.x < area.midX ? .left : .right)
                : (point.y < area.midY ? .top : .bottom))
        }

        guard let (id, rect) = leaf(at: point) else { return nil }

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
        case let .fourth(slot, axis):
            try insertFourth(.panel(window), states: [window.identity: .present], slot: slot, axis: axis, ids: &ids)
        case let .corner(corner): try insertCorner(.panel(window), states: [window.identity: .present], corner: corner, ids: &ids)
        case let .fill(id): try fill(id, with: .panel(window), states: [window.identity: .present])
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
        case let .fourth(slot, axis): try insertFourth(node, states: states, slot: slot, axis: axis, ids: &ids)
        case let .corner(corner): try insertCorner(node, states: states, corner: corner, ids: &ids)
        case let .fill(id): try fill(id, with: node, states: states)
        }
    }
}

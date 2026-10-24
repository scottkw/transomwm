import Foundation

public enum DropZone: Equatable, Sendable {
    case edge(Edge)
    case center
}

public enum DropTarget: Equatable, Sendable {
    case tile(NodeID, DropZone)
    case layoutEdge(Edge)
    case emptyLayout
}

public enum DropZones {
    public static let edgeBandFraction: Double = 0.25
    public static let displayEdgeBand: Double = 24

    public static func target(at point: Point, in area: Rect, tree: LayoutTree, resolution: Resolution) -> DropTarget? {
        nil
    }
}

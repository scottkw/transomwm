import PaneModel

/// One draggable gap between two taking-part children of a split (UI-SPEC Surface 3), in global top-left points.
/// `first` and `second` are child indices of `split`; a minimised child between them keeps its weight (Pitfall 9).
public struct GapHandle: Equatable, Sendable {
    public let split: NodeID
    public let first: Int
    public let second: Int
    /// The split's axis: horizontal means a left-right resize.
    public let axis: Axis
    public let rect: Rect

    public init(split: NodeID, first: Int, second: Int, axis: Axis, rect: Rect) {
        self.split = split
        self.first = first
        self.second = second
        self.axis = axis
        self.rect = rect
    }
}

/// Where the gap handles go (TILE-05): pure geometry from a resolved layout.
public enum GapHandles {
    public static func handles(tree: LayoutTree, resolution: Resolution, gap: Double) -> [GapHandle] {
        []
    }
}

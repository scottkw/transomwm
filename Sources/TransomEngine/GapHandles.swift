import TransomModel

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
    /// Below this gap there are no handles; edge drags still resize (UI-SPEC Surface 3).
    public static let minimumGap = 4.0

    /// For each split, the strip between consecutive taking-part children (skipping children with no rect), across the
    /// split's own rect: a nested handle stops at its parent's edge, so at a T-junction the parent's runs through.
    /// Outer gaps are not boundaries and get none. Ordered by split, then child.
    public static func handles(tree: LayoutTree, resolution: Resolution, gap: Double) -> [GapHandle] {
        guard gap >= minimumGap else { return [] }
        var found: [GapHandle] = []
        for (id, rect) in resolution.nodeRects {
            guard case .split(let axis, let children, _)? = tree.node(id) else { continue }
            let taking = children.indices.compactMap { i in resolution.nodeRects[children[i]].map { (index: i, rect: $0) } }
            for (p, q) in zip(taking, taking.dropFirst()) {
                let strip = axis == .horizontal
                    ? Rect(x: p.rect.maxX, y: rect.minY, width: q.rect.minX - p.rect.maxX, height: rect.height)
                    : Rect(x: rect.minX, y: p.rect.maxY, width: rect.width, height: q.rect.minY - p.rect.maxY)
                guard strip.width > 0, strip.height > 0 else { continue }
                found.append(GapHandle(split: id, first: p.index, second: q.index, axis: axis, rect: strip))
            }
        }
        return found.sorted { ($0.split, $0.first) < ($1.split, $1.first) }
    }
}

import Foundation

/// Where a fourth lands along an axis (D-11): one of four equal spans, or the middle half.
public enum FourthSlot: String, CaseIterable, Hashable, Sendable {
    case first, second, third, fourth, middle

    /// The slot's span as fractions of the axis, 0 being the left edge or the top.
    var span: (start: Double, end: Double) {
        switch self {
        case .first: (0, 0.25)
        case .second: (0.25, 0.5)
        case .third: (0.5, 0.75)
        case .fourth: (0.75, 1)
        case .middle: (0.25, 0.75)
        }
    }
}

/// The drag's five bands across a display's visible frame (UI-SPEC Surface 3), the middle one being the central quarter.
public enum FourthZones {
    private static let bands: [(end: Double, slot: FourthSlot)] = [
        (0.25, .first), (0.375, .second), (0.625, .middle), (0.75, .third), (1, .fourth),
    ]

    /// The band under `point`, clamped into `visible`.
    public static func slot(at point: Point, in visible: Rect, axis: Axis) -> FourthSlot {
        let raw = axis == .horizontal ? (point.x - visible.minX) / visible.width : (point.y - visible.minY) / visible.height
        return bands.first { raw < $0.end }?.slot ?? .fourth
    }

    /// The five bands in hit order along `axis`, each the whole cross-axis length.
    public static func bands(in visible: Rect, axis: Axis) -> [Rect] {
        var start = 0.0
        return bands.map { band in
            defer { start = band.end }
            return axis == .horizontal
                ? Rect(x: visible.minX + start * visible.width, y: visible.y, width: (band.end - start) * visible.width, height: visible.height)
                : Rect(x: visible.x, y: visible.minY + start * visible.height, width: visible.width, height: (band.end - start) * visible.height)
        }
    }
}

extension LayoutTree {
    /// D-14: `node` takes `slot`'s share of the whole desk at the root, and a root split the other way becomes one child
    /// of a new root. The caller has already taken the window off the desk. All-or-nothing, like every tree edit.
    public mutating func insertFourth(
        _ node: Node, states: [WindowIdentity: WindowState], slot: FourthSlot, axis: Axis, ids: inout IDSource
    ) throws(LayoutError) {
        guard let root else { return try insertRootLeaf(node, states: states, ids: &ids) }
        let (children, weights): ([NodeID], [Double]) =
            if case let .split(rootAxis, c, w)? = nodes[root], rootAxis == axis { (c, w) } else { ([root], [1]) }
        let (index, shares) = Self.fourthShares(weights: weights, takesPart: children.map(takesPart), span: slot.span)
        var next = self
        var nextIDs = ids
        let leading: Edge = axis == .horizontal ? .left : .top
        let trailing: Edge = axis == .horizontal ? .right : .bottom
        if index < children.count {
            try next.insertLeaf(node, states: states, at: leading, of: children[index], ids: &nextIDs)
        } else {
            try next.insertLeaf(node, states: states, at: trailing, of: children[children.count - 1], ids: &nextIDs)
        }
        guard let newRoot = next.root else { throw .invariantViolated("a fourth left no root") }
        try next.setWeights(in: newRoot, shares)
        self = next
        ids = nextIDs
    }

    /// Mirrors `Solver.aggregate`: whether a node gets any space when resolved.
    func takesPart(_ id: NodeID) -> Bool {
        switch nodes[id] {
        case let .panel(window)?: state(of: window) == .present
        case let .tabs(windows, selected)?: state(of: windows[selected]) == .present
        case let .desktop(hidden)?: !hidden
        case let .split(_, children, _)?: children.contains(where: takesPart)
        case nil: false
        }
    }

    /// The insertion index and the new weights, the window's at that index. Children not taking part keep their stored
    /// weight and the rest share what they leave, so positions are worked out over the children taking part only.
    private static func fourthShares(
        weights: [Double], takesPart: [Bool], span: (start: Double, end: Double)
    ) -> (index: Int, shares: [Double]) {
        let room = weights.indices.reduce(0) { takesPart[$1] ? $0 + weights[$1] : $0 }
        var index = weights.count
        if span.start == 0 {
            index = 0
        } else if span.end != 1 {
            // A tile centred exactly at the window's position goes after it (D-14).
            let position = (span.start + span.end) / 2
            var earlier = 0.0
            for i in weights.indices where takesPart[i] {
                if (earlier + weights[i] / 2) / room >= position - 1e-9 {
                    index = i
                    break
                }
                earlier += weights[i]
            }
        }
        let before = weights.indices.reduce(0) { $1 < index && takesPart[$1] ? $0 + weights[$1] : $0 }
        let after = room - before
        // An empty side has no tile to fill it, so the window grows into that space (D-14).
        let start = before > 0 ? span.start : 0
        let end = after > 0 ? span.end : 1
        var shares = weights.indices.map { i -> Double in
            guard takesPart[i] else { return weights[i] }
            return (i < index ? start / before : (1 - end) / after) * weights[i] * room
        }
        // Nothing else taking part leaves no room to scale into: the window fills the desk once resolved.
        shares.insert(max((end - start) * room, minWeight), at: index)
        return (index, shares)
    }
}

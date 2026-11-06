import Foundation

/// Where a share of the whole desk lands along an axis: one of four equal spans or the middle half (08.1 D-11), or a half
/// or a third (8.1.1 D-10). Halves and thirds have no drag band (`FourthZones` keeps its five).
public enum FourthSlot: String, CaseIterable, Hashable, Sendable {
    case first, second, third, fourth, middle
    case firstHalf, secondHalf, firstThird, middleThird, lastThird

    /// Defined once so every third is the same constant.
    public static let oneThird = 1.0 / 3
    public static let twoThirds = 2.0 / 3

    /// The slot's span as fractions of the axis, 0 being the left edge or the top.
    public var span: (start: Double, end: Double) {
        switch self {
        case .first: (0, 0.25)
        case .second: (0.25, 0.5)
        case .third: (0.5, 0.75)
        case .fourth: (0.75, 1)
        case .middle: (0.25, 0.75)
        case .firstHalf: (0, 0.5)
        case .secondHalf: (0.5, 1)
        case .firstThird: (0, Self.oneThird)
        case .middleThird: (Self.oneThird, Self.twoThirds)
        case .lastThird: (Self.twoThirds, 1)
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

/// One part of a desk's length along an axis, for `insertFourth`. Tiles and empty areas are measured as fractions of the
/// length the children taking part share; a child not taking part keeps its stored weight.
enum FourthPiece: Equatable {
    case tile(NodeID, Double)
    case empty(Double)
    case absent(NodeID, Double)
    case window(Double)
}

extension LayoutTree {
    /// `node` takes exactly `slot`'s span of the whole desk along `axis` (8.1.1 D-16, rule E1). The caller has already
    /// taken the window off the desk. All-or-nothing, like every tree edit.
    public mutating func insertFourth(
        _ node: Node, states: [WindowIdentity: WindowState], slot: FourthSlot, axis: Axis, ids: inout IDSource
    ) throws(LayoutError) {
        try checkNewLeaf(node)
        var next = self
        var nextIDs = ids
        func make() throws(LayoutError) -> NodeID {
            // IDSource is public and not tied to the tree, so a lagging one must not overwrite a node.
            let id = try nextIDs.make()
            guard next.nodes[id] == nil else { throw .invariantViolated("ID source issued \(id), which is already in the tree") }
            return id
        }
        var pieces: [FourthPiece] = []
        var basis = 1.0
        var rootID: NodeID?
        if let root {
            if case let .split(rootAxis, children, weights)? = nodes[root], rootAxis == axis {
                rootID = root
                let room = zip(children, weights).reduce(0) { takesPart($1.0) ? $0 + $1.1 : $0 }
                // Nothing taking part leaves no room to scale into: the window's share of the stored total keeps it from
                // being a sliver when the others return (WR-07).
                basis = room > 0 ? room : weights.reduce(0, +)
                for (child, weight) in zip(children, weights) {
                    if !takesPart(child) {
                        pieces.append(.absent(child, weight))
                    } else if nodes[child] == .spacer {
                        pieces.append(.empty(weight / room))
                        next.nodes[child] = nil
                    } else {
                        pieces.append(.tile(child, weight / room))
                    }
                }
            } else {
                pieces = [takesPart(root) ? .tile(root, 1) : .absent(root, 1)]
            }
        }
        var children: [NodeID] = []
        var weights: [Double] = []
        for piece in Self.fourthPieces(pieces, span: slot.span) {
            switch piece {
            case let .tile(id, length):
                children.append(id)
                weights.append(length * basis)
            case let .absent(id, weight):
                children.append(id)
                weights.append(weight)
            case let .empty(length):
                let id = try make()
                next.nodes[id] = .spacer
                children.append(id)
                weights.append(length * basis)
            case let .window(length):
                let id = try make()
                next.nodes[id] = node
                children.append(id)
                weights.append(length * basis)
            }
        }
        let id: NodeID
        if let rootID { id = rootID } else { id = try make() }
        let sum = weights.reduce(0, +)
        next.nodes[id] = .split(axis: axis, children: children, weights: weights.map { $0 / sum })
        next.root = id
        next.states.merge(states) { $1 }
        next.normalize()
        if let root = next.root, case let .split(_, children, _)? = next.nodes[root], children.count > Self.maxChildren {
            throw .splitFull(root, limit: Self.maxChildren)
        }
        try next.validate()
        self = next
        ids = nextIDs
    }

    /// Mirrors `Solver.aggregate`: whether a node gets any space when resolved. Only docked tiles count (D-04).
    func takesPart(_ id: NodeID) -> Bool {
        switch nodes[id] {
        case let .panel(window)?: state(of: window) == .present
        case let .tabs(windows, selected)?: state(of: windows[selected]) == .present
        case let .split(_, children, _)?: children.contains(where: takesPart)
        case .spacer?: true
        case nil: false
        }
    }

    /// The pieces in their new order, the window's exactly `span` (8.1.1 D-16). Empty areas under the span are used up
    /// first (E2). A tile goes after the window when the span starts the axis, before it when the span ends it, and
    /// otherwise by its centre (one centred exactly at the window's goes after, D-14). Each side then fits its room: too
    /// long, its empty areas shrink first and then its tiles shrink proportionally (E2); too short, the rest stays an
    /// empty area beside the window, so nothing grows (E3). Pieces not taking part stay with the piece before them.
    static func fourthPieces(_ pieces: [FourthPiece], span: (start: Double, end: Double)) -> [FourthPiece] {
        let (a, b) = span
        let centre = (a + b) / 2
        var before: [FourthPiece] = []
        var after: [FourthPiece] = []
        var position = 0.0
        var toAfter = a == 0
        for piece in pieces {
            switch piece {
            case let .empty(length):
                let (start, end) = (position, position + length)
                position = end
                if start < a { before.append(.empty(min(end, a) - start)) }
                if end > b {
                    after.append(.empty(end - max(start, b)))
                    toAfter = true
                }
            case let .tile(_, length):
                toAfter = a == 0 || (b != 1 && position + length / 2 >= centre - 1e-9)
                position += length
                if toAfter { after.append(piece) } else { before.append(piece) }
            case .absent, .window:
                if toAfter { after.append(piece) } else { before.append(piece) }
            }
        }
        return fitted(before, room: a, windowAfter: true) + [.window(b - a)] + fitted(after, room: 1 - b, windowAfter: false)
    }

    private static func fitted(_ side: [FourthPiece], room: Double, windowAfter: Bool) -> [FourthPiece] {
        func length(_ piece: FourthPiece, empty: Bool) -> Double {
            switch piece {
            case let .empty(l): empty ? l : 0
            case let .tile(_, l): empty ? 0 : l
            default: 0
            }
        }
        let empties = side.reduce(0) { $0 + length($1, empty: true) }
        let tiles = side.reduce(0) { $0 + length($1, empty: false) }
        var result = side
        if empties + tiles > room + 1e-9 {
            let excess = empties + tiles - room
            let emptyScale = empties >= excess ? (empties - excess) / empties : 0
            let tileScale = empties >= excess ? 1 : room / tiles
            result = side.map { piece in
                switch piece {
                case let .empty(l): .empty(l * emptyScale)
                case let .tile(id, l): .tile(id, l * tileScale)
                default: piece
                }
            }
        } else if room - empties - tiles > 1e-9 {
            let rest = FourthPiece.empty(room - empties - tiles)
            if windowAfter { result.append(rest) } else { result.insert(rest, at: 0) }
        }
        // A sliver of empty area is no area.
        return result.filter { if case let .empty(l) = $0 { l >= minWeight } else { true } }
    }
}

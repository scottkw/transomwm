import Foundation

public struct Resolution: Equatable, Sendable {
    public var nodeRects: [NodeID: Rect]
    public var windowRects: [WindowRef: Rect]
    /// Windows that cannot fit without overlapping; they get no rect.
    public var unfit: Set<WindowRef>

    public init(nodeRects: [NodeID: Rect] = [:], windowRects: [WindowRef: Rect] = [:], unfit: Set<WindowRef> = []) {
        self.nodeRects = nodeRects
        self.windowRects = windowRects
        self.unfit = unfit
    }
}

/// Lays the tree out in `area` with one `gap` between tiles and around the outer edge (D-12).
/// The area is snapped inward to whole points and the gap rounded, so every rect is whole points;
/// along a split each child but the last gets floor(weight × length) and the last absorbs the
/// remainder (D-13). Every tab of a tabs leaf gets the leaf's rect.
public func resolve(_ tree: LayoutTree, in area: Rect, mins: [WindowRef: Size], gap: Double) throws(LayoutError) -> Resolution {
    var result = Resolution()
    guard let root = tree.root else { return result }
    let gap = gap.rounded()
    let minX = area.minX.rounded(.up) + gap
    let minY = area.minY.rounded(.up) + gap
    let inner = Rect(
        x: minX, y: minY,
        width: max(0, area.maxX.rounded(.down) - gap - minX),
        height: max(0, area.maxY.rounded(.down) - gap - minY))

    var stack = [(id: root, rect: inner)]
    while let (id, rect) = stack.popLast() {
        result.nodeRects[id] = rect
        guard let node = tree.node(id) else { throw .nodeNotFound(id) }
        switch node {
        case let .split(axis, children, weights):
            let horizontal = axis == .horizontal
            let length = max(0, (horizontal ? rect.width : rect.height) - gap * Double(children.count - 1))
            var offset = horizontal ? rect.minX : rect.minY
            var used = 0.0
            for (i, child) in children.enumerated() {
                let size = i == children.count - 1 ? length - used : (weights[i] * length).rounded(.down)
                used += size
                stack.append((child, horizontal
                    ? Rect(x: offset, y: rect.minY, width: size, height: rect.height)
                    : Rect(x: rect.minX, y: offset, width: rect.width, height: size)))
                offset += size + gap
            }
        case let .panel(window):
            result.windowRects[window] = rect
        case let .tabs(windows, _):
            for window in windows { result.windowRects[window] = rect }
        }
    }
    return result
}

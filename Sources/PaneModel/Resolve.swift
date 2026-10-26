import Foundation

// resolve never changes stored weights: minimum sizes adjust the geometry, not the user's intent, so
// the layout springs back once a window's minimum shrinks or the area grows. Windows that cannot fit
// come back in `unfit`; Phase 4 shows them as represented (a snapshot) instead of overlapping them.

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

    /// The Desktop tile's rect; nil when the tree has none or it is hidden.
    public var desktopRect: Rect? { nodeRects[.desktop] }
}

/// Lays the tree out in `area` with one `gap` between tiles and around the outer edge (D-12).
///
/// - Only `.present` windows take part (D-17). Absent and fullscreen windows keep their node but get
///   no rect and are not unfit; a leaf takes part while one of its windows does, a split while one
///   child does, and the taking-part children of a split share its length by their stored weights.
/// - Every present window gets at least its minimum (rounded up, at least 1×1) by water-filling
///   (D-10). While the minimums cannot fit, the window with the largest minimum on the violated axis
///   (area when both are) becomes unfit; ties go to the larger leaf NodeID, then the larger
///   WindowIdentity. Victims are then re-admitted in removal order wherever they fit (D-11).
/// - The area is snapped inward to whole points and the gap rounded, so every rect is whole points;
///   along a split each child but the last gets floor(share) and the last the remainder (D-13).
public func resolve(
    _ tree: LayoutTree, in area: Rect, mins: [WindowRef: Size], gap: Double, desktopMinimum: Size = Size(width: 1, height: 1)
) throws(LayoutError) -> Resolution {
    guard area.isValidGeometry else { throw .invalidGeometry("area") }
    guard gap.isFinite, gap >= 0, gap <= Geometry.maxCoordinate else { throw .invalidGap }
    let isValid = { (s: Size) in [s.width, s.height].allSatisfy { $0.isFinite && $0 >= 0 && $0 <= Geometry.maxCoordinate } }
    // The smallest bad identity, so the error does not depend on dictionary order.
    if let bad = mins.filter({ !isValid($0.value) }).keys.min(by: { $0.identity < $1.identity }) {
        throw .invalidMinimum(bad)
    }

    var result = Resolution()
    guard let root = tree.root else { return result }
    let gap = gap.rounded()
    let minX = area.minX.rounded(.up) + gap
    let minY = area.minY.rounded(.up) + gap
    let inner = Rect(
        x: minX, y: minY,
        width: max(0, area.maxX.rounded(.down) - gap - minX),
        height: max(0, area.maxY.rounded(.down) - gap - minY))

    var solver = Solver(tree: tree, gap: gap)
    var candidates: [(leaf: NodeID, window: WindowRef, min: Size)] = []
    for (id, node) in tree.nodes {
        let windows: [WindowRef]
        switch node {
        case let .panel(window): windows = [window]
        case let .tabs(tabs, _): windows = tabs
        case .split, .desktop: continue
        }
        for window in windows where tree.state(of: window) == .present {
            let min = mins[window] ?? Size(width: 1, height: 1)
            let effective = Size(width: max(1, min.width.rounded(.up)), height: max(1, min.height.rounded(.up)))
            solver.minimum[window] = effective
            candidates.append((id, window, effective))
        }
    }
    solver.active = Set(candidates.map(\.window))

    func fits() throws(LayoutError) -> Bool {
        guard let need = try solver.aggregate(root) else { return true }
        return need.width <= inner.width && need.height <= inner.height
    }

    // Each pass removes one window, so this ends after at most one pass per present window.
    var removed: [WindowRef] = []
    while let need = try solver.aggregate(root), need.width > inner.width || need.height > inner.height {
        let wide = need.width > inner.width, tall = need.height > inner.height
        func key(_ s: Size) -> Double { wide && tall ? s.width * s.height : wide ? s.width : s.height }
        let victim = candidates.filter { solver.active.contains($0.window) }.max { l, r in
            (key(l.min), l.leaf, l.window.identity) < (key(r.min), r.leaf, r.window.identity)
        }!
        solver.active.remove(victim.window)
        removed.append(victim.window)
    }
    // Maximality: never leave out a window that fits with the ones already placed.
    for window in removed {
        solver.active.insert(window)
        if try !fits() {
            solver.active.remove(window)
            result.unfit.insert(window)
        }
    }

    if try solver.aggregate(root) != nil { try solver.place(root, in: inner, into: &result) }
    return result
}

private struct Solver {
    let tree: LayoutTree
    let gap: Double
    var minimum: [WindowRef: Size] = [:]
    var active: Set<WindowRef> = []

    private func node(_ id: NodeID) throws(LayoutError) -> Node {
        guard let node = tree.node(id) else { throw .nodeNotFound(id) }
        return node
    }

    /// The smallest size the node can take with its active windows, or nil if it does not take part.
    /// Recursive: validated trees are at most `LayoutTree.maxDepth` deep.
    func aggregate(_ id: NodeID) throws(LayoutError) -> Size? {
        switch try node(id) {
        case let .panel(window):
            return active.contains(window) ? minimum[window] : nil
        case let .tabs(windows, _):
            // Tabs share one rect, so it must fit the largest of them on each axis.
            let sizes = windows.filter(active.contains).compactMap { minimum[$0] }
            guard !sizes.isEmpty else { return nil }
            return Size(width: sizes.map(\.width).max()!, height: sizes.map(\.height).max()!)
        case .desktop:
            return nil
        case let .split(axis, children, _):
            var sizes: [Size] = []
            for child in children { if let size = try aggregate(child) { sizes.append(size) } }
            guard !sizes.isEmpty else { return nil }
            let gaps = gap * Double(sizes.count - 1)
            return axis == .horizontal
                ? Size(width: sizes.map(\.width).reduce(gaps, +), height: sizes.map(\.height).max()!)
                : Size(width: sizes.map(\.width).max()!, height: sizes.map(\.height).reduce(gaps, +))
        }
    }

    /// Lays out a taking-part node in `rect`, which the fit check guarantees is at least its aggregate.
    func place(_ id: NodeID, in rect: Rect, into result: inout Resolution) throws(LayoutError) {
        result.nodeRects[id] = rect
        switch try node(id) {
        case let .panel(window):
            result.windowRects[window] = rect
        case let .tabs(windows, _):
            for window in windows where active.contains(window) { result.windowRects[window] = rect }
        case .desktop:
            break
        case let .split(axis, children, weights):
            var parts: [(id: NodeID, weight: Double, min: Double)] = []
            let horizontal = axis == .horizontal
            for (child, weight) in zip(children, weights) {
                if let size = try aggregate(child) { parts.append((child, weight, horizontal ? size.width : size.height)) }
            }
            let available = (horizontal ? rect.width : rect.height) - gap * Double(parts.count - 1)

            // Water-filling: pin every child whose weighted share is below its minimum, share what is
            // left among the rest, repeat until nothing new is pinned (at most one pass per child).
            var share = parts.map(\.min)
            var pinned = Array(repeating: false, count: parts.count)
            while true {
                let free = available - parts.indices.filter { pinned[$0] }.reduce(0) { $0 + parts[$1].min }
                let weight = parts.indices.filter { !pinned[$0] }.reduce(0) { $0 + parts[$1].weight }
                guard weight > 0 else { break }
                var changed = false
                for i in parts.indices where !pinned[i] {
                    share[i] = free * parts[i].weight / weight
                    if share[i] < parts[i].min {
                        share[i] = parts[i].min
                        pinned[i] = true
                        changed = true
                    }
                }
                if !changed { break }
            }

            var offset = horizontal ? rect.minX : rect.minY
            var used = 0.0
            for (i, part) in parts.enumerated() {
                let size = i == parts.count - 1 ? available - used : share[i].rounded(.down)
                used += size
                try place(part.id, in: horizontal
                    ? Rect(x: offset, y: rect.minY, width: size, height: rect.height)
                    : Rect(x: rect.minX, y: offset, width: rect.width, height: size), into: &result)
                offset += size + gap
            }
        }
    }
}

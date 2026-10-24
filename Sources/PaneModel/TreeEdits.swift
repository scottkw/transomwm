import Foundation

// Every edit works on copies of the tree and the ID source and commits both only on success,
// so a throwing edit leaves no trace.
extension LayoutTree {
    public mutating func insertRoot(_ window: WindowRef, ids: inout IDSource) throws(LayoutError) {
        guard root == nil else { throw .treeNotEmpty }
        var next = self
        var nextIDs = ids
        let leaf = nextIDs.make()
        next.root = leaf
        next.nodes[leaf] = .panel(window)
        next.states[window.identity] = .present
        self = next
        ids = nextIDs
        assertValid()
    }

    /// Docks `window` on `edge` of `target`. Rules, first match wins:
    /// 1. the target's parent splits on the edge's axis: the window becomes the target's sibling;
    /// 2. the target itself splits on that axis: the window becomes its first or last child;
    /// 3. otherwise the target's slot gets a new split holding the target and the window, 0.5 / 0.5.
    /// Rules 1 and 2 give the new child 1/(n+1) and scale the others by n/(n+1) (D-04).
    /// None of the rules creates a split whose child splits on the same axis.
    public mutating func insert(_ window: WindowRef, at edge: Edge, of target: NodeID, ids: inout IDSource) throws(LayoutError) {
        guard states[window.identity] == nil else { throw .duplicateWindow(window) }
        guard let targetNode = nodes[target] else { throw .nodeNotFound(target) }
        let axis = edge.axis
        var next = self
        var nextIDs = ids
        let leaf = nextIDs.make()
        next.nodes[leaf] = .panel(window)
        next.states[window.identity] = .present

        let parent = parent(of: target)
        let parentSplit = parent.flatMap { id -> (axis: Axis, children: [NodeID], weights: [Double])? in
            if case let .split(a, c, w) = nodes[id] { return (a, c, w) }
            return nil
        }
        if let parent, let parentSplit, parentSplit.axis == axis {
            let index = parentSplit.children.firstIndex(of: target)! + (edge.isLeading ? 0 : 1)
            next.nodes[parent] = try Self.adding(leaf, at: index, to: parent, parentSplit.axis, parentSplit.children, parentSplit.weights)
        } else if case let .split(targetAxis, children, weights) = targetNode, targetAxis == axis {
            let index = edge.isLeading ? 0 : children.count
            next.nodes[target] = try Self.adding(leaf, at: index, to: target, targetAxis, children, weights)
        } else {
            let split = nextIDs.make()
            next.nodes[split] = .split(axis: axis, children: edge.isLeading ? [leaf, target] : [target, leaf], weights: [0.5, 0.5])
            if let parent, let parentSplit {
                let children = parentSplit.children.map { $0 == target ? split : $0 }
                next.nodes[parent] = .split(axis: parentSplit.axis, children: children, weights: parentSplit.weights)
            } else {
                next.root = split
            }
        }

        try next.normalize()
        guard next.nodes.count <= Self.maxNodes else { throw .tooManyNodes(limit: Self.maxNodes) }
        guard next.depth(of: leaf) <= Self.maxDepth else { throw .tooDeep(limit: Self.maxDepth) }
        self = next
        ids = nextIDs
        assertValid()
    }

    /// Removes `window` (D-05). A panel's share goes back to its siblings in proportion to their
    /// weights; a tab group left with one window becomes a panel under the same NodeID.
    /// Throws `splitFull` if the collapse that follows would merge more than `maxChildren` children.
    public mutating func remove(_ window: WindowRef) throws(LayoutError) {
        guard let leaf = leaf(containing: window) else { throw .windowNotFound(window) }
        var next = self
        next.states[window.identity] = nil
        if case let .tabs(windows, selected)? = nodes[leaf] {
            var rest = windows
            let index = rest.firstIndex(of: window)!
            rest.remove(at: index)
            // Removing the selected tab selects the one that took its index, clamped to the last.
            next.nodes[leaf] = rest.count == 1
                ? .panel(rest[0])
                : .tabs(windows: rest, selected: index < selected ? selected - 1 : min(selected, rest.count - 1))
        } else {
            next.nodes[leaf] = nil
            if let parent = parent(of: leaf), case .split(let axis, var children, var weights)? = nodes[parent] {
                let index = children.firstIndex(of: leaf)!
                children.remove(at: index)
                weights.remove(at: index)
                // normalize() divides the rest by their sum: the proportional redistribution.
                next.nodes[parent] = .split(axis: axis, children: children, weights: weights)
            } else {
                next.root = nil
            }
        }
        try next.normalize()
        self = next
        assertValid()
    }

    /// D-06, run on the working copy of every edit. Collapses and merges repeat until a pass finds
    /// none; then each split's weights are renormalised and clamped. Iterative throughout.
    mutating func normalize() throws(LayoutError) {
        while try collapseOrMergeOnce() {}
        for (id, node) in nodes {
            if case let .split(axis, children, weights) = node, !Self.isNormalised(weights) {
                nodes[id] = .split(axis: axis, children: children, weights: Self.clamped(weights))
            }
        }
    }

    /// Applies the first collapse (a split with one child) or merge (a child split on its parent's
    /// axis) found walking down from the root. Returns false when there is none.
    private mutating func collapseOrMergeOnce() throws(LayoutError) -> Bool {
        var stack: [(id: NodeID, parent: NodeID?)] = root.map { [($0, nil)] } ?? []
        while let (id, parent) = stack.popLast() {
            guard case let .split(axis, children, weights)? = nodes[id] else { continue }
            if children.count == 1 {
                // The only child takes the split's slot, and with it the slot's weight.
                if let parent, case let .split(parentAxis, siblings, parentWeights)? = nodes[parent] {
                    nodes[parent] = .split(axis: parentAxis, children: siblings.map { $0 == id ? children[0] : $0 }, weights: parentWeights)
                } else {
                    root = children[0]
                }
                nodes[id] = nil
                return true
            }
            for (index, child) in children.enumerated() {
                guard case let .split(childAxis, grandchildren, childWeights)? = nodes[child], childAxis == axis else { continue }
                guard children.count - 1 + grandchildren.count <= Self.maxChildren else {
                    throw .splitFull(id, limit: Self.maxChildren)
                }
                var merged = children
                var mergedWeights = weights
                merged.replaceSubrange(index...index, with: grandchildren)
                mergedWeights.replaceSubrange(index...index, with: childWeights.map { $0 * weights[index] })
                nodes[id] = .split(axis: axis, children: merged, weights: mergedWeights)
                nodes[child] = nil
                return true
            }
            stack.append(contentsOf: children.map { ($0, id) })
        }
        return false
    }

    /// Already summing to 1 with every weight at or above the minimum; such weights are left
    /// bit-identical (D-07 relies on this).
    private static func isNormalised(_ weights: [Double]) -> Bool {
        weights.allSatisfy { $0 >= minWeight - 1e-12 } && abs(weights.reduce(0, +) - 1) <= 1e-12
    }

    /// Divides by the sum, then pins weights below `minWeight` to it and shares the rest of 1 among
    /// the others in proportion, until none is below. Terminates: the pinned set only grows, and
    /// maxChildren × minWeight == 1 leaves the unpinned weights an average of at least minWeight.
    private static func clamped(_ weights: [Double]) -> [Double] {
        let sum = weights.reduce(0, +)
        var result = weights.map { $0 / sum }
        var pinned: Set<Int> = []
        while true {
            let low = result.indices.filter { !pinned.contains($0) && result[$0] < minWeight }
            if low.isEmpty { return result }
            pinned.formUnion(low)
            let free = result.indices.filter { !pinned.contains($0) }
            let freeSum = free.reduce(0) { $0 + result[$1] }
            let share = 1 - Double(pinned.count) * minWeight
            for i in pinned { result[i] = minWeight }
            for i in free { result[i] = result[i] / freeSum * share }
        }
    }

    private static func adding(
        _ child: NodeID, at index: Int, to split: NodeID, _ axis: Axis, _ children: [NodeID], _ weights: [Double]
    ) throws(LayoutError) -> Node {
        guard children.count < maxChildren else { throw .splitFull(split, limit: maxChildren) }
        let n = Double(children.count)
        var children = children
        var weights = weights.map { $0 * n / (n + 1) }
        children.insert(child, at: index)
        weights.insert(1 / (n + 1), at: index)
        return .split(axis: axis, children: children, weights: weights)
    }
}

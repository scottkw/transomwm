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

        guard next.nodes.count <= Self.maxNodes else { throw .tooManyNodes(limit: Self.maxNodes) }
        guard next.depth(of: leaf) <= Self.maxDepth else { throw .tooDeep(limit: Self.maxDepth) }
        self = next
        ids = nextIDs
        assertValid()
    }

    public mutating func remove(_ window: WindowRef) throws(LayoutError) {}

    // shortcut: scaled weights can fall below minWeight when a sibling already sits near it;
    // Plan 01-02's normalize() adds the clamp.
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

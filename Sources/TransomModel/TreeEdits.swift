import Foundation

// Every edit works on copies of the tree and the ID source and commits both only on success,
// so a throwing edit leaves no trace.
extension LayoutTree {
    public mutating func insertRoot(_ window: WindowRef, ids: inout IDSource) throws(LayoutError) {
        try insertRootLeaf(.panel(window), states: [window.identity: .present], ids: &ids)
    }

    /// `insertRoot` for a whole leaf (a panel or a tab group) with its members' states.
    public mutating func insertRootLeaf(_ node: Node, states: [WindowIdentity: WindowState], ids: inout IDSource) throws(LayoutError) {
        guard root == nil else { throw .treeNotEmpty }
        try checkNewLeaf(node)
        var next = self
        var nextIDs = ids
        let leaf = try nextIDs.make()
        next.root = leaf
        next.nodes[leaf] = node
        next.states.merge(states) { $1 }
        try next.validate()  // the caller's states must match the leaf's members
        self = next
        ids = nextIDs
    }

    /// Docks `window` on `edge` of `target`. Rules, first match wins:
    /// 1. the target's parent splits on the edge's axis: the window becomes the target's sibling;
    /// 2. the target itself splits on that axis: the window becomes its first or last child;
    /// 3. otherwise the target's slot gets a new split holding the target and the window, 0.5 / 0.5.
    /// Rules 1 and 2 give the new child 1/(n+1) and scale the others by n/(n+1) (D-04).
    /// None of the rules creates a split whose child splits on the same axis.
    public mutating func insert(_ window: WindowRef, at edge: Edge, of target: NodeID, ids: inout IDSource) throws(LayoutError) {
        try insertLeaf(.panel(window), states: [window.identity: .present], at: edge, of: target, ids: &ids)
    }

    /// `insert` for a whole leaf, a panel or a tab group, with its members' states (Pattern 9: a group moves as one).
    /// Every member must be new to the tree.
    public mutating func insertLeaf(
        _ node: Node, states: [WindowIdentity: WindowState], at edge: Edge, of target: NodeID, ids: inout IDSource
    ) throws(LayoutError) {
        try checkNewLeaf(node)
        guard let targetNode = nodes[target] else { throw .nodeNotFound(target) }
        let axis = edge.axis
        var next = self
        var nextIDs = ids
        // IDSource is public and not tied to the tree, so a lagging one must not overwrite a node.
        let leaf = try nextIDs.make()
        guard nodes[leaf] == nil else { throw .invariantViolated("ID source issued \(leaf), which is already in the tree") }
        next.nodes[leaf] = node
        next.states.merge(states) { $1 }

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
            let split = try nextIDs.make()
            guard nodes[split] == nil else { throw .invariantViolated("ID source issued \(split), which is already in the tree") }
            next.nodes[split] = .split(axis: axis, children: edge.isLeading ? [leaf, target] : [target, leaf], weights: [0.5, 0.5])
            if let parent, let parentSplit {
                let children = parentSplit.children.map { $0 == target ? split : $0 }
                next.nodes[parent] = .split(axis: parentSplit.axis, children: children, weights: parentSplit.weights)
            } else {
                next.root = split
            }
        }

        next.normalize()
        // The whole tree, not just the new leaf: wrapping the root pushes every node one level deeper.
        // Runs in release too, so an invalid insert throws instead of committing.
        try next.validate()
        self = next
        ids = nextIDs
    }

    /// Removes `window` (D-05). A panel's share goes back to its siblings in proportion to their
    /// weights; a tab group left with one window becomes a panel under the same NodeID.
    /// Throws only `windowNotFound`: a confirmed `.closed` must always be able to drop the slot.
    public mutating func remove(_ window: WindowRef) throws(LayoutError) {
        guard let leaf = leaf(containing: window) else { throw .windowNotFound(window) }
        guard case .tabs(let windows, let selected)? = nodes[leaf] else {
            _ = try removeLeaf(leaf)  // a panel: never throws
            return
        }
        var next = self
        next.states[window.identity] = nil
        var rest = windows
        let index = rest.firstIndex(of: window)!
        rest.remove(at: index)
        // Removing the selected tab selects the one that took its index, clamped to the last.
        next.nodes[leaf] = rest.count == 1
            ? .panel(rest[0])
            : .tabs(windows: rest, selected: index < selected ? selected - 1 : min(selected, rest.count - 1))
        self = next
        assertValid()
    }

    /// Takes the whole leaf `id` (a panel or a tab group) out of the tree, as `remove` does a panel's. Rule E5 (8.1.1
    /// D-16): an empty area right beside it takes its share, the one before it first; with none, its siblings share it
    /// by weight. Returns the leaf and its members' states, for `insertLeaf` or a floating group.
    public mutating func removeLeaf(_ id: NodeID) throws(LayoutError) -> (node: Node, states: [WindowIdentity: WindowState]) {
        guard let node = nodes[id] else { throw .nodeNotFound(id) }
        guard let members = Self.members(of: node) else { throw .notALeaf(id) }
        var next = self
        var states: [WindowIdentity: WindowState] = [:]
        for member in members { states[member.identity] = next.states.removeValue(forKey: member.identity) }
        next.nodes[id] = nil
        if let parent = parent(of: id), case .split(let axis, var children, var weights)? = nodes[parent] {
            let index = children.firstIndex(of: id)!
            children.remove(at: index)
            let weight = weights.remove(at: index)
            if let beside = [index - 1, index].first(where: { children.indices.contains($0) && nodes[children[$0]] == .spacer }) {
                weights[beside] += weight
            }
            next.nodes[parent] = .split(axis: axis, children: children, weights: weights)
        } else {
            next.root = nil
        }
        next.normalize()
        self = next
        assertValid()
        return (node, states)
    }

    /// Rule E4 (8.1.1 D-16): the leaf `id` (a panel or a whole tab group) leaves, and an empty area takes its place,
    /// NodeID and weight. For a docked window moved to a docking position. Returns what `removeLeaf` does.
    public mutating func vacate(_ id: NodeID) throws(LayoutError) -> (node: Node, states: [WindowIdentity: WindowState]) {
        guard let node = nodes[id] else { throw .nodeNotFound(id) }
        guard let members = Self.members(of: node) else { throw .notALeaf(id) }
        var next = self
        var states: [WindowIdentity: WindowState] = [:]
        for member in members { states[member.identity] = next.states.removeValue(forKey: member.identity) }
        next.nodes[id] = .spacer
        next.normalize()
        try next.validate()
        self = next
        return (node, states)
    }

    /// Rule E6 (8.1.1 D-16): `node` (a panel or a tab group, every member new to the tree, with their states) takes the
    /// empty area `spacer`'s place, NodeID and weight.
    public mutating func fill(_ spacer: NodeID, with node: Node, states: [WindowIdentity: WindowState]) throws(LayoutError) {
        guard let current = nodes[spacer] else { throw .nodeNotFound(spacer) }
        guard current == .spacer else { throw .notALeaf(spacer) }
        try checkNewLeaf(node)
        var next = self
        next.nodes[spacer] = node
        next.states.merge(states) { $1 }
        next.normalize()
        try next.validate()  // the caller's states must match the leaf's members
        self = next
    }

    /// Adds `window` as the last, selected tab of the leaf `target` (MODEL-06). A panel becomes a
    /// tab group `[existing, window]` under the same NodeID; tab order is insertion order.
    public mutating func group(_ window: WindowRef, into target: NodeID) throws(LayoutError) {
        guard states[window.identity] == nil else { throw .duplicateWindow(window) }
        guard let node = nodes[target] else { throw .nodeNotFound(target) }
        var next = self
        switch node {
        case let .panel(existing): next.nodes[target] = .tabs(windows: [existing, window], selected: 1)
        case let .tabs(windows, _): next.nodes[target] = .tabs(windows: windows + [window], selected: windows.count)
        case .split, .spacer: throw .notALeaf(target)
        }
        next.states[window.identity] = .present
        self = next
        assertValid()
    }

    /// Makes `window` the selected tab of its group.
    public mutating func selectTab(_ window: WindowRef) throws(LayoutError) {
        guard let leaf = leaf(containing: window) else { throw .windowNotFound(window) }
        guard case let .tabs(windows, _)? = nodes[leaf] else { throw .notATabGroup(leaf) }
        var next = self
        next.nodes[leaf] = .tabs(windows: windows, selected: windows.firstIndex(of: window)!)
        self = next
        assertValid()
    }

    /// Lifecycle transition (D-17, MODEL-08). `.absent` and `.fullscreen` change `states` only, never
    /// `nodes`, so the slot stays reserved: `resolve` gives its space to the neighbours, and `.present`
    /// brings back exactly the rects it had. `.closed` is rejected here: only `World.apply(.closed, …)`
    /// removes a closed window, because it must also purge the window from undo history.
    ///
    /// Callers (the Window Control phase) must send `.closed` only after two sources confirm the window
    /// is gone: an AX invalid-element error and the window missing from the CG window list. Lock screen,
    /// sleep and AX timeouts are `.absent`, never `.closed` (PITFALLS.md Pitfall 2).
    public mutating func setState(_ state: WindowState, for window: WindowRef) throws(LayoutError) {
        guard states[window.identity] != nil else { throw .windowNotFound(window) }
        guard state != .closed else { throw .invariantViolated("closed is a transition, not a stored state; close \(window) through World.apply") }
        states[window.identity] = state
        assertValid()
    }

    /// Exchanges the leaves of two docked windows (TILE-11): two panels, or one panel and one tab group, which moves as
    /// a whole (UI-SPEC Surface 5). NodeIDs and weights stay put, so each leaf takes the other's rect; states are keyed
    /// by identity and travel with their windows. Two tab groups never swap.
    public mutating func swap(_ a: WindowRef, _ b: WindowRef) throws(LayoutError) {
        guard let leafA = leaf(containing: a) else { throw .windowNotFound(a) }
        guard let leafB = leaf(containing: b) else { throw .windowNotFound(b) }
        guard leafA != leafB else { throw .invariantViolated("cannot swap \(leafA) with itself") }
        guard let nodeA = nodes[leafA], let nodeB = nodes[leafB] else { throw .nodeNotFound(leafA) }
        if case .tabs = nodeA, case .tabs = nodeB { throw .notALeaf(leafB) }
        var next = self
        next.nodes[leafA] = nodeB
        next.nodes[leafB] = nodeA
        try next.validate()
        self = next
    }

    /// Gives every child of `split` the same weight (TILE-12).
    public mutating func balance(split: NodeID) throws(LayoutError) {
        let (axis, children, _) = try splitParts(split)
        try commit(split, .split(axis: axis, children: children, weights: Array(repeating: 1 / Double(children.count), count: children.count)))
    }

    /// Mirrors `split`: children and their weights in reverse order (TILE-12).
    public mutating func flip(split: NodeID) throws(LayoutError) {
        let (axis, children, weights) = try splitParts(split)
        try commit(split, .split(axis: axis, children: children.reversed(), weights: weights.reversed()))
    }

    /// Turns the layout a quarter (TILE-12, D-32): toggles the axis of `split` and of every split below it,
    /// keeping child order and weights. When `split` has a parent the flip starts at the root instead: a
    /// nested split taking its parent's axis would merge into it, and a merged split cannot be rotated
    /// back. Flipping every axis keeps parent and child axes apart, so nothing merges and Rotate is its
    /// own inverse.
    public mutating func rotate(split: NodeID) throws(LayoutError) {
        _ = try splitParts(split)
        guard let root else { throw .nodeNotFound(split) }
        var next = self
        // Iterative, and a valid tree is a tree within maxDepth / maxNodes (T-03-04).
        var stack = [parent(of: split) == nil ? split : root]
        while let id = stack.popLast() {
            guard case let .split(axis, children, weights)? = nodes[id] else { continue }
            next.nodes[id] = .split(axis: axis == .horizontal ? .vertical : .horizontal, children: children, weights: weights)
            stack.append(contentsOf: children)
        }
        next.normalize()
        try next.validate()
        self = next
    }

    /// A leaf to add: a panel or a tab group whose windows are all new to the tree.
    func checkNewLeaf(_ node: Node) throws(LayoutError) {
        guard let members = Self.members(of: node) else { throw .invariantViolated("only a panel or a tab group is inserted as a leaf") }
        if let duplicate = members.first(where: { states[$0.identity] != nil }) { throw .duplicateWindow(duplicate) }
    }

    /// A window leaf's windows; nil for a split or an empty area.
    private static func members(of node: Node) -> [WindowRef]? {
        switch node {
        case let .panel(window): [window]
        case let .tabs(windows, _): windows
        case .split, .spacer: nil
        }
    }

    private func splitParts(_ id: NodeID) throws(LayoutError) -> (Axis, [NodeID], [Double]) {
        guard let node = nodes[id] else { throw .nodeNotFound(id) }
        guard case let .split(axis, children, weights) = node else { throw .notASplit(id) }
        return (axis, children, weights)
    }

    /// Copy-then-commit for a one-node edit: normalised and validated before `self` changes.
    private mutating func commit(_ id: NodeID, _ node: Node) throws(LayoutError) {
        var next = self
        next.nodes[id] = node
        next.normalize()
        try next.validate()
        self = next
    }

    /// Moves `delta` (a fraction of the split's length) across the boundary after child `index`,
    /// between those two children only (D-07). Both stay at or above `minWeight`; every other
    /// weight is left bit-identical.
    public mutating func resizeBoundary(in split: NodeID, after index: Int, by delta: Double) throws(LayoutError) {
        try resizeBetween(in: split, index, index + 1, by: delta)
    }

    /// Moves `delta` (a fraction of the split's length) from child `second` to child `first`, which need
    /// not be adjacent; every other weight is left bit-identical, so a gap drag across a minimised sibling
    /// never changes it (TILE-05, Pitfall 9). Both stay at or above `minWeight`.
    public mutating func resizeBetween(in split: NodeID, _ first: Int, _ second: Int, by delta: Double) throws(LayoutError) {
        let (axis, children, weights) = try splitParts(split)
        guard first != second, children.indices.contains(first), children.indices.contains(second) else {
            throw .invalidBoundary(split: split, index: first)
        }
        guard delta.isFinite else { throw .invalidGeometry("delta must be finite") }
        var result = weights
        let total = weights[first] + weights[second]
        result[first] = min(max(weights[first] + delta, Self.minWeight), total - Self.minWeight)
        result[second] = total - result[first]
        try commit(split, .split(axis: axis, children: children, weights: result))
    }

    /// Replaces `split`'s weights with `weights` normalised to sum 1 (G-03-3). One value per child, each finite and
    /// greater than 0.
    public mutating func setWeights(in split: NodeID, _ weights: [Double]) throws(LayoutError) {
        let (axis, children, _) = try splitParts(split)
        guard weights.count == children.count, weights.allSatisfy({ $0.isFinite && $0 > 0 }) else {
            throw .invalidGeometry("weights must be one finite value above 0 per child")
        }
        let sum = weights.reduce(0, +)
        try commit(split, .split(axis: axis, children: children, weights: weights.map { $0 / sum }))
    }

    /// Grows (positive `delta`) or shrinks child `index` by a fraction of the split's length (TILE-13). The
    /// change comes from or goes to its siblings in proportion to their weights, each kept at `minWeight`
    /// or above. Throws `atSizeLimit` when the clamps leave nothing to move.
    public mutating func resizeChild(in split: NodeID, index: Int, by delta: Double) throws(LayoutError) {
        let (axis, children, weights) = try splitParts(split)
        guard children.indices.contains(index) else { throw .invalidBoundary(split: split, index: index) }
        guard delta.isFinite else { throw .invalidGeometry("delta must be finite") }
        let target = min(max(weights[index] + delta, Self.minWeight), 1 - Double(children.count - 1) * Self.minWeight)
        var others = weights
        others.remove(at: index)
        var result = Self.clamped(others, total: 1 - target)
        result.insert(target, at: index)
        guard zip(result, weights).contains(where: { abs($0 - $1) > 1e-12 }) else { throw .atSizeLimit(split) }
        try commit(split, .split(axis: axis, children: children, weights: result))
    }

    /// D-06, run on the working copy of every edit. Collapses and merges (adjacent empty areas included) repeat until a
    /// pass finds none; then each split's weights are renormalised and clamped. Iterative throughout. A split holding no
    /// window always reduces to one empty area this way, and a tree of only empty areas is an empty desk (8.1.1 D-16,
    /// rule E5; D-07).
    /// A merge that would pass `maxChildren` is skipped, leaving that same-axis child nested: more than
    /// maxChildren siblings cannot all keep `minWeight`. A later edit that makes room merges it.
    mutating func normalize() {
        while collapseOrMergeOnce() {}
        if let root, nodes[root] == .spacer { self = LayoutTree() }
        for (id, node) in nodes {
            if case let .split(axis, children, weights) = node, !Self.isNormalised(weights) {
                nodes[id] = .split(axis: axis, children: children, weights: Self.clamped(weights))
            }
        }
    }

    /// Applies the first collapse (a split with one child), merge (a child split on its parent's axis) or merge of two
    /// adjacent empty areas (into the first, with both weights) found walking down from the root. Returns false when
    /// there is none.
    private mutating func collapseOrMergeOnce() -> Bool {
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
            if let index = children.indices.dropLast().first(where: { nodes[children[$0]] == .spacer && nodes[children[$0 + 1]] == .spacer }) {
                var children = children, weights = weights
                let merged = weights.remove(at: index + 1)
                weights[index] += merged
                nodes[children.remove(at: index + 1)] = nil
                nodes[id] = .split(axis: axis, children: children, weights: weights)
                return true
            }
            for (index, child) in children.enumerated() {
                guard case let .split(childAxis, grandchildren, childWeights)? = nodes[child], childAxis == axis else { continue }
                guard children.count - 1 + grandchildren.count <= Self.maxChildren else { continue }
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

    /// Scales to sum `total`, then pins weights below `minWeight` to it and shares the rest of `total`
    /// among the others in proportion, until none is below. Terminates: the pinned set only grows, and
    /// callers pass `total >= count × minWeight` (maxChildren × minWeight == 1), which leaves the unpinned
    /// weights an average of at least minWeight.
    private static func clamped(_ weights: [Double], total: Double = 1) -> [Double] {
        let sum = weights.reduce(0, +)
        var result = weights.map { $0 / sum * total }
        var pinned: Set<Int> = []
        while true {
            let low = result.indices.filter { !pinned.contains($0) && result[$0] < minWeight }
            if low.isEmpty { return result }
            pinned.formUnion(low)
            let free = result.indices.filter { !pinned.contains($0) }
            let freeSum = free.reduce(0) { $0 + result[$1] }
            let share = total - Double(pinned.count) * minWeight
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

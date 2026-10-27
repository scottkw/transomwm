import Foundation
import Testing
@testable import TransomModel

/// Seeded, so a failing seed replays exactly. Kept local on purpose: Plan 02 has its own copy, and
/// two copies do not justify a shared helper.
fileprivate struct SplitMix64: RandomNumberGenerator {
    var state: UInt64

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}

/// The test's own minimum-size rules (Task 1 step 4), written against the tree and not Resolve.swift,
/// so the properties are not checked by the code they test.
private func effectiveMinimum(_ min: Size?) -> Size {
    Size(width: max(1, (min?.width ?? 0).rounded(.up)), height: max(1, (min?.height ?? 0).rounded(.up)))
}

private func need(_ tree: LayoutTree, _ id: NodeID, _ windows: Set<WindowRef>, _ mins: [WindowRef: Size], _ gap: Double) -> Size? {
    let leafWindows: [WindowRef]
    switch tree.nodes[id]! {
    case let .panel(window): leafWindows = [window]
    case let .tabs(tabs, _): leafWindows = tabs
    case .desktop: return nil  // the fuzzed trees are raw trees and hold no Desktop tile
    case let .split(axis, children, _):
        let sizes = children.compactMap { need(tree, $0, windows, mins, gap) }
        if sizes.isEmpty { return nil }
        let along = sizes.reduce(gap * Double(sizes.count - 1)) { $0 + (axis == .horizontal ? $1.width : $1.height) }
        let across = sizes.map { axis == .horizontal ? $0.height : $0.width }.max()!
        return axis == .horizontal ? Size(width: along, height: across) : Size(width: across, height: along)
    }
    let sizes = leafWindows.filter(windows.contains).map { effectiveMinimum(mins[$0]) }
    if sizes.isEmpty { return nil }
    return Size(width: sizes.map(\.width).max()!, height: sizes.map(\.height).max()!)
}

private func fitsAll(_ tree: LayoutTree, _ windows: Set<WindowRef>, _ mins: [WindowRef: Size], _ gap: Double, in inner: Rect) -> Bool {
    guard let root = tree.root, let size = need(tree, root, windows, mins, gap) else { return true }
    return size.width <= inner.width && size.height <= inner.height
}

@Suite struct ResolveFuzzTests {
    @Test(arguments: 0..<30)
    func resolvedLayoutsNeverOverlapAndHonourMinimums(seed: Int) throws {
        var rng = SplitMix64(state: UInt64(seed))
        for index in 0..<20 {
            let (tree, mins) = try randomLayout(&rng)
            let area = Rect(
                x: Double.random(in: -3000...3000, using: &rng), y: Double.random(in: -3000...3000, using: &rng),
                width: Double.random(in: 0...4000, using: &rng), height: Double.random(in: 0...4000, using: &rng))
            let rawGap = Double.random(in: 0...40, using: &rng)
            let resolution = try resolve(tree, in: area, mins: mins, gap: rawGap)
            let context = "seed \(seed) case \(index) area \(area) gap \(rawGap) tree \(tree)"
            func check(_ ok: Bool, _ property: String) {
                if !ok { Issue.record("\(property) failed: \(context)") }
            }

            let gap = rawGap.rounded()
            let sx = area.minX.rounded(.up) + gap, sy = area.minY.rounded(.up) + gap
            let inner = Rect(x: sx, y: sy,
                             width: max(0, area.maxX.rounded(.down) - gap - sx), height: max(0, area.maxY.rounded(.down) - gap - sy))
            let leaves = resolution.nodeRects.filter { if case .split? = tree.nodes[$0.key] { false } else { true } }
                .sorted { $0.key < $1.key }

            // P1: no two distinct leaves overlap.
            for (i, l) in leaves.enumerated() {
                for r in leaves[(i + 1)...] { check(!l.value.overlaps(r.value), "P1 \(l.key) overlaps \(r.key)") }
            }
            // P2: whole points, inside the snapped area inset by the rounded gap.
            for rect in Array(resolution.nodeRects.values) + Array(resolution.windowRects.values) {
                check([rect.x, rect.y, rect.width, rect.height].allSatisfy { $0 == $0.rounded() }, "P2 \(rect) not whole points")
                check(rect.minX >= inner.minX && rect.minY >= inner.minY && rect.maxX <= inner.maxX && rect.maxY <= inner.maxY,
                      "P2 \(rect) outside \(inner)")
            }
            // P3: every placed window is at least its effective minimum.
            for (window, rect) in resolution.windowRects {
                let min = effectiveMinimum(mins[window])
                check(rect.width >= min.width && rect.height >= min.height, "P3 \(window) \(rect) below \(min)")
            }
            // P4: present = placed ∪ unfit, disjoint; absent and fullscreen windows are in neither.
            let present = Set(tree.windows.filter { tree.state(of: $0) == .present })
            let placed = Set(resolution.windowRects.keys)
            check(placed.isDisjoint(with: resolution.unfit), "P4 placed and unfit overlap")
            check(placed.union(resolution.unfit) == present, "P4 placed ∪ unfit != present")
            // P5: when everything fits, nothing is unfit.
            if fitsAll(tree, present, mins, gap, in: inner) { check(resolution.unfit.isEmpty, "P5 unfit although all fit") }
            // P6: deterministic.
            check(try resolve(tree, in: area, mins: mins, gap: rawGap) == resolution, "P6 second resolve differs")
            // P7: in each placed split the children's lengths plus the gaps equal the split's length.
            for (id, rect) in resolution.nodeRects {
                guard case let .split(axis, children, _)? = tree.nodes[id] else { continue }
                let lengths = children.compactMap { resolution.nodeRects[$0] }.map { axis == .horizontal ? $0.width : $0.height }
                let total = lengths.reduce(gap * Double(lengths.count - 1), +)
                check(total == (axis == .horizontal ? rect.width : rect.height), "P7 split \(id) lengths \(lengths)")
            }
            // P9: in a placed split where no child's weighted share is below its minimum (so nothing is
            // pinned), every child but the last gets its weighted share of the length, to within rounding.
            for (id, rect) in resolution.nodeRects {
                guard case let .split(axis, children, weights)? = tree.nodes[id] else { continue }
                let horizontal = axis == .horizontal
                let parts = zip(children, weights).compactMap { child, weight -> (length: Double, weight: Double, min: Double)? in
                    guard let r = resolution.nodeRects[child], let size = need(tree, child, placed, mins, gap) else { return nil }
                    return (horizontal ? r.width : r.height, weight, horizontal ? size.width : size.height)
                }
                let available = (horizontal ? rect.width : rect.height) - gap * Double(parts.count - 1)
                let weight = parts.reduce(0) { $0 + $1.weight }
                let exact = parts.map { available * $0.weight / weight }
                guard zip(exact, parts).allSatisfy({ $0 >= $1.min }) else { continue }
                for (share, part) in zip(exact, parts).dropLast() {
                    check(abs(part.length - share) <= 1, "P9 split \(id) length \(part.length) is not its weighted share \(share)")
                }
            }
            // P8: maximality — no unfit window could have joined the placed ones.
            for window in resolution.unfit {
                check(!fitsAll(tree, placed.union([window]), mins, gap, in: inner), "P8 \(window) would have fit")
            }
        }
    }

    /// 1–25 windows docked by random inserts, then random weights, states and minimums.
    private func randomLayout(_ rng: inout SplitMix64) throws -> (LayoutTree, [WindowRef: Size]) {
        var tree = LayoutTree()
        var ids = IDSource()
        let count = Int.random(in: 1...25, using: &rng)
        for id in 1...count {
            let window = makeWindow(UInt32(id))
            // Dictionary order varies per process; sort so a seed always picks the same node.
            if let target = tree.nodes.keys.sorted().randomElement(using: &rng) {
                try tree.insert(window, at: Edge.allCases.randomElement(using: &rng)!, of: target, ids: &ids)
            } else {
                try tree.insertRoot(window, ids: &ids)
            }
        }

        var nodes = tree.nodes
        for id in nodes.keys.sorted() {
            guard case let .split(axis, children, _)? = nodes[id] else { continue }
            let raw = children.map { _ in Double.random(in: 0...1, using: &rng) }
            let sum = raw.reduce(0, +)
            let spare = 1 - LayoutTree.minWeight * Double(children.count)
            let weights = raw.map { LayoutTree.minWeight + spare * (sum > 0 ? $0 / sum : 1 / Double(children.count)) }
            nodes[id] = .split(axis: axis, children: children, weights: weights)
        }
        var states: [WindowIdentity: WindowState] = [:]
        var mins: [WindowRef: Size] = [:]
        for window in tree.windows {
            let roll = Double.random(in: 0..<1, using: &rng)
            states[window.identity] = roll < 0.15 ? .absent : roll < 0.20 ? .fullscreen : .present
            if Bool.random(using: &rng) {
                mins[window] = Size(width: Double.random(in: 0...600, using: &rng), height: Double.random(in: 0...600, using: &rng))
            }
        }
        return (try LayoutTree(root: tree.root, nodes: nodes, states: states), mins)
    }
}

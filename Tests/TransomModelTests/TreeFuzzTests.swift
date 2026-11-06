import Foundation
import Testing
@testable import TransomModel

/// Seeded, so a failing seed replays exactly. Kept local on purpose: Plan 03 has its own copy, and
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

@Suite struct TreeFuzzTests {
    @Test(arguments: 0..<20)
    func randomEditsKeepEveryInvariant(seed: Int) throws {
        var rng = SplitMix64(state: UInt64(seed))
        var tree = LayoutTree()
        var ids = IDSource()
        var expected: Set<WindowIdentity> = []
        var nextWindow: UInt32 = 1
        let ghost = makeWindow(.max)

        for _ in 0..<100 {
            // Dictionary order varies per process; sort so a seed always picks the same node.
            let nodeIDs = tree.nodes.keys.sorted()
            switch Int.random(in: 0..<13, using: &rng) {
            case 0..<4:
                let window = makeWindow(nextWindow)
                nextWindow += 1
                if let target = nodeIDs.randomElement(using: &rng) {
                    // A third of the drops onto a window leaf make (or grow) a tab group instead of docking beside it.
                    if case .split? = tree.nodes[target] {
                        try tree.insert(window, at: Edge.allCases.randomElement(using: &rng)!, of: target, ids: &ids)
                    } else if tree.nodes[target] != .spacer, Int.random(in: 0..<3, using: &rng) == 0 {
                        try tree.group(window, into: target)
                    } else {
                        try tree.insert(window, at: Edge.allCases.randomElement(using: &rng)!, of: target, ids: &ids)
                    }
                } else {
                    try tree.insertRoot(window, ids: &ids)
                }
                expected.insert(window.identity)
            case 4..<7:
                guard let window = tree.windows.randomElement(using: &rng) else { continue }
                try tree.remove(window)
                expected.remove(window.identity)
            case 7:
                let tabbed = tree.windows.filter { window in
                    if case .tabs? = tree.leaf(containing: window).flatMap({ tree.nodes[$0] }) { true } else { false }
                }
                guard let window = tabbed.randomElement(using: &rng) else { continue }
                try tree.selectTab(window)
            case 8:
                let splits = nodeIDs.filter { if case .split? = tree.nodes[$0] { true } else { false } }
                guard let split = splits.randomElement(using: &rng), case let .split(_, children, _)? = tree.nodes[split] else { continue }
                let index = Int.random(in: 0..<(children.count - 1), using: &rng)
                try tree.resizeBoundary(in: split, after: index, by: Double.random(in: -0.5...0.5, using: &rng))
            case 9:
                let window = makeWindow(nextWindow)
                nextWindow += 1
                let slot = FourthSlot.allCases.randomElement(using: &rng)!
                let axis: Axis = Bool.random(using: &rng) ? .horizontal : .vertical
                // Too deep or too full: nothing changed, so there's nothing to record.
                guard (try? tree.insertFourth(.panel(window), states: [window.identity: .present], slot: slot, axis: axis, ids: &ids)) != nil else { continue }
                expected.insert(window.identity)
            case 10:
                // Rule E4: a window leaf (a whole tab group) leaves an empty area behind.
                guard let window = tree.windows.randomElement(using: &rng), let leaf = tree.leaf(containing: window) else { continue }
                let taken = try tree.vacate(leaf)
                expected.subtract(taken.states.keys)
            case 11:
                // Rule E6: a new window fills an empty area.
                let spacers = nodeIDs.filter { tree.nodes[$0] == .spacer }
                guard let spacer = spacers.randomElement(using: &rng) else { continue }
                let window = makeWindow(nextWindow)
                nextWindow += 1
                try tree.fill(spacer, with: .panel(window), states: [window.identity: .present])
                expected.insert(window.identity)
            default:
                // Edits that must throw and leave the tree and the ID source untouched.
                let before = tree
                let idsBefore = ids
                if Bool.random(using: &rng), let window = tree.windows.randomElement(using: &rng), let target = nodeIDs.randomElement(using: &rng) {
                    #expect(throws: LayoutError.duplicateWindow(window)) { try tree.insert(window, at: .left, of: target, ids: &ids) }
                } else {
                    #expect(throws: LayoutError.windowNotFound(ghost)) { try tree.remove(ghost) }
                }
                #expect(tree == before)
                #expect(ids == idsBefore)
            }
            try expectInvariants(tree, windows: expected)
        }
    }

    private func expectInvariants(_ tree: LayoutTree, windows expected: Set<WindowIdentity>) throws {
        try tree.validate()
        for node in tree.nodes.values {
            guard case let .split(axis, children, weights) = node else { continue }
            #expect(abs(weights.reduce(0, +) - 1) <= 1e-9)
            #expect(weights.allSatisfy { $0 >= LayoutTree.minWeight - 1e-12 })
            #expect(children.count >= 2)
            for child in children {
                if case let .split(childAxis, grandchildren, _)? = tree.nodes[child] {
                    #expect(childAxis != axis || children.count - 1 + grandchildren.count > LayoutTree.maxChildren)
                }
            }
        }
        #expect(Set(tree.windows.map(\.identity)) == expected)
        // 8.1.1 D-16: empty areas stay in normal form.
        if let root = tree.root { #expect(tree.nodes[root] != .spacer, "the root is an empty area") }
        func holdsWindow(_ id: NodeID) -> Bool {
            switch tree.nodes[id] {
            case .panel?, .tabs?: true
            case let .split(_, children, _)?: children.contains(where: holdsWindow)
            case .spacer?, nil: false
            }
        }
        for (id, node) in tree.nodes {
            guard case let .split(_, children, _) = node else { continue }
            #expect(holdsWindow(id), "split \(id) holds no window")
            #expect(!zip(children, children.dropFirst()).contains { tree.nodes[$0] == .spacer && tree.nodes[$1] == .spacer })
        }
    }
}

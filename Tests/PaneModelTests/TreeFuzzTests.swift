import Foundation
import Testing
@testable import PaneModel

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
            switch Int.random(in: 0..<10, using: &rng) {
            case 0..<4:
                let window = makeWindow(nextWindow)
                nextWindow += 1
                if let target = nodeIDs.randomElement(using: &rng) {
                    try tree.insert(window, at: Edge.allCases.randomElement(using: &rng)!, of: target, ids: &ids)
                } else {
                    try tree.insertRoot(window, ids: &ids)
                }
                expected.insert(window.identity)
            case 4..<7:
                guard let window = tree.windows.randomElement(using: &rng) else { continue }
                try tree.remove(window)
                expected.remove(window.identity)
            case 7..<9:
                let splits = nodeIDs.filter { if case .split? = tree.nodes[$0] { true } else { false } }
                guard let split = splits.randomElement(using: &rng), case let .split(_, children, _)? = tree.nodes[split] else { continue }
                let index = Int.random(in: 0..<(children.count - 1), using: &rng)
                try tree.resizeBoundary(in: split, after: index, by: Double.random(in: -0.5...0.5, using: &rng))
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
                if case let .split(childAxis, _, _)? = tree.nodes[child] { #expect(childAxis != axis) }
            }
        }
        #expect(Set(tree.windows.map(\.identity)) == expected)
    }
}

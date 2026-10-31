import TransomEngine
import Testing

/// D-15: with the Spaces lookup off, settled Space visits cluster by Jaccard overlap into session-only synthetic IDs.
@Suite struct CoVisibilitySpacesTests {
    private let base = CoVisibilitySpaces.syntheticBase

    @Test func overlappingVisitsJoinAndDisjointOnesStartANewSpace() {
        var map = CoVisibilitySpaces()
        #expect(map.visit(display: "A", windowIDs: [1, 2, 3]) == base | 1)
        #expect(map.visit(display: "A", windowIDs: [1, 2, 4]) == base | 1, "Jaccard 0.5 joins")
        #expect(map.visit(display: "A", windowIDs: [7, 8]) == base | 2)
        #expect(map.visitedCount == 2)
    }

    @Test func anEmptyVisitReturnsTheDisplaysLastSpaceAndChangesNothing() {
        var map = CoVisibilitySpaces()
        map.visit(display: "A", windowIDs: [7, 8])
        let before = map
        #expect(map.visit(display: "A", windowIDs: []) == base | 1)
        #expect(map == before)
    }

    @Test func displaysNeverShareASpace() {
        var map = CoVisibilitySpaces()
        let a = map.visit(display: "A", windowIDs: [1, 2, 3])
        let b = map.visit(display: "B", windowIDs: [1, 2, 3])
        #expect(a != b)
        #expect(map.visitedCount == 2)
    }

    @Test func aForgottenWindowLeavesEveryCluster() {
        var map = CoVisibilitySpaces()
        map.visit(display: "A", windowIDs: [1, 2])
        map.visit(display: "B", windowIDs: [1, 9])
        map.forget(windowID: 1)
        // Only 2 is left on A's Space, so {2, 5} overlaps by 1/2 and joins it.
        #expect(map.visit(display: "A", windowIDs: [2, 5]) == base | 1)
        // {9, 6, 7} against B's {9}: 1/3, a new Space.
        #expect(map.visit(display: "B", windowIDs: [9, 6, 7]) == base | 3)
    }

    @Test func syntheticIDsAreInTheReservedHighRange() {
        var map = CoVisibilitySpaces()
        #expect(map.visit(display: "A", windowIDs: [1]) >= CoVisibilitySpaces.syntheticBase)
    }
}

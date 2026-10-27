import Foundation
import Testing
@testable import TransomModel

private let a = makeWindow(1)
private let b = makeWindow(2)

private func n(_ raw: UInt64) -> NodeID { NodeID(raw: raw) }

private let area = Rect(x: 0, y: 0, width: 1000, height: 500)

@Suite struct DropZoneTests {
    /// A single panel A at node 1, resolved with gap 10: A's rect is (10, 10, 980, 480).
    func single(in rect: Rect = area) throws -> (LayoutTree, Resolution) {
        let tree = try LayoutTree(root: n(1), nodes: [n(1): .panel(a)], states: [a.identity: .present])
        return (tree, try resolve(tree, in: rect, mins: [:], gap: 10))
    }

    /// H[A, B] at nodes 2 and 3 under split 1.
    func pair(bState: WindowState = .present) throws -> (LayoutTree, Resolution) {
        let tree = try LayoutTree(
            root: n(1),
            nodes: [n(1): .split(axis: .horizontal, children: [n(2), n(3)], weights: [0.5, 0.5]), n(2): .panel(a), n(3): .panel(b)],
            states: [a.identity: .present, b.identity: bState])
        return (tree, try resolve(tree, in: area, mins: [:], gap: 10))
    }

    func target(_ x: Double, _ y: Double, _ layout: (LayoutTree, Resolution), in rect: Rect = area) -> DropTarget? {
        DropZones.target(at: Point(x: x, y: y), in: rect, tree: layout.0, resolution: layout.1)
    }

    @Test func centreAndEdgeBandsOfATile() throws {
        let layout = try single()
        #expect(target(500, 250, layout) == .tile(n(1), .center))
        #expect(target(60, 250, layout) == .tile(n(1), .edge(.left)))
        #expect(target(940, 250, layout) == .tile(n(1), .edge(.right)))
        #expect(target(500, 60, layout) == .tile(n(1), .edge(.top)))
        #expect(target(500, 440, layout) == .tile(n(1), .edge(.bottom)))
    }

    @Test func cornerPicksTheSmallerNormalisedDistanceAndTiesGoToLeftOrRight() throws {
        // fx = 50/980 is smaller than fy = 50/480.
        #expect(target(60, 60, try single()) == .tile(n(1), .edge(.left)))
        // A square tile (10, 10, 480, 480): fx == fy, so left/right wins.
        let square = Rect(x: 0, y: 0, width: 500, height: 500)
        #expect(target(60, 60, try single(in: square), in: square) == .tile(n(1), .edge(.left)))
        #expect(target(440, 440, try single(in: square), in: square) == .tile(n(1), .edge(.right)))
    }

    @Test func boundaryFractionsCountAsCentre() throws {
        let layout = try single()
        // fx = 245/980 = 0.25 and 735/980 = 0.75 exactly.
        #expect(target(255, 250, layout) == .tile(n(1), .center))
        #expect(target(745, 250, layout) == .tile(n(1), .center))
        #expect(target(254.9, 250, layout) == .tile(n(1), .edge(.left)))
        #expect(target(745.1, 250, layout) == .tile(n(1), .edge(.right)))
    }

    @Test func pointsNearTheAreaEdgeTargetTheWholeLayout() throws {
        let layout = try single()
        #expect(target(10, 250, layout) == .layoutEdge(.left))
        #expect(target(990, 250, layout) == .layoutEdge(.right))
        #expect(target(500, 5, layout) == .layoutEdge(.top))
        #expect(target(500, 495, layout) == .layoutEdge(.bottom))
        #expect(target(10, 10, layout) == .layoutEdge(.left))
    }

    @Test func gapsAndPointsOutsideTheAreaHitNothing() throws {
        let layout = try pair()
        #expect(target(495, 250, layout) == nil)
        #expect(target(500, 250, layout) == nil)
        #expect(target(-5, 250, layout) == nil)
        #expect(target(1000, 250, layout) == nil)
        #expect(target(750, 250, layout) == .tile(n(3), .center))
    }

    @Test func emptyTreeIsTheEmptyLayoutInsideTheAreaOnly() throws {
        let layout = (LayoutTree(), Resolution())
        #expect(target(500, 250, layout) == .emptyLayout)
        #expect(target(5, 5, layout) == .emptyLayout)
        #expect(target(1500, 250, layout) == nil)
    }

    @Test func absentWindowsTileIsNotHittable() throws {
        let layout = try pair(bState: .absent)
        #expect(target(750, 250, layout) == .tile(n(2), .edge(.right)))
    }

    @Test func tuningConstants() {
        #expect(DropZones.edgeBandFraction == 0.25)
        #expect(DropZones.displayEdgeBand == 24)
    }
}

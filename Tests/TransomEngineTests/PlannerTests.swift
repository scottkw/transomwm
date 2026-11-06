import TransomEngine
import TransomModel
import Testing

private let area = Rect(x: 0, y: 25, width: 1440, height: 875)

private func ref(_ id: UInt32) -> WindowRef {
    WindowRef(identity: WindowIdentity(windowID: id, pid: 700, bundleID: "com.example.planner"))
}

private let a = ref(1), b = ref(6)

/// `docked` left to right (a alone by default), plus the given floating windows.
private func desk(_ docked: [WindowRef] = [a], floating: [(WindowRef, Rect)] = []) throws -> Desk {
    var desk = Desk()
    var ids = IDSource()
    for window in docked { try desk.tree.applyDrop(.layoutEdge(.right), window: window, ids: &ids) }
    for (window, frame) in floating { try desk.desktop.add(window, frame: frame) }
    return desk
}

/// D-05, D-12: the planner turns a desk's docked windows into tile frames; floating windows are never planned.
@Suite struct PlannerTests {
    /// 8.1.1 D-01: the docked tiles share the whole inner area; nothing is kept back for a Desktop tile.
    @Test func dockedTilesComeFromResolveAndCoverTheInnerArea() throws {
        let desk = try desk([a, b])
        let plan = try Planner.plan(desk: desk, area: area, gap: 8, mins: [:])
        let expected = try resolve(desk.tree, in: area, mins: [:], gap: 8)
        let left = try #require(plan.frames[a]), right = try #require(plan.frames[b])
        #expect(left == expected.windowRects[a] && right == expected.windowRects[b])
        #expect(!left.overlaps(right))
        // Inner area: 8 pt in from each edge; one 8 pt gap between the two tiles.
        #expect(left.minX == 8 && right.maxX == 1432)
        #expect(left.width + 8 + right.width == 1424)
        #expect(left.minY == 33 && left.height == 859 && right.minY == 33 && right.height == 859)
        #expect(plan.unfit.isEmpty)
    }

    @Test func aLoneDockedTileFillsTheInnerArea() throws {
        let plan = try Planner.plan(desk: try desk(), area: area, gap: 8, mins: [:])
        #expect(plan.frames == [a: Rect(x: 8, y: 33, width: 1424, height: 859)])
    }

    /// D-05: a floating window is never framed or parked, wherever it sits and whatever it wants or needs.
    @Test func floatingWindowsAreNeverPlanned() throws {
        let over = ref(2), clear = ref(3), offEdge = ref(4), huge = ref(5)
        let desk = try desk(floating: [
            (over, Rect(x: 600, y: 100, width: 300, height: 200)), (clear, Rect(x: 800, y: 100, width: 300, height: 200)),
            (offEdge, Rect(x: 1300, y: 100, width: 300, height: 200)), (huge, Rect(x: 100, y: 40, width: 800, height: 600)),
        ])
        let plan = try Planner.plan(
            desk: desk, area: area, gap: 8, mins: [huge: Size(width: 2000, height: 1000)])
        #expect(plan.frames.keys.sorted { $0.identity < $1.identity } == [a])
        #expect(plan.parks.isEmpty)
        // No floater sizes anything: the docked tile is laid out as if the floating layer were empty.
        #expect(plan.resolution == (try resolve(desk.tree, in: area, mins: [:], gap: 8)))
        #expect(plan.unfit.isEmpty)
    }

    /// G-03-4: Float's placement.
    @Test func floatFrameIsTheWantedFrameClampedIntoTheVisibleFrame() {
        let tile = Rect(x: 8, y: 33, width: 708, height: 859), area = Rect(x: 8, y: 33, width: 1424, height: 859)
        let inside = Rect(x: 800, y: 100, width: 300, height: 200)
        #expect(Planner.floatFrame(wanted: inside, tile: tile, area: area, minimum: nil) == inside)
        let partly = Rect(x: 1300, y: 800, width: 300, height: 200)
        #expect(Planner.floatFrame(wanted: partly, tile: tile, area: area, minimum: nil) == Planner.clamp(partly, into: area))
    }

    @Test func floatFrameFallsBackToACentredFrame90PercentOfTheTile() {
        let tile = Rect(x: 8, y: 33, width: 708, height: 859), area = Rect(x: 8, y: 33, width: 1424, height: 859)
        let centred = Rect(x: area.midX - 0.9 * 708 / 2, y: area.midY - 0.9 * 859 / 2, width: 0.9 * 708, height: 0.9 * 859)
        #expect(Planner.floatFrame(wanted: nil, tile: tile, area: area, minimum: nil) == centred)
        let onTheTile = Rect(x: 9, y: 32, width: 707, height: 860)
        #expect(Planner.floatFrame(wanted: onTheTile, tile: tile, area: area, minimum: nil) == centred)
    }

    @Test func floatFramesFallbackKeepsTheMinimumAndNeverExceedsTheVisibleFrame() {
        let tile = Rect(x: 8, y: 33, width: 708, height: 859), area = Rect(x: 8, y: 33, width: 1424, height: 859)
        let big = Planner.floatFrame(wanted: nil, tile: tile, area: area, minimum: Size(width: 700, height: 850))
        #expect(big.width == 700 && big.height == 850)
        let huge = Planner.floatFrame(wanted: nil, tile: area, area: area, minimum: Size(width: 2000, height: 2000))
        #expect(huge == area)
    }

    @Test func clampShrinksAFrameLargerThanTheVisibleFrame() {
        let area = Rect(x: 724, y: 33, width: 708, height: 859)
        #expect(Planner.clamp(Rect(x: 0, y: 0, width: 2000, height: 2000), into: area) == area)
        #expect(Planner.clamp(Rect(x: 1400, y: 800, width: 100, height: 200), into: area) == Rect(x: 1332, y: 692, width: 100, height: 200))
    }

    @Test func dockTargetInATilesRightEdgeBandIsItsRightEdge() throws {
        let desk = try desk()
        let plan = try Planner.plan(desk: desk, area: area, gap: 8, mins: [:])
        let leaf = try #require(desk.tree.leaf(containing: a)), tile = try #require(plan.resolution.nodeRects[leaf])
        let point = Point(x: tile.maxX - 40, y: tile.midY)
        #expect(Planner.dockTarget(at: point, desk: desk, area: area, resolution: plan.resolution) == .tile(leaf, .edge(.right)))
    }

    @Test func dockTargetAtATilesCentreUsesTheNearestEdgeBand() throws {
        let desk = try desk()
        let plan = try Planner.plan(desk: desk, area: area, gap: 8, mins: [:])
        let leaf = try #require(desk.tree.leaf(containing: a)), tile = try #require(plan.resolution.nodeRects[leaf])
        let left = Point(x: tile.midX - 10, y: tile.midY)
        #expect(Planner.dockTarget(at: left, desk: desk, area: area, resolution: plan.resolution) == .tile(leaf, .edge(.left)))
        let below = Point(x: tile.midX, y: tile.midY + 10)
        #expect(Planner.dockTarget(at: below, desk: desk, area: area, resolution: plan.resolution) == .tile(leaf, .edge(.bottom)))
    }

    /// Quick 261027-gqo (user decision 2026-10-27): at the exact centre, Dock's edge fallback ties to the left edge.
    @Test func dockTargetAtATilesExactCentreGoesLeft() throws {
        let desk = try desk()
        let plan = try Planner.plan(desk: desk, area: area, gap: 8, mins: [:])
        let leaf = try #require(desk.tree.leaf(containing: a)), tile = try #require(plan.resolution.nodeRects[leaf])
        let centre = Point(x: tile.midX, y: tile.midY)
        #expect(Planner.dockTarget(at: centre, desk: desk, area: area, resolution: plan.resolution) == .tile(leaf, .edge(.left)))
    }

    /// 8.1.1 D-01: an empty desk has no tile to dock beside; the window becomes the root.
    @Test func dockTargetOnAnEmptyDeskIsTheEmptyLayout() throws {
        let desk = try desk([])
        let plan = try Planner.plan(desk: desk, area: area, gap: 8, mins: [:])
        #expect(Planner.dockTarget(at: Point(x: 720, y: 460), desk: desk, area: area, resolution: plan.resolution) == .emptyLayout)
    }
}

import TransomEngine
import TransomModel
import Testing

private let area = Rect(x: 0, y: 25, width: 1440, height: 875)

private func ref(_ id: UInt32) -> WindowRef {
    WindowRef(identity: WindowIdentity(windowID: id, pid: 700, bundleID: "com.example.planner"))
}

private let a = ref(1)

/// [a | Desktop], plus the given floating windows.
private func desk(floating: [(WindowRef, Rect)] = []) throws -> Desk {
    var desk = Desk()
    var ids = IDSource()
    try desk.tree.insert(a, at: .left, of: .desktop, ids: &ids)
    for (window, frame) in floating { try desk.desktop.add(window, frame: frame) }
    return desk
}

/// D-05, D-12: the planner turns a desk's docked windows into tile frames; floating windows are never planned.
@Suite struct PlannerTests {
    @Test func dockedTileAndDesktopComeFromResolveAndCoverTheInnerArea() throws {
        let desk = try desk()
        let plan = try Planner.plan(desk: desk, area: area, gap: 8, mins: [:])
        let expected = try resolve(desk.tree, in: area, mins: [:], gap: 8)
        let tile = try #require(plan.frames[a])
        let desktop = try #require(plan.desktopRect)
        #expect(tile == expected.windowRects[a])
        #expect(desktop == expected.desktopRect)
        #expect(!tile.overlaps(desktop))
        // Inner area: 8 pt in from each edge; one 8 pt gap between the two tiles.
        #expect(tile.minX == 8 && desktop.maxX == 1432)
        #expect(tile.width + 8 + desktop.width == 1424)
        #expect(tile.minY == 33 && tile.height == 859 && desktop.minY == 33 && desktop.height == 859)
        #expect(plan.unfit.isEmpty)
    }

    /// D-05: a floating window is never framed or parked, wherever it sits and whatever it wants or needs.
    @Test func floatingWindowsAreNeverPlanned() throws {
        let over = ref(2), clear = ref(3), offEdge = ref(4), huge = ref(5)
        let desk = try desk(floating: [
            (over, Rect(x: 600, y: 100, width: 300, height: 200)), (clear, Rect(x: 800, y: 100, width: 300, height: 200)),
            (offEdge, Rect(x: 1300, y: 100, width: 300, height: 200)), (huge, Rect(x: 100, y: 40, width: 800, height: 600)),
        ])
        let plan = try Planner.plan(
            desk: desk, area: area, gap: 8, mins: [huge: Size(width: 2000, height: 1000)],
            wanted: [clear.identity: Rect(x: 0, y: 25, width: 400, height: 400)])
        #expect(plan.frames.keys.sorted { $0.identity < $1.identity } == [a])
        #expect(plan.parks.isEmpty)
        // No floater sizes anything: the docked tile is laid out as if the floating layer were empty.
        #expect(plan.resolution == (try resolve(desk.tree, in: area, mins: [:], gap: 8)))
        #expect(plan.unfit.isEmpty)
    }

    /// G-03-4: Float's placement.
    @Test func floatFrameIsTheWantedFrameClampedIntoTheDesktop() {
        let tile = Rect(x: 8, y: 33, width: 708, height: 859), desktop = Rect(x: 8, y: 33, width: 1424, height: 859)
        let inside = Rect(x: 800, y: 100, width: 300, height: 200)
        #expect(Planner.floatFrame(wanted: inside, tile: tile, desktop: desktop, minimum: nil) == inside)
        let partly = Rect(x: 1300, y: 800, width: 300, height: 200)
        #expect(Planner.floatFrame(wanted: partly, tile: tile, desktop: desktop, minimum: nil) == Planner.clamp(partly, into: desktop))
    }

    @Test func floatFrameFallsBackToACentredFrame90PercentOfTheTile() {
        let tile = Rect(x: 8, y: 33, width: 708, height: 859), desktop = Rect(x: 8, y: 33, width: 1424, height: 859)
        let centred = Rect(x: desktop.midX - 0.9 * 708 / 2, y: desktop.midY - 0.9 * 859 / 2, width: 0.9 * 708, height: 0.9 * 859)
        #expect(Planner.floatFrame(wanted: nil, tile: tile, desktop: desktop, minimum: nil) == centred)
        let onTheTile = Rect(x: 9, y: 32, width: 707, height: 860)
        #expect(Planner.floatFrame(wanted: onTheTile, tile: tile, desktop: desktop, minimum: nil) == centred)
    }

    @Test func floatFramesFallbackKeepsTheMinimumAndNeverExceedsTheDesktop() {
        let tile = Rect(x: 8, y: 33, width: 708, height: 859), desktop = Rect(x: 8, y: 33, width: 1424, height: 859)
        let big = Planner.floatFrame(wanted: nil, tile: tile, desktop: desktop, minimum: Size(width: 700, height: 850))
        #expect(big.width == 700 && big.height == 850)
        let huge = Planner.floatFrame(wanted: nil, tile: desktop, desktop: desktop, minimum: Size(width: 2000, height: 2000))
        #expect(huge == desktop)
    }

    @Test func clampShrinksAFrameLargerThanTheDesktop() {
        let desktop = Rect(x: 724, y: 33, width: 708, height: 859)
        #expect(Planner.clamp(Rect(x: 0, y: 0, width: 2000, height: 2000), into: desktop) == desktop)
        #expect(Planner.clamp(Rect(x: 1400, y: 800, width: 100, height: 200), into: desktop) == Rect(x: 1332, y: 692, width: 100, height: 200))
    }

    @Test func dockTargetInTheDesktopsRightEdgeBandIsItsRightEdge() throws {
        let desk = try desk()
        let plan = try Planner.plan(desk: desk, area: area, gap: 8, mins: [:])
        let desktop = try #require(plan.desktopRect)
        let point = Point(x: desktop.maxX - 40, y: desktop.midY)
        #expect(Planner.dockTarget(at: point, desk: desk, area: area, resolution: plan.resolution) == .tile(.desktop, .edge(.right)))
    }

    @Test func dockTargetAtTheDesktopsCentreUsesTheNearestEdgeBand() throws {
        let desk = try desk()
        let plan = try Planner.plan(desk: desk, area: area, gap: 8, mins: [:])
        let desktop = try #require(plan.desktopRect)
        let left = Point(x: desktop.midX - 10, y: desktop.midY)
        #expect(Planner.dockTarget(at: left, desk: desk, area: area, resolution: plan.resolution) == .tile(.desktop, .edge(.left)))
        let below = Point(x: desktop.midX, y: desktop.midY + 10)
        #expect(Planner.dockTarget(at: below, desk: desk, area: area, resolution: plan.resolution) == .tile(.desktop, .edge(.bottom)))
    }

    /// Quick 261027-gqo (user decision 2026-10-27): at the exact centre, Dock's edge fallback ties to the left edge.
    @Test func dockTargetAtTheDesktopsExactCentreGoesLeft() throws {
        let desk = try desk()
        let plan = try Planner.plan(desk: desk, area: area, gap: 8, mins: [:])
        let desktop = try #require(plan.desktopRect)
        let centre = Point(x: desktop.midX, y: desktop.midY)
        #expect(Planner.dockTarget(at: centre, desk: desk, area: area, resolution: plan.resolution) == .tile(.desktop, .edge(.left)))
    }
}

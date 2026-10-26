import PaneEngine
import PaneModel
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

/// D-24, D-12: the planner turns a desk into tile frames, the Desktop rect and clamped floating frames.
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

    @Test func aFloatingWindowOverlappingADockedTileIsClampedIntoTheDesktop() throws {
        let f = ref(2)
        let frame = Rect(x: 600, y: 100, width: 300, height: 200)
        let plan = try Planner.plan(desk: try desk(floating: [(f, frame)]), area: area, gap: 8, mins: [:])
        let desktop = try #require(plan.desktopRect)
        let clamped = Planner.clamp(frame, into: desktop)
        #expect(plan.frames[f] == clamped)
        #expect(clamped == Rect(x: desktop.minX, y: 100, width: 300, height: 200))
    }

    @Test func aFloatingWindowInsideTheDesktopIsLeftAlone() throws {
        let g = ref(3)
        let plan = try Planner.plan(desk: try desk(floating: [(g, Rect(x: 800, y: 100, width: 300, height: 200))]), area: area, gap: 8, mins: [:])
        #expect(plan.frames[g] == nil)
    }

    @Test func aFloatingWindowOffTheScreenEdgeButClearOfTilesIsLeftAlone() throws {
        let h = ref(4)
        let plan = try Planner.plan(desk: try desk(floating: [(h, Rect(x: 1300, y: 100, width: 300, height: 200))]), area: area, gap: 8, mins: [:])
        #expect(plan.frames[h] == nil)
    }

    @Test func theDesktopMinimumIsThePerAxisMaximumOfThePresentFloatingWindows() throws {
        let wide = ref(5), tall = ref(6)
        let desk = try desk(floating: [(wide, Rect(x: 800, y: 100, width: 300, height: 200)), (tall, Rect(x: 900, y: 100, width: 300, height: 200))])
        let mins = [wide: Size(width: 900, height: 100), tall: Size(width: 100, height: 500)]
        let plan = try Planner.plan(desk: desk, area: area, gap: 8, mins: mins)
        let desktop = try #require(plan.desktopRect)
        #expect(desktop.width >= 900)
        #expect(desktop.height >= 500)
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
}

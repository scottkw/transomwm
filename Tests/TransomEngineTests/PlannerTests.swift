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

    /// G-03-11: a floater is planned at its wanted frame, clamped only when that frame overlaps a docked tile.
    @Test func aShrunkFloaterWhoseWantedFrameIsClearOfTilesIsPlannedAtTheWantedFrame() throws {
        let f = ref(7)
        let wanted = Rect(x: 800, y: 100, width: 400, height: 500)
        let plan = try Planner.plan(
            desk: try desk(floating: [(f, Rect(x: 800, y: 300, width: 400, height: 250))]), area: area, gap: 8, mins: [:],
            wanted: [f.identity: wanted])
        #expect(plan.frames[f] == wanted)
    }

    @Test func aFloaterWhoseWantedFrameOverlapsATileIsPlannedAtItsClamp() throws {
        let f = ref(7)
        let wanted = Rect(x: 600, y: 100, width: 300, height: 200)
        let plan = try Planner.plan(
            desk: try desk(floating: [(f, Rect(x: 800, y: 300, width: 300, height: 200))]), area: area, gap: 8, mins: [:],
            wanted: [f.identity: wanted])
        let desktop = try #require(plan.desktopRect)
        #expect(plan.frames[f] == Planner.clamp(wanted, into: desktop))
    }

    @Test func aFloaterAtItsWantedFrameClearOfTilesIsLeftAlone() throws {
        let f = ref(7)
        let frame = Rect(x: 800, y: 100, width: 300, height: 200)
        let plan = try Planner.plan(desk: try desk(floating: [(f, frame)]), area: area, gap: 8, mins: [:], wanted: [f.identity: frame])
        #expect(plan.frames[f] == nil)
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

    /// Quick 261027-gqo (user decision 2026-10-27): at the exact centre, Dock's edge fallback ties to the left edge.
    @Test func dockTargetAtTheDesktopsExactCentreGoesLeft() throws {
        let desk = try desk()
        let plan = try Planner.plan(desk: desk, area: area, gap: 8, mins: [:])
        let desktop = try #require(plan.desktopRect)
        let centre = Point(x: desktop.midX, y: desktop.midY)
        #expect(Planner.dockTarget(at: centre, desk: desk, area: area, resolution: plan.resolution) == .tile(.desktop, .edge(.left)))
    }
}

/// G-03-6: on a 1024 pt display, H[Desktop, Notes] with Notes' 642 pt minimum, plus the given floaters.
private let small = Rect(x: 0, y: 25, width: 1024, height: 688)
private let notes = ref(10)

private func notesDesk(floating: [(WindowRef, Rect)]) throws -> Desk {
    var desk = Desk()
    var ids = IDSource()
    try desk.tree.insert(notes, at: .right, of: .desktop, ids: &ids)
    for (window, frame) in floating { try desk.desktop.add(window, frame: frame) }
    return desk
}

/// G-03-6: a floater whose minimum would push docked windows out does not size the Desktop tile.
extension PlannerTests {
    @Test func aFloaterTooBigForTheRoomDoesNotPushTheDockedWindowOut() throws {
        let big = ref(11)
        let frame = Rect(x: 100, y: 40, width: 800, height: 600)
        let desk = try notesDesk(floating: [(big, frame)])
        let mins = [notes: Size(width: 642, height: 100), big: Size(width: 768, height: 692)]
        let plan = try Planner.plan(desk: desk, area: small, gap: 12, mins: mins)
        #expect(plan.unfit.isEmpty)
        let tile = try #require(plan.frames[notes])
        #expect(tile.width >= 642)
        let desktop = try #require(plan.desktopRect)
        let alone = try resolve(desk.tree, in: small, mins: [notes: Size(width: 642, height: 100)], gap: 12)
        #expect(desktop == alone.desktopRect)
        #expect(tile == alone.windowRects[notes])
        #expect(plan.frames[big] == Planner.clamp(frame, into: desktop))
    }

    @Test func aFloaterThatFitsStillWidensTheDesktop() throws {
        let safari = ref(12)
        let desk = try notesDesk(floating: [(safari, Rect(x: 20, y: 40, width: 300, height: 300))])
        let mins = [notes: Size(width: 300, height: 100), safari: Size(width: 574, height: 100)]
        let plan = try Planner.plan(desk: desk, area: small, gap: 12, mins: mins)
        #expect(plan.unfit.isEmpty)
        #expect(try #require(plan.desktopRect).width >= 574)
    }

    @Test func theLargestFloaterIsDroppedAndASmallerOneStillSizesTheDesktop() throws {
        let safari = ref(12), big = ref(11)
        let desk = try notesDesk(floating: [
            (safari, Rect(x: 20, y: 40, width: 300, height: 300)), (big, Rect(x: 40, y: 60, width: 300, height: 300)),
        ])
        let mins = [notes: Size(width: 300, height: 100), safari: Size(width: 574, height: 100), big: Size(width: 768, height: 100)]
        let plan = try Planner.plan(desk: desk, area: small, gap: 12, mins: mins)
        #expect(plan.unfit.isEmpty)
        let desktop = try #require(plan.desktopRect)
        #expect(desktop.width >= 574)
        #expect(desktop.width < 768)
    }

    /// H[Desktop, Notes, x] with Notes' 400 pt minimum: the Desktop's own share is 288 pt, under a 300 pt floater.
    private func threeDocked(floating: [(WindowRef, Rect)]) throws -> Desk {
        var desk = try notesDesk(floating: floating)
        var ids = IDSource(next: 100)
        try desk.tree.insert(ref(16), at: .right, of: try #require(desk.tree.leaf(containing: notes)), ids: &ids)
        return desk
    }

    /// WR-02: the larger-area floater goes first, but once the real culprit is dropped too, it is added back.
    @Test func aFloaterDroppedOnlyForItsAreaIsAddedBack() throws {
        let tall = ref(13), wide = ref(14)
        let desk = try threeDocked(floating: [
            (tall, Rect(x: 20, y: 40, width: 300, height: 600)), (wide, Rect(x: 40, y: 60, width: 300, height: 200)),
        ])
        let mins = [notes: Size(width: 400, height: 100), tall: Size(width: 300, height: 600), wide: Size(width: 768, height: 200)]
        let plan = try Planner.plan(desk: desk, area: small, gap: 12, mins: mins)
        #expect(plan.unfit.isEmpty)
        #expect(try #require(plan.desktopRect).width >= 300)
    }

    /// WR-02: a width-only hint (area 0) sorts last, but the floater dropped before it is added back.
    @Test func aWidthOnlyHintIsNotKeptAtTheCostOfAFloaterThatFits() throws {
        let safari = ref(12), reminders = ref(15)
        let desk = try threeDocked(floating: [
            (safari, Rect(x: 20, y: 40, width: 300, height: 300)), (reminders, Rect(x: 40, y: 60, width: 300, height: 300)),
        ])
        let mins = [notes: Size(width: 400, height: 100), safari: Size(width: 300, height: 300), reminders: Size(width: 768, height: 0)]
        let plan = try Planner.plan(desk: desk, area: small, gap: 12, mins: mins)
        #expect(plan.unfit.isEmpty)
        #expect(try #require(plan.desktopRect).width >= 300)
    }

    @Test func aDockedWindowTooBigOnItsOwnIsStillUnfit() throws {
        let safari = ref(12)
        let desk = try notesDesk(floating: [(safari, Rect(x: 20, y: 40, width: 300, height: 300))])
        let mins = [notes: Size(width: 1100, height: 100), safari: Size(width: 574, height: 100)]
        let plan = try Planner.plan(desk: desk, area: small, gap: 12, mins: mins)
        #expect(plan.unfit == [notes])
        // Dropping the floater would not make room, so it keeps sizing the Desktop tile.
        #expect(try #require(plan.desktopRect).width >= 574)
    }
}

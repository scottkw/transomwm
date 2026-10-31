@testable import TransomEngine
import TransomModel
import Testing

private func ref(_ id: UInt32) -> WindowRef {
    WindowRef(identity: WindowIdentity(windowID: id, pid: 712, bundleID: "com.example.selection"))
}

private func window(_ id: UInt32, _ x: Double, _ y: Double, _ width: Double, _ height: Double) -> OverviewWindow {
    OverviewWindow(window: ref(id), frame: Rect(x: x, y: y, width: width, height: height))
}

/// A 40 × 40 window centred on (x, y).
private func dot(_ id: UInt32, _ x: Double, _ y: Double) -> OverviewWindow { window(id, x - 20, y - 20, 40, 40) }

private func display(
    _ uuid: String = "D", x: Double = 0, y: Double = 0, spaceCount: Int = 3, windows: [OverviewWindow] = [],
    hidden: [UInt64: [OverviewWindow]] = [:]
) -> OverviewDisplayInput {
    let spaces = (0..<spaceCount).map { i in
        SpaceInfo(id: UInt64(i + 1), uuid: "\(uuid)S\(i + 1)", kind: .desktop, displayUUID: uuid, index: i + 1)
    }
    return OverviewDisplayInput(
        uuid: uuid, visibleFrame: Rect(x: x, y: y, width: 1440, height: 900), spaces: spaces, current: spaceCount > 0 ? 1 : nil,
        windows: windows, hiddenSpaceWindows: hidden)
}

private func layout(_ displays: OverviewDisplayInput..., strip: Bool = true) -> OverviewLayout {
    OverviewLayout(displays: displays, stripShown: strip)
}

private func selected(_ item: OverviewItem, on display: String = "D") -> OverviewSelection {
    OverviewSelection(selected: item, display: display)
}

/// 06 UI-SPEC Surface 3 (D-04): the one selection, its initial item, the arrows, the strip, Tab, edges and closes.
@Suite struct OverviewSelectionTests {
    // MARK: Initial selection

    @Test func theFocusedWindowWinsWhereverItIs() {
        let l = layout(display("A", windows: [window(1, 0, 0, 720, 900)]), display("B", x: 1440, windows: [window(2, 1440, 0, 200, 200)]))
        let s = OverviewSelection.initial(layout: l, focused: ref(2), pointer: Point(x: 100, y: 450))
        #expect(s == OverviewSelection(selected: .tile(ref(2)), display: "B"))
    }

    @Test func aFocusedWindowNotShownFallsBackToTheTileUnderThePointer() throws {
        let l = layout(display(windows: [window(1, 0, 0, 1000, 900), window(2, 1100, 100, 200, 200)]))
        let small = try #require(l.displays[0].tiles.last).rect
        let s = OverviewSelection.initial(layout: l, focused: ref(9), pointer: Point(x: small.midX, y: small.midY))
        #expect(s.selected == .tile(ref(2)))
    }

    @Test func overTheBackdropTheLargestTileOnThePointersDisplayWins() {
        let l = layout(display(windows: [window(1, 0, 0, 1000, 900), window(2, 1100, 100, 200, 200)]))
        #expect(OverviewSelection.initial(layout: l, focused: nil, pointer: Point(x: 2, y: 899)).selected == .tile(ref(1)))
    }

    @Test func aPointerDisplayWithoutTilesTakesItsCurrentSpaceThumbnail() {
        let l = layout(display("A"), display("B", x: 1440, windows: [window(1, 1440, 0, 500, 500)]))
        #expect(OverviewSelection.initial(layout: l, focused: nil, pointer: Point(x: 100, y: 450)) == selected(.thumbnail(space: 1), on: "A"))
    }

    @Test func withTheStripHiddenTheFirstDisplayLeftToRightWithATileWins() {
        // Given right to left: the order comes from the frames.
        let l = layout(
            display("C", x: 2880, windows: [window(3, 2880, 0, 900, 900)]), display("B", x: 1440, windows: [window(2, 1440, 0, 300, 300)]),
            display("A"), strip: false)
        #expect(OverviewSelection.initial(layout: l, focused: nil, pointer: Point(x: 100, y: 450)) == selected(.tile(ref(2)), on: "B"))
    }

    @Test func noTilesAndNoStripSelectNothing() {
        #expect(OverviewSelection.initial(layout: layout(display(), strip: false), focused: nil, pointer: Point(x: 10, y: 10)).selected == nil)
    }

    // MARK: Arrows

    @Test func theConeBeatsANearerTileFarOffAxis() {
        // From (300, 500): 2 is 10° off the → axis and 609 pt away, 3 is 60° off and 300 pt away.
        let l = layout(display(windows: [dot(1, 300, 500), dot(2, 900, 605.8), dot(3, 450, 240.2)]), strip: false)
        var s = selected(.tile(ref(1)))
        s.move(.right, in: l)
        #expect(s.selected == .tile(ref(2)))
    }

    @Test func withNothingInTheConeTheNearestOnThatSideWins() {
        // Both 60° off the → axis; 3 is nearer.
        let l = layout(display(windows: [dot(1, 300, 500), dot(2, 600, 0), dot(3, 450, 760)]), strip: false)
        var s = selected(.tile(ref(1)))
        s.move(.right, in: l)
        #expect(s.selected == .tile(ref(3)))
    }

    @Test func equalDistancesResolveToTheFrontMostWindow() {
        // 2 and 3 mirror each other about the → axis; 3 is later in back-to-front order, so front-most.
        let l = layout(display(windows: [dot(1, 300, 450), dot(2, 700, 350), dot(3, 700, 550)]), strip: false)
        for _ in 0..<3 {
            var s = selected(.tile(ref(1)))
            s.move(.right, in: l)
            #expect(s.selected == .tile(ref(3)))
        }
    }

    @Test(arguments: [OverviewKey.left, .up, .down])
    func anArrowAtAnEdgeChangesNothing(key: OverviewKey) {
        let l = layout(display(windows: [window(1, 0, 0, 720, 900), window(2, 720, 0, 720, 900)]), strip: false)
        var s = selected(.tile(ref(1)))
        s.move(key, in: l)
        #expect(s == selected(.tile(ref(1))))
    }

    @Test func upFromTheTopRowGoesToTheThumbnailNearestInX() {
        // Right half's tile centre (x ≈ 1003) is nearest the third thumbnail (x ≈ 909).
        let l = layout(display(windows: [window(1, 0, 0, 720, 900), window(2, 720, 0, 720, 900)]))
        var s = selected(.tile(ref(2)))
        s.move(.up, in: l)
        #expect(s == selected(.thumbnail(space: 3)))
    }

    @Test func downFromAThumbnailGoesToTheTileNearestInX() {
        let l = layout(display(windows: [window(1, 0, 0, 720, 900), window(2, 720, 0, 720, 900)]))
        var s = selected(.thumbnail(space: 1))
        s.move(.down, in: l)
        #expect(s.selected == .tile(ref(1)))
    }

    @Test func leftAndRightInTheStripMoveBetweenThumbnails() {
        let l = layout(display(windows: [window(1, 0, 0, 720, 900)]))
        var s = selected(.thumbnail(space: 2))
        s.move(.right, in: l)
        #expect(s.selected == .thumbnail(space: 3))
        s.move(.right, in: l)  // the last thumbnail: nothing beyond
        #expect(s.selected == .thumbnail(space: 3))
        s.move(.left, in: l)
        s.move(.left, in: l)
        s.move(.left, in: l)
        #expect(s.selected == .thumbnail(space: 1))
        s.move(.up, in: l)
        #expect(s.selected == .thumbnail(space: 1))
    }

    @Test func downFromTheStripWithoutTilesDoesNotMove() {
        let l = layout(display())
        var s = selected(.thumbnail(space: 2))
        s.move(.down, in: l)
        #expect(s.selected == .thumbnail(space: 2))
    }

    @Test func arrowsNeverReachMiniTiles() throws {
        // Space 3 holds a hidden window under the thumbnail ↑ lands on; space 1's mini tile is window 2 itself.
        let l = layout(display(windows: [window(1, 0, 0, 720, 900), window(2, 720, 0, 720, 900)], hidden: [3: [window(5, 0, 0, 1440, 900)]]))
        try #require(l.displays[0].thumbnails[2].miniTiles.count == 1)
        var s = selected(.tile(ref(2)))
        s.move(.up, in: l)
        #expect(s.selected == .thumbnail(space: 3))
        s.move(.down, in: l)
        #expect(s.selected == .tile(ref(2)))
    }

    @Test func fromAMiniTileTheArrowsActAsFromItsThumbnail() {
        let l = layout(display(windows: [window(1, 0, 0, 720, 900)], hidden: [2: [window(5, 0, 0, 1440, 900)]]))
        var s = selected(.miniTile(ref(5), space: 2))
        s.move(.right, in: l)
        #expect(s.selected == .thumbnail(space: 3))
    }

    // MARK: Tab

    @Test func tabGoesLeftToRightAndWrapsAndBackTabReverses() {
        let l = layout(display("B", x: 1440, windows: [window(2, 1440, 0, 500, 500)]), display("A", windows: [window(1, 0, 0, 500, 500)]))
        var s = selected(.tile(ref(1)), on: "A")
        s.move(.tab, in: l)
        #expect(s == selected(.tile(ref(2)), on: "B"))
        s.move(.tab, in: l)
        #expect(s == selected(.tile(ref(1)), on: "A"))
        s.move(.backTab, in: l)
        #expect(s == selected(.tile(ref(2)), on: "B"))
    }

    @Test func displaysWithEqualLeftEdgesOrderByTopEdgeThenUUID() {
        let l = layout(
            display("Z", y: 0, windows: [window(1, 0, 0, 500, 500)]), display("M", y: -900, windows: [window(2, 0, -900, 500, 500)]),
            display("K", y: 0, windows: [window(3, 0, 0, 500, 500)]), strip: false)
        var s = selected(.tile(ref(2)), on: "M")
        s.move(.tab, in: l)
        #expect(s.display == "K")
        s.move(.tab, in: l)
        #expect(s.display == "Z")
        s.move(.tab, in: l)
        #expect(s.display == "M")
    }

    @Test func tabLandsOnTheFocusedWindowElseTheLargestElseTheCurrentThumbnail() {
        let l = layout(
            display("A", windows: [window(1, 0, 0, 500, 500)]),
            display("B", x: 1440, windows: [window(2, 1440, 0, 900, 900), window(3, 2400, 0, 200, 200)]), display("C", x: 2880))
        var s = selected(.tile(ref(1)), on: "A")
        s.move(.tab, in: l, focused: ref(3))
        #expect(s.selected == .tile(ref(3)))
        s = selected(.tile(ref(1)), on: "A")
        s.move(.tab, in: l)
        #expect(s.selected == .tile(ref(2)))
        s.move(.tab, in: l)
        #expect(s == selected(.thumbnail(space: 1), on: "C"))
    }

    @Test func tabWithOneDisplayStaysPut() {
        let l = layout(display(windows: [window(1, 0, 0, 900, 900), window(2, 900, 0, 540, 900)]))
        var s = selected(.tile(ref(2)))
        s.move(.tab, in: l)
        s.move(.backTab, in: l)
        #expect(s == selected(.tile(ref(2))))
    }

    // MARK: Title capsule

    @Test func theTitleCapsuleSitsInsideATallTileAndIsCappedToItsWidth() {
        let area = Rect(x: 24, y: 169, width: 1392, height: 707)
        let r = OverviewLayout.titleCapsule(tile: Rect(x: 100, y: 200, width: 300, height: 200), mainArea: area, size: Size(width: 400, height: 24))
        #expect(r == Rect(x: 116, y: 368, width: 268, height: 24))  // 400 − 8 − 24; width 300 − 32
    }

    @Test func aShortTileGetsItsCapsuleBelowItKeptInTheMainArea() {
        let area = Rect(x: 24, y: 169, width: 1392, height: 707)
        let below = OverviewLayout.titleCapsule(tile: Rect(x: 100, y: 200, width: 300, height: 30), mainArea: area, size: Size(width: 100, height: 24))
        #expect(below == Rect(x: 200, y: 238, width: 100, height: 24))
        let clamped = OverviewLayout.titleCapsule(tile: Rect(x: 100, y: 840, width: 300, height: 30), mainArea: area, size: Size(width: 100, height: 24))
        #expect(clamped?.y == 852)  // the main area ends at 876
        #expect(OverviewLayout.titleCapsule(tile: Rect(x: 0, y: 200, width: 40, height: 200), mainArea: area, size: Size(width: 100, height: 24)) == nil)
    }

    // MARK: A window closed while open

    @Test func closingTheSelectedWindowSelectsTheNearestRemainingTile() {
        let l = layout(display(windows: [dot(1, 200, 450), dot(2, 700, 450), dot(3, 1300, 450)]))
        var s = selected(.tile(ref(2)))
        s.reselect(afterRemoving: ref(2), in: l)
        #expect(s.selected == .tile(ref(1)))
    }

    @Test func closingTheLastTileSelectsTheCurrentSpaceThumbnail() {
        let l = layout(display(windows: [dot(1, 200, 450)]))
        var s = selected(.tile(ref(1)))
        s.reselect(afterRemoving: ref(1), in: l)
        #expect(s.selected == .thumbnail(space: 1))
    }

    @Test func closingAnotherWindowKeepsTheSelection() {
        let l = layout(display(windows: [dot(1, 200, 450), dot(2, 700, 450)]))
        var s = selected(.tile(ref(2)))
        s.reselect(afterRemoving: ref(1), in: l)
        #expect(s == selected(.tile(ref(2))))
    }
}

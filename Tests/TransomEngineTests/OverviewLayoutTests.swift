@testable import TransomEngine
import TransomModel
import Testing

private func ref(_ id: UInt32) -> WindowRef {
    WindowRef(identity: WindowIdentity(windowID: id, pid: 711, bundleID: "com.example.overview"))
}

private func spaces(_ count: Int, display: String = "D", fullScreen: Set<Int> = []) -> [SpaceInfo] {
    var desktops = 0
    return (0..<count).map { i in
        let full = fullScreen.contains(i)
        if !full { desktops += 1 }
        return SpaceInfo(
            id: UInt64(i + 1), uuid: "S\(i + 1)", kind: full ? .fullScreen : .desktop, displayUUID: display, index: full ? 0 : desktops)
    }
}

private let wide = Rect(x: 0, y: 0, width: 1440, height: 900)

private func display(
    _ visible: Rect = wide, uuid: String = "D", isMain: Bool = true, spaceCount: Int = 3, fullScreen: Set<Int> = [],
    windows: [OverviewWindow] = [], home: [WindowRef: Rect] = [:], hidden: [UInt64: [OverviewWindow]] = [:]
) -> OverviewDisplayInput {
    OverviewDisplayInput(
        uuid: uuid, visibleFrame: visible, isMain: isMain, spaces: spaces(spaceCount, display: uuid, fullScreen: fullScreen), current: 1,
        windows: windows, home: home, hiddenSpaceWindows: hidden)
}

private func near(_ a: Double, _ b: Double) -> Bool { abs(a - b) < 0.001 }

private func near(_ a: Rect, _ b: Rect) -> Bool { near(a.x, b.x) && near(a.y, b.y) && near(a.width, b.width) && near(a.height, b.height) }

/// 06 UI-SPEC Spacing Scale exceptions, Surfaces 1-2: every overview rect.
@Suite struct OverviewLayoutTests {
    @Test func aWideDisplayWithThreeSpacesGetsTheSpecStripAndMainArea() throws {
        let layout = try #require(OverviewLayout(displays: [display()], stripShown: true).displays.first)
        #expect(layout.thumbnails.count == 3)
        let first = try #require(layout.thumbnails.first)
        #expect(near(first.rect.height, 108))
        #expect(near(first.rect.width, 172.8))
        let band = try #require(layout.stripBand)
        #expect(near(band, Rect(x: 0, y: 0, width: 1440, height: 169)))  // 16 + 108 + 8 + 21 + 16
        #expect(near(layout.mainArea, Rect(x: 24, y: 169, width: 1392, height: 900 - 169 - 24)))
    }

    @Test func aPlaceholderIsDrawnButNeverCountedOrSelected() throws {
        let one = ref(1), two = ref(2), waiting = ref(3)
        var input = display(windows: [
            OverviewWindow(window: one, frame: Rect(x: 0, y: 0, width: 400, height: 900)), OverviewWindow(window: two, frame: Rect(x: 400, y: 0, width: 400, height: 900)),
        ])
        input.placeholders = [OverviewWindow(window: waiting, frame: Rect(x: 800, y: 0, width: 640, height: 900))]
        let layout = OverviewLayout(displays: [input], stripShown: true)
        let shown = try #require(layout.displays.first)
        #expect(shown.tiles.map(\.window) == [one, two], "2 windows")
        let tile = try #require(shown.placeholders.first)
        #expect(tile.window == waiting)
        #expect(layout.item(at: Point(x: tile.rect.midX, y: tile.rect.midY)) == nil)
        #expect(OverviewSelection.initial(layout: layout, focused: waiting, pointer: Point(x: tile.rect.midX, y: tile.rect.midY)).selected != .tile(waiting))
        #expect(shown.thumbnails.first?.miniTiles.map(\.window) == [one, two])
    }

    @Test(arguments: [(600.0, 72.0), (400.0, 64.0), (1200.0, 112.0)])
    func thumbnailHeightIsTwelvePercentClamped(height: Double, expected: Double) throws {
        let input = display(Rect(x: 0, y: 0, width: height * 1.6, height: height))
        let layout = try #require(OverviewLayout(displays: [input], stripShown: true).displays.first)
        #expect(near(try #require(layout.thumbnails.first).rect.height, expected))
    }

    @Test func sixteenSpacesShrinkUniformlyIntoOneRowThatFits() throws {
        let input = display(Rect(x: 0, y: 0, width: 1280, height: 800), spaceCount: 16)
        let layout = try #require(OverviewLayout(displays: [input], stripShown: true).displays.first)
        let thumbs = layout.thumbnails
        #expect(thumbs.count == 16)
        #expect(Set(thumbs.map(\.rect.height)).count == 1 && Set(thumbs.map(\.rect.minY)).count == 1)  // one size, one row
        let height = try #require(thumbs.first).rect.height
        #expect(height >= OverviewLayout.thumbnailMin && height < 96)
        let row = try #require(thumbs.last).rect.maxX - (try #require(thumbs.first).rect.minX)
        #expect(row <= 1232 + 0.001)
    }

    @Test func narrowDisplaysStopShrinkingAtThirtyTwo() throws {
        let input = display(Rect(x: 0, y: 0, width: 800, height: 500), spaceCount: 16)
        let layout = try #require(OverviewLayout(displays: [input], stripShown: true).displays.first)
        #expect(near(try #require(layout.thumbnails.first).rect.height, 32))
    }

    @Test func seventeenSpacesAreCappedAtSixteen() throws {
        let layout = try #require(OverviewLayout(displays: [display(spaceCount: 17)], stripShown: true).displays.first)
        #expect(layout.thumbnails.count == 16)
    }

    @Test func thumbnailsAreACentredRowSixteenApartWithLabelsBelow() throws {
        let layout = try #require(OverviewLayout(displays: [display()], stripShown: true).displays.first)
        let thumbs = layout.thumbnails
        for (left, right) in zip(thumbs, thumbs.dropFirst()) { #expect(near(right.rect.minX - left.rect.maxX, 16)) }
        let first = try #require(thumbs.first), last = try #require(thumbs.last)
        #expect(near(first.rect.minX - 0, 1440 - last.rect.maxX))
        #expect(near(first.rect.minY, 16))
        for thumb in thumbs {
            #expect(near(thumb.labelRect, Rect(x: thumb.rect.minX, y: thumb.rect.maxY + 8, width: thumb.rect.width, height: 21)))
        }
    }

    @Test func aHiddenStripLeavesNoBandAndInsetsTheMainAreaOnAllSides() throws {
        let layout = try #require(OverviewLayout(displays: [display()], stripShown: false).displays.first)
        #expect(layout.stripBand == nil && layout.thumbnails.isEmpty)
        #expect(near(layout.mainArea, Rect(x: 24, y: 24, width: 1392, height: 852)))
    }

    @Test func sharedSpacesDrawTheStripOnlyOnTheMainDisplay() {
        let main = display(uuid: "M"), other = display(Rect(x: 1440, y: 0, width: 1440, height: 900), uuid: "O", isMain: false)
        let layout = OverviewLayout(displays: [main, other], stripShown: true, separateSpaces: false)
        #expect(layout.displays.map { $0.thumbnails.count } == [3, 0])
        #expect(layout.displays[1].stripBand == nil)
        #expect(near(layout.displays[1].mainArea, Rect(x: 1464, y: 24, width: 1392, height: 852)))
    }

    @Test func aSingleSpaceStillShowsItsThumbnail() throws {
        let layout = try #require(OverviewLayout(displays: [display(spaceCount: 1)], stripShown: true).displays.first)
        #expect(layout.thumbnails.count == 1)
        #expect(layout.thumbnails.first?.isCurrent == true)
    }

    @Test func anEmptyCurrentSpaceGetsACentredCapsuleAndNoTiles() throws {
        let layout = try #require(
            OverviewLayout(displays: [display()], stripShown: true, emptyCapsuleSize: Size(width: 200, height: 24)).displays.first)
        #expect(layout.tiles.isEmpty)
        let capsule = try #require(layout.emptyCapsule)
        #expect(near(capsule.midX, layout.mainArea.midX) && near(capsule.midY, layout.mainArea.midY))
        #expect(near(capsule.width, 200) && near(capsule.height, 24))
        #expect(OverviewLayout(displays: [display()], stripShown: true).item(at: Point(x: capsule.midX, y: capsule.midY)) == nil)
    }

    @Test func identicalFramesKeepTheirOrderAndTheFrontOneIsHit() throws {
        let frame = Rect(x: 100, y: 100, width: 400, height: 300)
        let back = OverviewWindow(window: ref(1), frame: frame), front = OverviewWindow(window: ref(2), frame: frame)
        let layout = OverviewLayout(displays: [display(windows: [back, front])], stripShown: true)
        let tiles = try #require(layout.displays.first).tiles
        #expect(tiles.map(\.window) == [ref(1), ref(2)])
        #expect(tiles[0].rect == tiles[1].rect)
        #expect(layout.item(at: Point(x: tiles[1].rect.midX, y: tiles[1].rect.midY)) == .tile(ref(2)))
    }

    @Test func mainAreaTilesScaleUniformlyAndCentre() throws {
        let window = OverviewWindow(window: ref(1), frame: wide)
        let layout = try #require(OverviewLayout(displays: [display(windows: [window])], stripShown: true).displays.first)
        let tile = try #require(layout.tiles.first).rect
        #expect(near(tile.width / tile.height, 1.6))
        #expect(near(tile.midX, layout.mainArea.midX) && near(tile.midY, layout.mainArea.midY))
        #expect(near(tile.height, layout.mainArea.height) || near(tile.width, layout.mainArea.width))
        #expect(near(layout.scale, tile.width / 1440))
    }

    @Test func hiddenSpaceWindowsAreMiniTilesScaledIntoTheirThumbnail() throws {
        let window = OverviewWindow(window: ref(5), frame: Rect(x: 0, y: 0, width: 720, height: 450))
        let layout = OverviewLayout(displays: [display(hidden: [2: [window]])], stripShown: true)
        let thumb = try #require(layout.displays.first?.thumbnails.first { $0.spaceID == 2 })
        let mini = try #require(thumb.miniTiles.first)
        #expect(mini.window == ref(5))
        #expect(near(mini.rect, Rect(x: thumb.rect.minX, y: thumb.rect.minY, width: thumb.rect.width / 2, height: thumb.rect.height / 2)))
        #expect(layout.item(at: Point(x: mini.rect.midX, y: mini.rect.midY)) == .miniTile(ref(5), space: 2))
        #expect(layout.item(at: Point(x: thumb.rect.maxX - 2, y: thumb.rect.maxY - 2)) == .thumbnail(space: 2))
    }

    @Test func theCurrentThumbnailShowsTheCurrentWindows() throws {
        let window = OverviewWindow(window: ref(1), frame: Rect(x: 0, y: 0, width: 720, height: 900))
        let layout = OverviewLayout(displays: [display(windows: [window])], stripShown: true)
        let current = try #require(layout.displays.first?.thumbnails.first { $0.isCurrent })
        #expect(current.spaceID == 1)
        #expect(current.miniTiles.map(\.window) == [ref(1)])
    }

    @Test func aFullScreenSpaceIsOneMiniTileFillingItsThumbnail() throws {
        let window = OverviewWindow(window: ref(9), frame: Rect(x: 200, y: 100, width: 300, height: 200))
        let layout = OverviewLayout(displays: [display(fullScreen: [2], hidden: [3: [window]])], stripShown: true)
        let thumb = try #require(layout.displays.first?.thumbnails.first { $0.spaceID == 3 })
        #expect(thumb.miniTiles.count == 1)
        #expect(thumb.miniTiles.first.map { near($0.rect, thumb.rect) } == true)
    }

    @Test func aZoomedDisplayUsesHomeViewRects() throws {
        let parked = OverviewWindow(window: ref(3), frame: Rect(x: 1439, y: 899, width: 600, height: 400))
        let home = Rect(x: 0, y: 0, width: 720, height: 900)
        let layout = try #require(OverviewLayout(displays: [display(windows: [parked], home: [ref(3): home])], stripShown: false).displays.first)
        let tile = try #require(layout.tiles.first).rect
        let originX = layout.mainArea.midX - 1440 * layout.scale / 2  // height-limited: centred across, flush top and bottom
        #expect(near(tile, Rect(x: originX, y: 24, width: 720 * layout.scale, height: 900 * layout.scale)))
    }

    @Test func fullScreenDisplaysGetNoLayout() {
        var full = display(uuid: "F")
        full.isFullScreen = true
        let layout = OverviewLayout(displays: [full, display(Rect(x: 1440, y: 0, width: 1440, height: 900), uuid: "N", isMain: false)])
        #expect(layout.displays.map(\.uuid) == ["N"])
    }
}

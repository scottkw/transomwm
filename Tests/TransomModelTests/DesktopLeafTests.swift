import Foundation
import Testing
@testable import TransomModel

private let a = makeWindow(1)
private let b = makeWindow(2)
private let key = DeskKey(displayUUID: "D1", spaceID: nil)
private let screen = Rect(x: 0, y: 25, width: 1440, height: 875)

/// A world with one fresh desk, then `a` docked by a drop on the Desktop tile's left edge.
private func dockedBesideDesktop() throws -> World {
    var world = World()
    try world.addDesk(key)
    var history = UndoHistory()
    try world.edit(key, history: &history) { desk, ids throws(LayoutError) in
        try desk.tree.applyDrop(.tile(.desktop, .edge(.left)), window: a, ids: &ids)
    }
    return world
}

/// H[a, Desktop], built on a raw tree.
private func besideDesktop() throws -> LayoutTree {
    var ids = IDSource()
    var tree = LayoutTree.withDesktop()
    try tree.insert(a, at: .left, of: .desktop, ids: &ids)
    return tree
}

@Suite struct DesktopLeafTests {
    @Test func aNewDeskIsTheDesktopTileAlone() throws {
        let desk = Desk()
        #expect(desk.tree.root == .desktop)
        #expect(desk.tree.nodes[.desktop] == .desktop(hidden: false))
        #expect(desk.tree.windows.isEmpty)
        #expect(desk.tree.isDesktopHidden == false)
        try desk.validate()
    }

    @Test func theLoneDesktopGetsTheRectALonePanelGets() throws {
        let lone = try LayoutTree(root: NodeID(raw: 1), nodes: [NodeID(raw: 1): .panel(a)], states: [a.identity: .present])
        let panelRect = try #require(try resolve(lone, in: screen, mins: [:], gap: 8).windowRects[a])
        let resolution = try resolve(Desk().tree, in: screen, mins: [:], gap: 8)
        #expect(resolution.desktopRect == panelRect)
        #expect(resolution.windowRects.isEmpty)
    }

    @Test func dockingBesideTheDesktopShrinksItWithoutOverlap() throws {
        let tree = try #require(try dockedBesideDesktop()[key]).tree
        let leaf = try #require(tree.leaf(containing: a))
        let root = try #require(tree.root)
        #expect(tree.nodes[root] == .split(axis: .horizontal, children: [leaf, .desktop], weights: [0.5, 0.5]))

        let resolution = try resolve(tree, in: screen, mins: [:], gap: 8)
        let window = try #require(resolution.windowRects[a])
        let desktop = try #require(resolution.desktopRect)
        #expect(window.maxX < desktop.minX)
        #expect(desktop.width < screen.width - 16)
        // The Desktop is an ordinary non-split rect to the drop zones, so its edge bands dock beside it.
        let point = Point(x: desktop.maxX - desktop.width * 0.1, y: desktop.midY)
        #expect(DropZones.target(at: point, in: screen, tree: tree, resolution: resolution) == .tile(.desktop, .edge(.right)))
    }

    @Test func windowsAndLeafLookupNeverReportTheDesktop() throws {
        let tree = try #require(try dockedBesideDesktop()[key]).tree
        #expect(tree.windows == [a])
        #expect(tree.leaf(containing: a) != .desktop)
    }

    @Test func theSavedWorldCarriesTheDesktopTileAndRoundTrips() throws {
        let world = try dockedBesideDesktop()
        let data = try world.encoded()
        // The Desk's Desktop layer already encodes under "desktop", so look for the tile's "hidden" too.
        #expect(String(decoding: data, as: UTF8.self).contains(#""0":{"desktop":{"hidden":false}}"#))
        #expect(try World.decode(from: data) == world)
    }

    @Test func theDesktopTileIsOnlyValidUnderItsReservedID() {
        #expect(throws: LayoutError.self) {
            try LayoutTree(root: NodeID(raw: 7), nodes: [NodeID(raw: 7): .desktop(hidden: false)], states: [:])
        }
    }

    @Test func aWorldWhoseIDSourceCouldMintTheDesktopIDIsInvalid() {
        #expect(throws: LayoutError.self) { try World(ids: IDSource(next: 0), desks: [:]) }
    }

    @Test func hidingTheDesktopWhileNothingIsDockedIsRefused() {
        var tree = LayoutTree.withDesktop()
        #expect(throws: LayoutError.nothingDocked) { try tree.setDesktopHidden(true) }
        #expect(tree == LayoutTree.withDesktop())
    }

    @Test func hidingTheDesktopGivesItsSpaceToTheDockedTilesAndShowingRestoresThem() throws {
        var tree = try besideDesktop()
        let before = try resolve(tree, in: screen, mins: [:], gap: 8)
        try tree.setDesktopHidden(true)
        #expect(tree.isDesktopHidden == true)

        let hidden = try resolve(tree, in: screen, mins: [:], gap: 8)
        #expect(hidden.desktopRect == nil)
        #expect(hidden.windowRects[a] == (try resolve(Desk().tree, in: screen, mins: [:], gap: 8)).desktopRect)

        try tree.setDesktopHidden(false)
        #expect(try resolve(tree, in: screen, mins: [:], gap: 8) == before)
    }

    @Test(arguments: [false, true])
    func removingTheLastDockedWindowLeavesTheVisibleDesktopAlone(hiddenFirst: Bool) throws {
        var tree = try besideDesktop()
        if hiddenFirst { try tree.setDesktopHidden(true) }
        try tree.remove(a)
        #expect(tree == LayoutTree.withDesktop())
        #expect(tree.isDesktopHidden == false)
    }

    @Test func groupingAWindowIntoTheDesktopIsRefused() throws {
        var tree = try besideDesktop()
        let before = tree
        #expect(throws: LayoutError.desktopTile(.desktop)) { try tree.group(b, into: .desktop) }
        #expect(tree == before)
    }

    @Test func dockingBelowTheDesktopNestsBesideItAndNormalizeKeepsIt() throws {
        var ids = IDSource(next: 10)
        var tree = try besideDesktop()
        try tree.insert(b, at: .bottom, of: .desktop, ids: &ids)
        let aLeaf = try #require(tree.leaf(containing: a)), bLeaf = try #require(tree.leaf(containing: b))
        let root = try #require(tree.root)
        guard case let .split(.horizontal, children, _)? = tree.nodes[root], children.count == 2, children[0] == aLeaf else {
            Issue.record("expected H[a, V[Desktop, b]], got \(tree.nodes)")
            return
        }
        #expect(tree.nodes[children[1]] == .split(axis: .vertical, children: [.desktop, bLeaf], weights: [0.5, 0.5]))

        try tree.remove(b)
        #expect(tree.nodes[.desktop] == .desktop(hidden: false))
        #expect(tree.nodes[root] == .split(axis: .horizontal, children: [aLeaf, .desktop], weights: [0.5, 0.5]))
    }

    @Test func theDesktopIsNeverTheUnfitTile() throws {
        let area = Rect(x: 0, y: 0, width: 1440, height: 900)
        let resolution = try resolve(
            besideDesktop(), in: area, mins: [a: Size(width: 1000, height: 1)], gap: 8, desktopMinimum: Size(width: 600, height: 1))
        #expect(resolution.unfit == [a])
        #expect(resolution.desktopRect == Rect(x: 8, y: 8, width: 1424, height: 884))
    }

    @Test func aDesktopMinimumLargerThanTheAreaGetsTheWholeArea() throws {
        let area = Rect(x: 0, y: 0, width: 1440, height: 900)
        let resolution = try resolve(besideDesktop(), in: area, mins: [:], gap: 8, desktopMinimum: Size(width: 5000, height: 1))
        #expect(resolution.unfit == [a])
        #expect(resolution.desktopRect == Rect(x: 8, y: 8, width: 1424, height: 884))
    }

    @Test func anInvalidDesktopMinimumIsRefused() {
        #expect(throws: LayoutError.invalidGeometry("desktop minimum")) {
            try resolve(Desk().tree, in: screen, mins: [:], gap: 8, desktopMinimum: Size(width: -1, height: 1))
        }
    }

    @Test func hidingATreeWithoutTheDesktopTileThrowsNodeNotFound() {
        var tree = LayoutTree()
        #expect(throws: LayoutError.nodeNotFound(.desktop)) { try tree.setDesktopHidden(true) }
    }
}

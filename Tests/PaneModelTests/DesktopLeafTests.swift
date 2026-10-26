import Foundation
import Testing
@testable import PaneModel

private let a = makeWindow(1)
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

    @Test func aDeskWithoutTheDesktopTileIsInvalid() {
        #expect(throws: LayoutError.self) { try Desk(tree: LayoutTree()).validate() }
    }

    @Test func aWorldWhoseIDSourceCouldMintTheDesktopIDIsInvalid() {
        #expect(throws: LayoutError.self) { try World(ids: IDSource(next: 0), desks: [:]) }
    }
}

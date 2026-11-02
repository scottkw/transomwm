import Foundation
import Testing
@testable import TransomModel

private let a = makeWindow(1)
private let b = makeWindow(2)
private let c = makeWindow(3)
private let w = makeWindow(9)
private let ghost = makeWindow(99)

private func n(_ raw: UInt64) -> NodeID { NodeID(raw: raw) }

private let area = Rect(x: 0, y: 0, width: 1200, height: 800)
private let floatFrame = Rect(x: 50, y: 60, width: 400, height: 300)

/// H[A, B, C]: A n1, B n2, C n4 under split n3.
private func triple() throws -> (LayoutTree, IDSource) {
    var tree = LayoutTree()
    var ids = IDSource()
    try tree.insertRoot(a, ids: &ids)
    try tree.insert(b, at: .right, of: n(1), ids: &ids)
    try tree.insert(c, at: .right, of: n(2), ids: &ids)
    return (tree, ids)
}

/// The same windows docked as a desk holds them, beside the Desktop tile: H[A, B, C, Desktop].
private func deskTriple() throws -> (LayoutTree, IDSource) {
    var tree = LayoutTree.withDesktop()
    var ids = IDSource()
    try tree.insert(a, at: .left, of: .desktop, ids: &ids)
    try tree.insert(b, at: .right, of: #require(tree.leaf(containing: a)), ids: &ids)
    try tree.insert(c, at: .right, of: #require(tree.leaf(containing: b)), ids: &ids)
    return (tree, ids)
}

private func layout(_ tree: LayoutTree) throws -> Resolution {
    try resolve(tree, in: area, mins: [:], gap: 8)
}

@Suite struct LifecycleTests {
    @Test(arguments: [WindowState.absent, .fullscreen])
    func aHiddenWindowKeepsItsSlotAndComesBackToTheSameRects(state: WindowState) throws {
        var (tree, _) = try triple()
        let nodesBefore = tree.nodes
        let before = try layout(tree)

        try tree.setState(state, for: b)
        #expect(tree.nodes == nodesBefore)
        #expect(tree.state(of: b) == state)
        let hidden = try layout(tree)
        let ra = try #require(hidden.windowRects[a])
        let rc = try #require(hidden.windowRects[c])
        #expect(hidden.windowRects[b] == nil)
        #expect(!hidden.unfit.contains(b))
        #expect(ra.minX == 8)
        #expect(rc.maxX == 1192)
        #expect(ra.width + 8 + rc.width == 1184)

        try tree.setState(.present, for: b)
        #expect(try layout(tree) == before)
    }

    @Test func absentThenFullscreenThenPresentRestoresTheOriginalResolution() throws {
        var (tree, _) = try triple()
        let before = try layout(tree)
        try tree.setState(.absent, for: b)
        try tree.setState(.fullscreen, for: b)
        #expect(tree.state(of: b) == .fullscreen)
        try tree.setState(.present, for: b)
        #expect(try layout(tree) == before)
    }

    @Test func closedIsNotAStoredStateSoTheTreeRejectsIt() throws {
        // Only World.apply closes a window (it also purges undo history); see UndoTests.
        var (tree, _) = try triple()
        let before = tree
        #expect(throws: LayoutError.self) { try tree.setState(.closed, for: b) }
        #expect(tree == before)
    }

    @Test func unknownWindowThrowsAndChangesNothing() throws {
        var (tree, _) = try triple()
        let before = tree
        for state in WindowState.allCases {
            #expect(throws: LayoutError.windowNotFound(ghost)) { try tree.setState(state, for: ghost) }
        }
        #expect(tree == before)
    }

    @Test func everyWindowAbsentResolvesEmptyAndKeepsTheTree() throws {
        var (tree, _) = try triple()
        let nodesBefore = tree.nodes
        let before = try layout(tree)
        for window in [a, b, c] { try tree.setState(.absent, for: window) }
        let empty = try layout(tree)
        #expect(empty.windowRects.isEmpty)
        #expect(empty.nodeRects.isEmpty)
        #expect(empty.unfit.isEmpty)
        #expect(tree.nodes == nodesBefore)
        for window in [a, b, c] { try tree.setState(.present, for: window) }
        #expect(try layout(tree) == before)
    }

    @Test func anAbsentHiddenTabLeavesItsGroupPlacedAndAnAbsentSelectedOneReservesTheSlot() throws {
        var (tree, ids) = try triple()
        try tree.remove(c)
        try tree.remove(b)
        try tree.group(b, into: n(1))
        try tree.insert(c, at: .right, of: n(1), ids: &ids)
        try tree.setState(.absent, for: a)
        let r = try layout(tree)
        let group = try #require(r.nodeRects[n(1)])
        #expect(r.windowRects[b] == TabBand.content(of: group))
        #expect(r.windowRects[a] == nil)
        #expect(r.hiddenTabs.isEmpty)

        try tree.selectTab(a)
        let reserved = try layout(tree)
        #expect(reserved.nodeRects[n(1)] == nil, "a group whose selected tab is absent took part")
        #expect(reserved.windowRects[b] == nil && reserved.hiddenTabs.isEmpty)
        #expect(tree.node(n(1)) == .tabs(windows: [a, b], selected: 0))
    }

    @Test func deskSetStateHandlesFloatingWindows() throws {
        var desk = Desk()
        try desk.desktop.add(w, frame: floatFrame)
        try desk.setState(.absent, for: w)
        #expect(desk.desktop.windows == [FloatingWindow(window: w, frame: floatFrame, state: .absent)])
        try desk.setState(.present, for: w)
        #expect(desk.desktop.windows.first?.state == .present)
        #expect(throws: LayoutError.self) { try desk.setState(.closed, for: w) }
        try desk.close(w)
        #expect(!desk.desktop.contains(w))
        #expect(throws: LayoutError.windowNotFound(w)) { try desk.setState(.absent, for: w) }
    }

    @Test func deskSetStateRoutesDockedWindowsThroughTheTree() throws {
        var (tree, _) = try deskTriple()
        var desk = Desk(tree: tree)
        try desk.desktop.add(w, frame: floatFrame)
        try desk.setState(.fullscreen, for: b)
        try tree.setState(.fullscreen, for: b)
        #expect(desk.tree == tree)
        try desk.close(b)
        try tree.remove(b)
        #expect(desk.tree == tree)
        #expect(desk.desktop.contains(w))
        let before = desk
        #expect(throws: LayoutError.windowNotFound(ghost)) { try desk.setState(.absent, for: ghost) }
        #expect(desk == before)
    }

    @Test func desktopLayerSetStateRejectsClosedAndUnknownWindows() throws {
        var layer = DesktopLayer()
        try layer.add(w, frame: floatFrame)
        let before = layer
        #expect(throws: LayoutError.self) { try layer.setState(.closed, for: w) }
        #expect(throws: LayoutError.windowNotFound(ghost)) { try layer.setState(.absent, for: ghost) }
        #expect(layer == before)
        try layer.setState(.fullscreen, for: w)
        #expect(layer.frame(of: w) == floatFrame)
        #expect(layer.windows.first?.state == .fullscreen)
    }

    @Test func lifecycleStatesSurviveAWorldJSONRoundTrip() throws {
        let (tree, ids) = try deskTriple()
        var desk = Desk(tree: tree)
        try desk.desktop.add(w, frame: floatFrame)
        try desk.setState(.absent, for: b)
        try desk.setState(.fullscreen, for: c)
        try desk.setState(.absent, for: w)
        let key = DeskKey(displayUUID: "D1", spaceID: nil)
        let world = try World(ids: ids, desks: [key: desk])
        let data = try world.encoded()
        let decoded = try World.decode(from: data)
        #expect(decoded == world)
        #expect(decoded[key]?.tree.state(of: b) == .absent)
        #expect(decoded[key]?.tree.state(of: c) == .fullscreen)
        #expect(decoded[key]?.desktop.windows.first?.state == .absent)
        #expect(!String(decoding: data, as: UTF8.self).contains("closed"))
    }
}

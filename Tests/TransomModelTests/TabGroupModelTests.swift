import Foundation
import Testing
@testable import TransomModel

private let a = makeWindow(1)
private let b = makeWindow(2)
private let c = makeWindow(3)
private let d = makeWindow(4)

private func n(_ raw: UInt64) -> NodeID { NodeID(raw: raw) }

private let area = Rect(x: 0, y: 0, width: 1000, height: 500)

/// H[tabs(A, B) at node 2, C at node 3], the group's members present unless `states` says otherwise.
private func groupBesideC(selected: Int = 1, states overrides: [WindowRef: WindowState] = [:]) throws -> LayoutTree {
    var states = [a.identity: WindowState.present, b.identity: .present, c.identity: .present]
    for (window, state) in overrides { states[window.identity] = state }
    return try LayoutTree(
        root: n(1),
        nodes: [n(1): .split(axis: .horizontal, children: [n(2), n(3)], weights: [0.5, 0.5]), n(2): .tabs(windows: [a, b], selected: selected), n(3): .panel(c)],
        states: states)
}

/// D-04, D-07, Pitfall 2: a tab group writes exactly one member into its tile, under the 32 pt band.
@Suite struct TabGroupModelTests {
    @Test func theBandGeometryRoundTrips() {
        let frame = Rect(x: 10, y: 20, width: 300, height: 200)
        #expect(TabBand.content(of: frame) == Rect(x: 10, y: 52, width: 300, height: 168))
        #expect(TabBand.frame(ofContent: TabBand.content(of: frame)) == frame)
        #expect(TabBand.strip(of: frame) == Rect(x: 10, y: 20, width: 300, height: 28))
        #expect(TabBand.content(of: Rect(x: 0, y: 0, width: 50, height: 20)).height == 0, "the content height is not floored at 0")
    }

    @Test func aTwoMemberGroupResolvesOneWindowRectAndOneHiddenTab() throws {
        let resolution = try resolve(try groupBesideC(), in: area, mins: [:], gap: 10)
        let tile = try #require(resolution.nodeRects[n(2)])
        #expect(tile == Rect(x: 10, y: 10, width: 485, height: 480))
        let content = TabBand.content(of: tile)
        #expect(content == Rect(x: 10, y: 42, width: 485, height: 448), "the content rect is not the tile minus 32 pt at the top")
        #expect(resolution.windowRects[b] == content, "the selected member is not in the content rect")
        #expect(resolution.windowRects[a] == nil, "the hidden member was written into the tile")
        #expect(resolution.hiddenTabs == [a: content])
        #expect(Set(resolution.windowRects.keys) == [b, c])
    }

    @Test func theGroupMinimumIsTheLargestMemberMinimumPlusTheBand() throws {
        // The hidden member's minimum counts too: whichever is selected must fit.
        let mins = [a: Size(width: 200, height: 460), b: Size(width: 100, height: 100)]
        let fits = try resolve(try groupBesideC(), in: Rect(x: 0, y: 0, width: 1000, height: 512), mins: mins, gap: 10)
        #expect(fits.unfit.isEmpty, "460 + 32 fits a 492 pt tall tile")
        let tight = try resolve(try groupBesideC(), in: Rect(x: 0, y: 0, width: 1000, height: 511), mins: mins, gap: 10)
        #expect(tight.unfit == [b], "the group fit without room for its band")
        #expect(tight.nodeRects[n(2)] == nil)
        #expect(tight.hiddenTabs.isEmpty, "a group that does not take part parked its hidden member")
    }

    @Test func theGroupTakesNoPartWhileItsSelectedMemberIsAbsent() throws {
        let resolution = try resolve(try groupBesideC(states: [b: .absent]), in: area, mins: [:], gap: 10)
        #expect(resolution.nodeRects[n(2)] == nil)
        #expect(resolution.windowRects == [c: Rect(x: 10, y: 10, width: 980, height: 480)])
        #expect(resolution.hiddenTabs.isEmpty)
        #expect(resolution.unfit.isEmpty)
    }

    @Test func noTwoWindowRectsOverlapWithAGroupInAThreeTileTree() throws {
        var tree = LayoutTree()
        var ids = IDSource()
        try tree.insertRoot(a, ids: &ids)
        try tree.insert(c, at: .right, of: n(1), ids: &ids)
        try tree.insert(d, at: .bottom, of: try #require(tree.leaf(containing: c)), ids: &ids)
        try tree.group(b, into: n(1))
        let resolution = try resolve(tree, in: area, mins: [:], gap: 8)
        let rects = Array(resolution.windowRects.values)
        #expect(rects.count == 3, "a group wrote more than one member: \(resolution.windowRects)")
        for (i, l) in rects.enumerated() {
            for r in rects[(i + 1)...] { #expect(!l.overlaps(r), "\(l) overlaps \(r)") }
        }
        #expect(resolution.hiddenTabs.keys.sorted { $0.identity < $1.identity } == [a])
    }
}

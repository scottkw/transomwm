import Foundation
import Testing
@testable import TransomModel

private let a = makeWindow(1)
private let b = makeWindow(2)
private let c = makeWindow(3)

private func n(_ raw: UInt64) -> NodeID { NodeID(raw: raw) }

/// A validated tree from raw-ID nodes. Every window is present unless `states` says otherwise.
private func tree(root: UInt64, _ nodes: [UInt64: Node], states overrides: [WindowRef: WindowState] = [:]) throws -> LayoutTree {
    var states: [WindowIdentity: WindowState] = [:]
    for node in nodes.values {
        switch node {
        case let .panel(window): states[window.identity] = .present
        case let .tabs(windows, _): for window in windows { states[window.identity] = .present }
        case .split: break
        }
    }
    for (window, state) in overrides { states[window.identity] = state }
    return try LayoutTree(root: n(root), nodes: Dictionary(uniqueKeysWithValues: nodes.map { (n($0.key), $0.value) }), states: states)
}

private func h(_ children: UInt64..., weights: [Double]) -> Node {
    .split(axis: .horizontal, children: children.map(n), weights: weights)
}

private func v(_ children: UInt64..., weights: [Double]) -> Node {
    .split(axis: .vertical, children: children.map(n), weights: weights)
}

private let wide = Rect(x: 0, y: 0, width: 1000, height: 500)
private let third = 1.0 / 3

@Suite struct ResolveTests {
    /// H[A, B] with A at node 2 and B at node 3.
    func pair(weights: [Double] = [0.5, 0.5]) throws -> LayoutTree {
        try tree(root: 1, [1: h(2, 3, weights: weights), 2: .panel(a), 3: .panel(b)])
    }

    @Test func emptyTreeResolvesToNothing() throws {
        #expect(try resolve(LayoutTree(), in: wide, mins: [a: Size(width: 10, height: 10)], gap: 10) == Resolution())
    }

    @Test func singleWindowFillsTheAreaInsetByTheGap() throws {
        let single = try tree(root: 1, [1: .panel(a)])
        let resolution = try resolve(single, in: wide, mins: [:], gap: 10)
        #expect(resolution.windowRects == [a: Rect(x: 10, y: 10, width: 980, height: 480)])
        #expect(resolution.nodeRects == [n(1): Rect(x: 10, y: 10, width: 980, height: 480)])
        #expect(resolution.unfit.isEmpty)
    }

    @Test func waterFillingPinsAChildBelowItsMinimumAndKeepsTheWeights() throws {
        let t = try pair()
        let resolution = try resolve(t, in: wide, mins: [a: Size(width: 700, height: 0)], gap: 0)
        #expect(resolution.windowRects[a] == Rect(x: 0, y: 0, width: 700, height: 500))
        #expect(resolution.windowRects[b] == Rect(x: 700, y: 0, width: 300, height: 500))
        #expect(t.node(n(1)) == h(2, 3, weights: [0.5, 0.5]))
    }

    @Test func exactFitPlacesBothAtTheirMinimum() throws {
        let mins = [a: Size(width: 485, height: 0), b: Size(width: 485, height: 0)]
        let resolution = try resolve(try pair(), in: wide, mins: mins, gap: 10)
        #expect(resolution.windowRects[a] == Rect(x: 10, y: 10, width: 485, height: 480))
        #expect(resolution.windowRects[b] == Rect(x: 505, y: 10, width: 485, height: 480))
        #expect(resolution.unfit.isEmpty)
    }

    @Test func onePointShortUnfitsTheLargerNodeIDAndTheOtherFills() throws {
        let mins = [a: Size(width: 485, height: 0), b: Size(width: 485, height: 0)]
        let resolution = try resolve(try pair(), in: Rect(x: 0, y: 0, width: 999, height: 500), mins: mins, gap: 10)
        #expect(resolution.unfit == [b])
        #expect(resolution.windowRects == [a: Rect(x: 10, y: 10, width: 979, height: 480)])
        #expect(resolution.nodeRects[n(3)] == nil)
    }

    @Test func heightIsTheBindingAxisInAVerticalSplit() throws {
        let t = try tree(root: 1, [1: v(2, 3, weights: [0.5, 0.5]), 2: .panel(a), 3: .panel(b)])
        let resolution = try resolve(t, in: Rect(x: 0, y: 0, width: 500, height: 800), mins: [a: Size(width: 0, height: 900)], gap: 0)
        #expect(resolution.unfit == [a])
        #expect(resolution.windowRects == [b: Rect(x: 0, y: 0, width: 500, height: 800)])
    }

    /// A (500, 400) has the largest area so it goes first; B (100, 600) still breaks the height and goes
    /// next. A fits again once B is gone, so maximality brings it back.
    @Test func readmitsAWindowThatFitsOnceALaterVictimLeaves() throws {
        let t = try tree(root: 1, [1: h(2, 3, 4, weights: [third, third, third]), 2: .panel(a), 3: .panel(b), 4: .panel(c)])
        let mins = [a: Size(width: 500, height: 400), b: Size(width: 100, height: 600), c: Size(width: 500, height: 10)]
        let resolution = try resolve(t, in: wide, mins: mins, gap: 0)
        #expect(resolution.unfit == [b])
        #expect(resolution.windowRects == [a: Rect(x: 0, y: 0, width: 500, height: 500), c: Rect(x: 500, y: 0, width: 500, height: 500)])
    }

    @Test func absentWindowKeepsItsSlotAndPresentAgainRestoresTheSameRects() throws {
        let nodes: [UInt64: Node] = [1: h(2, 3, 4, weights: [third, third, third]), 2: .panel(a), 3: .panel(b), 4: .panel(c)]
        let away = try tree(root: 1, nodes, states: [b: .absent])
        let resolution = try resolve(away, in: wide, mins: [:], gap: 10)
        #expect(resolution.windowRects == [a: Rect(x: 10, y: 10, width: 485, height: 480), c: Rect(x: 505, y: 10, width: 485, height: 480)])
        #expect(resolution.unfit.isEmpty)
        #expect(resolution.nodeRects[n(3)] == nil)
        #expect(away.leaf(containing: b) == n(3))

        let back = try tree(root: 1, nodes, states: [b: .present])
        #expect(try resolve(back, in: wide, mins: [:], gap: 10) == resolve(try tree(root: 1, nodes), in: wide, mins: [:], gap: 10))
    }

    @Test func fullscreenBehavesLikeAbsent() throws {
        let t = try tree(root: 1, [1: h(2, 3, weights: [0.5, 0.5]), 2: .panel(a), 3: .panel(b)], states: [a: .fullscreen])
        let resolution = try resolve(t, in: wide, mins: [a: Size(width: 5000, height: 5000)], gap: 10)
        #expect(resolution.windowRects == [b: Rect(x: 10, y: 10, width: 980, height: 480)])
        #expect(resolution.unfit.isEmpty)
    }

    @Test func tabGroupStaysPlacedWhileItsSelectedTabIsPresent() throws {
        let nodes: [UInt64: Node] = [1: h(2, 3, weights: [0.5, 0.5]), 2: .tabs(windows: [a, b], selected: 1), 3: .panel(c)]
        let one = try resolve(try tree(root: 1, nodes, states: [a: .absent]), in: wide, mins: [:], gap: 10)
        #expect(one.nodeRects[n(2)] == Rect(x: 10, y: 10, width: 485, height: 480))
        #expect(one.windowRects[b] == Rect(x: 10, y: 42, width: 485, height: 448), "the selected tab gets the content rect")
        #expect(one.windowRects[a] == nil)
        #expect(one.hiddenTabs.isEmpty, "an absent member is not parked")

        let none = try resolve(try tree(root: 1, nodes, states: [b: .absent]), in: wide, mins: [:], gap: 10)
        #expect(none.nodeRects[n(2)] == nil, "a group whose selected tab is absent took part")
        #expect(none.windowRects == [c: Rect(x: 10, y: 10, width: 980, height: 480)])
        #expect(none.hiddenTabs.isEmpty)
        #expect(none.unfit.isEmpty)
    }

    @Test func areaSmallerThanTwoGapsPlusOneUnfitsEveryPresentWindow() throws {
        let t = try tree(root: 1, [1: h(2, 3, weights: [0.5, 0.5]), 2: .panel(a), 3: .tabs(windows: [b, c], selected: 0)], states: [c: .absent])
        let resolution = try resolve(t, in: Rect(x: 0, y: 0, width: 15, height: 15), mins: [:], gap: 10)
        #expect(resolution.unfit == [a, b])
        #expect(resolution.windowRects.isEmpty)
        #expect(resolution.nodeRects.isEmpty)
    }

    @Test func touchingTilesShareAnEdgeAndDoNotOverlap() throws {
        let rects = try resolve(try pair(), in: wide, mins: [:], gap: 0).windowRects
        let left = try #require(rects[a])
        let right = try #require(rects[b])
        #expect(left.maxX == right.minX)
        #expect(!left.overlaps(right))
    }

    @Test func fractionalAreaSnapsInwardBeforeTheGap() throws {
        let single = try tree(root: 1, [1: .panel(a)])
        let area = Rect(x: 0.4, y: 0.6, width: 999.7, height: 500.2)
        #expect(try resolve(single, in: area, mins: [:], gap: 0).windowRects[a] == Rect(x: 1, y: 1, width: 999, height: 499))
        #expect(try resolve(single, in: area, mins: [:], gap: 9.6).windowRects[a] == Rect(x: 11, y: 11, width: 979, height: 479))
    }

    @Test func unequalWeightsSplitTheLengthProportionally() throws {
        let r = try resolve(try pair(weights: [0.3, 0.7]), in: wide, mins: [:], gap: 0)
        #expect(r.windowRects[a] == Rect(x: 0, y: 0, width: 300, height: 500))
        #expect(r.windowRects[b] == Rect(x: 300, y: 0, width: 700, height: 500))

        let column = try tree(root: 1, [1: v(2, 3, weights: [0.8, 0.2]), 2: .panel(a), 3: .panel(b)])
        let rv = try resolve(column, in: wide, mins: [:], gap: 10)
        #expect(rv.windowRects[a] == Rect(x: 10, y: 10, width: 980, height: 376))
        #expect(rv.windowRects[b] == Rect(x: 10, y: 396, width: 980, height: 94))
    }

    @Test func resolveIsDeterministicAndLaysChildrenOutInOrder() throws {
        let t = try tree(root: 1, [1: v(2, 3, weights: [0.3, 0.7]), 2: .panel(a), 3: h(4, 5, weights: [0.6, 0.4]), 4: .panel(b), 5: .panel(c)])
        let first = try resolve(t, in: wide, mins: [c: Size(width: 300, height: 200)], gap: 10)
        #expect(try resolve(t, in: wide, mins: [c: Size(width: 300, height: 200)], gap: 10) == first)
        let top = try #require(first.windowRects[a])
        let left = try #require(first.windowRects[b])
        let right = try #require(first.windowRects[c])
        #expect(top.maxY + 10 == left.minY)
        #expect(left.maxX + 10 == right.minX)
        #expect(left.minY == right.minY)
    }

    @Test(arguments: [
        Rect(x: .nan, y: 0, width: 100, height: 100),
        Rect(x: 0, y: 0, width: -1, height: 100),
        Rect(x: 2_000_000, y: 0, width: 100, height: 100),
        Rect(x: 0, y: 0, width: .infinity, height: 100),
    ])
    func invalidAreaThrows(area: Rect) throws {
        #expect(throws: LayoutError.invalidGeometry("area")) { try resolve(try pair(), in: area, mins: [:], gap: 0) }
    }

    @Test(arguments: [-1, Double.nan, Double.infinity, 2_000_000])
    func invalidGapThrows(gap: Double) throws {
        #expect(throws: LayoutError.invalidGap) { try resolve(try pair(), in: wide, mins: [:], gap: gap) }
    }

    @Test(arguments: [Size(width: -1, height: 10), Size(width: .nan, height: 10), Size(width: 10, height: .infinity)])
    func invalidMinimumThrows(min: Size) throws {
        #expect(throws: LayoutError.invalidMinimum(b)) { try resolve(try pair(), in: wide, mins: [b: min], gap: 0) }
    }

    @Test func minimumsForWindowsOutsideTheTreeAreIgnored() throws {
        let resolution = try resolve(try pair(), in: wide, mins: [makeWindow(99): Size(width: 5000, height: 5000)], gap: 0)
        #expect(resolution.unfit.isEmpty)
        #expect(resolution.windowRects.count == 2)
    }
}

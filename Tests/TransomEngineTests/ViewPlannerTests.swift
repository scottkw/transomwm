import TransomEngine
import TransomModel
import Testing

private let area = Rect(x: 0, y: 25, width: 1440, height: 875)
/// The area less resolve's 8 pt outer gap.
private let inner = Rect(x: 8, y: 33, width: 1424, height: 859)

private func ref(_ id: UInt32) -> WindowRef {
    WindowRef(identity: WindowIdentity(windowID: id, pid: 710, bundleID: "com.example.view"))
}

private let a = ref(1), b = ref(2), c = ref(3), f = ref(4)

/// H[a, V[b, c]], plus the given floating windows.
private func threeDocked(floating: [(WindowRef, Rect)] = []) throws -> Desk {
    var desk = Desk()
    var ids = IDSource()
    try desk.tree.applyDrop(.layoutEdge(.right), window: a, ids: &ids)
    try desk.tree.insert(b, at: .right, of: try #require(desk.tree.leaf(containing: a)), ids: &ids)
    try desk.tree.insert(c, at: .bottom, of: try #require(desk.tree.leaf(containing: b)), ids: &ids)
    for (window, frame) in floating { try desk.desktop.add(window, frame: frame) }
    return desk
}

/// H[a, b], nothing floating.
private func twoDocked() throws -> Desk {
    var desk = Desk()
    var ids = IDSource()
    try desk.tree.applyDrop(.layoutEdge(.right), window: a, ids: &ids)
    try desk.tree.applyDrop(.layoutEdge(.right), window: b, ids: &ids)
    return desk
}

private func split(of window: WindowRef, in desk: Desk) throws -> NodeID {
    let leaf = try #require(desk.tree.leaf(containing: window))
    return try #require(desk.tree.parent(of: leaf))
}

@Suite struct SubtreeTests {
    @Test func theSubtreeOfASplitKeepsExactlyItsDescendantsAndTheirStates() throws {
        var desk = try threeDocked()
        try desk.tree.setState(.absent, for: c)
        let id = try split(of: b, in: desk)

        let subtree = try desk.tree.subtree(at: id)

        #expect(subtree.root == id)
        let leafB = try #require(desk.tree.leaf(containing: b)), leafC = try #require(desk.tree.leaf(containing: c))
        #expect(Set(subtree.nodes.keys) == [id, leafB, leafC])
        #expect(subtree.states == [b.identity: .present, c.identity: .absent])
        #expect(subtree.nodes[id] == desk.tree.nodes[id])
    }

    @Test func theSubtreeAtALeafIsAValidLeafRootedTree() throws {
        let tree = try threeDocked().tree
        let leaf = try #require(tree.leaf(containing: a))

        let subtree = try tree.subtree(at: leaf)

        #expect(subtree.root == leaf)
        #expect(subtree.nodes == [leaf: .panel(a)])
        #expect(subtree.states == [a.identity: .present])
        try subtree.validate()
    }

    @Test func aMissingNodeThrows() throws {
        let missing = NodeID(raw: 9_999)
        #expect(throws: LayoutError.nodeNotFound(missing)) { try threeDocked().tree.subtree(at: missing) }
    }
}

/// D-A, ZOOM-01, ZOOM-13: views resolve a subtree at the whole area; with zoom on, unfit collapsible windows collapse.
@Suite struct ViewPlannerTests {
    @Test func homeViewEqualsThePhase3Plan() throws {
        let desks = [
            try threeDocked(),
            try threeDocked(floating: [(f, Rect(x: 1200, y: 100, width: 300, height: 200))]),
            try threeDocked(floating: [(f, Rect(x: 20, y: 100, width: 300, height: 200))]),
        ]
        for desk in desks {
            let phase3 = try Planner.plan(desk: desk, area: area, gap: 8, mins: [:])
            let view = try ViewPlanner.plan(desk: desk, view: .home, area: area, gap: 8, mins: [:])
            #expect(view.frames == phase3.frames)
            #expect(view.parks == phase3.parks)
            #expect(view.unfit == phase3.unfit)
            #expect(view.desktopRect == phase3.desktopRect)
            #expect(view.resolution == phase3.resolution && view.homeResolution == phase3.resolution)
            #expect(view.collapsed.isEmpty)
        }
    }

    @Test func aNodeViewFillsTheAreaAndParksTheRest() throws {
        let desk = try threeDocked()
        let home = try Planner.plan(desk: desk, area: area, gap: 8, mins: [:])

        let plan = try ViewPlanner.plan(desk: desk, view: .node(try split(of: b, in: desk)), area: area, gap: 8, mins: [:])

        #expect(Set(plan.frames.keys) == [b, c])
        let top = try #require(plan.frames[b]), bottom = try #require(plan.frames[c])
        #expect(top.minX == inner.minX && top.width == inner.width && top.minY == inner.minY)
        #expect(bottom.width == inner.width && bottom.maxY == inner.maxY && bottom.minY == top.maxY + 8)
        #expect(plan.parks == [a])
        #expect(plan.desktopRect == nil)
        #expect(plan.homeResolution == home.resolution)
    }

    /// D-14: a node view parks only the docked windows outside it; floaters get no frame and no park, in any view.
    @Test func floatersStayOnScreenInANodeView() throws {
        let g = ref(5)
        let desk = try threeDocked(floating: [(g, Rect(x: 1200, y: 400, width: 200, height: 150)), (f, Rect(x: 200, y: 100, width: 300, height: 200))])

        let leafA = try ViewPlanner.plan(desk: desk, view: .node(try #require(desk.tree.leaf(containing: a))), area: area, gap: 8, mins: [:])
        #expect(leafA.frames == [a: inner])
        #expect(leafA.parks == [b, c], "parks are sorted by identity")

        let split = try ViewPlanner.plan(desk: desk, view: .node(try split(of: b, in: desk)), area: area, gap: 8, mins: [:])
        #expect(Set(split.frames.keys) == [b, c])
        #expect(split.parks == [a])
    }

    /// a's 1000 pt minimum cannot sit beside b's 800 pt one: a collapses into what b leaves, b keeps its minimum.
    @Test func aCollapsibleWindowThatDoesNotFitGetsItsShareAndIsParked() throws {
        let desk = try twoDocked()
        let mins = [a: Size(width: 1000, height: 100), b: Size(width: 800, height: 100)]
        #expect(try Planner.plan(desk: desk, area: area, gap: 8, mins: mins).unfit == [a])

        let plan = try ViewPlanner.plan(desk: desk, view: .home, area: area, gap: 8, mins: mins, collapsible: [a.identity])

        let block = try #require(plan.collapsed[a])
        let second = try resolve(desk.tree, in: area, mins: [a: Size(width: 1, height: 1), b: mins[b]!], gap: 8)
        #expect(block == second.windowRects[a])
        // The 1424 pt inner width, less the 8 pt gap and b's 800: a gets the 616 pt left.
        #expect(block.minX == inner.minX && block.width == 616 && block.height == inner.height)
        #expect(plan.parks == [a])
        #expect(plan.frames[a] == nil)
        #expect(plan.frames[b]?.width == 800)
        #expect(plan.unfit.isEmpty)
    }

    /// A 20 pt wide area has 4 pt inside its outer gaps: room for one 1 pt tile, not two with a gap: b (the larger leaf) is
    /// hidden collapsed.
    @Test func aCollapsibleWindowStillUnfitAt1x1IsHiddenCollapsed() throws {
        let desk = try twoDocked()
        let narrow = Rect(x: 0, y: 0, width: 20, height: 200)
        let mins = [a: Size(width: 100, height: 1), b: Size(width: 100, height: 1)]

        let plan = try ViewPlanner.plan(desk: desk, view: .home, area: narrow, gap: 8, mins: mins, collapsible: [a.identity, b.identity])

        #expect(plan.parks == [a, b])
        #expect(plan.collapsed[b] == nil)
        #expect(plan.collapsed[a] != nil)
        #expect(plan.frames[a] == nil && plan.frames[b] == nil)
        #expect(plan.unfit.isEmpty)
    }

    @Test func unfitWindowsOutsideTheSetStayUnfit() throws {
        let desk = try twoDocked()
        let mins = [a: Size(width: 1000, height: 100), b: Size(width: 500, height: 100)]

        let plan = try ViewPlanner.plan(desk: desk, view: .home, area: area, gap: 8, mins: mins, collapsible: [b.identity])

        #expect(plan.unfit == [a])
        #expect(plan.collapsed.isEmpty)
        #expect(plan.parks.isEmpty)
    }

    /// a and b share 1416 pt: 708 each, exactly their minimums.
    @Test func aTileExactlyAtTheMinimumIsNotCollapsed() throws {
        let desk = try twoDocked()
        let mins = [a: Size(width: 708, height: inner.height), b: Size(width: 708, height: inner.height)]

        let plan = try ViewPlanner.plan(desk: desk, view: .home, area: area, gap: 8, mins: mins, collapsible: [a.identity])

        #expect(plan.collapsed.isEmpty)
        #expect(plan.parks.isEmpty)
        #expect(plan.frames[a] == Rect(x: inner.minX, y: inner.minY, width: 708, height: inner.height))
    }

    @Test func onePointSmallerIsCollapsed() throws {
        let desk = try twoDocked()
        for minimum in [Size(width: 709, height: inner.height), Size(width: 708, height: inner.height + 1)] {
            let mins = [a: minimum, b: Size(width: 708, height: inner.height)]

            let plan = try ViewPlanner.plan(desk: desk, view: .home, area: area, gap: 8, mins: mins, collapsible: [a.identity])

            #expect(plan.collapsed[a] == Rect(x: inner.minX, y: inner.minY, width: 708, height: inner.height), "minimum \(minimum)")
            #expect(plan.parks == [a])
            #expect(plan.frames[b] == Rect(x: inner.minX + 716, y: inner.minY, width: 708, height: inner.height))
        }
    }

    @Test func collapseIsDeterministic() throws {
        let desk = try threeDocked()
        let mins = [a: Size(width: 1000, height: 100), b: Size(width: 500, height: 100), c: Size(width: 600, height: 500)]
        let collapsible: Set = [a.identity, b.identity, c.identity]

        let first = try ViewPlanner.plan(desk: desk, view: .home, area: area, gap: 8, mins: mins, collapsible: collapsible)
        let second = try ViewPlanner.plan(desk: desk, view: .home, area: area, gap: 8, mins: mins, collapsible: collapsible)

        #expect(first == second)
        #expect(!first.collapsed.isEmpty)
    }
}

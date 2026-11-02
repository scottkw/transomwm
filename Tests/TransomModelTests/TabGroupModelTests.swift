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

private let floatA = Rect(x: 100, y: 100, width: 400, height: 300)
private let floatC = Rect(x: 600, y: 120, width: 300, height: 200)

/// The assumption-delta invariant (07-04): every member's stored frame is its group's content rect, and every member
/// floats exactly once.
private func expectGroupInvariant(_ layer: DesktopLayer, sourceLocation: SourceLocation = #_sourceLocation) {
    for group in layer.groups {
        for member in group.members {
            #expect(layer.windows.filter { $0.window == member }.count == 1, "\(member) does not float exactly once", sourceLocation: sourceLocation)
            #expect(layer.frame(of: member) == TabBand.content(of: group.frame), "\(member) is off its content rect", sourceLocation: sourceLocation)
        }
    }
    #expect((try? layer.validate()) != nil, "the layer does not validate", sourceLocation: sourceLocation)
}

/// a and c floating, b grouped onto a as group 5.
private func floatingGroup() throws -> DesktopLayer {
    var layer = DesktopLayer()
    try layer.add(a, frame: floatA)
    try layer.add(c, frame: floatC)
    try layer.group(id: n(5), target: a, adding: b)
    return layer
}

private func decodeLayer(_ json: String) throws -> DesktopLayer {
    try JSONDecoder().decode(DesktopLayer.self, from: Data(json.utf8))
}

/// D-02, D-13, TABS-05: floating groups as a sidecar on the Desktop layer.
@Suite struct FloatingTabGroupModelTests {
    @Test func groupingTakesTheTargetsFrameWithTheAddedWindowSelected() throws {
        let layer = try floatingGroup()
        #expect(layer.groups == [FloatingTabGroup(id: n(5), members: [a, b], selected: 1, frame: floatA)])
        #expect(layer.windows.map(\.window) == [a, c, b], "the added window is not in front")
        #expect(layer.frame(of: a) == TabBand.content(of: floatA))
        #expect(layer.frame(of: c) == floatC, "a window outside the group moved")
        expectGroupInvariant(layer)
    }

    @Test func groupingAnAlreadyFloatingWindowKeepsItOnce() throws {
        var layer = DesktopLayer()
        try layer.add(a, frame: floatA)
        try layer.add(c, frame: floatC)
        try layer.group(id: n(5), target: a, adding: c)
        #expect(layer.windows.map(\.window) == [a, c])
        expectGroupInvariant(layer)
    }

    @Test func groupingRefusesBadInputAndChangesNothing() throws {
        let before = try floatingGroup()
        var layer = before
        #expect(throws: LayoutError.windowNotFound(d)) { try layer.group(id: n(6), target: d, adding: c) }
        #expect(throws: LayoutError.duplicateWindow(a)) { try layer.group(id: n(6), target: a, adding: c) }
        #expect(throws: LayoutError.duplicateWindow(b)) { try layer.group(id: n(6), target: c, adding: b) }
        #expect(throws: LayoutError.duplicateWindow(c)) { try layer.group(id: n(6), target: c, adding: c) }
        #expect(throws: LayoutError.self) { try layer.group(id: n(5), target: c, adding: d) }
        #expect(throws: LayoutError.notATabGroup(n(9))) { try layer.addTab(d, to: n(9)) }
        #expect(throws: LayoutError.duplicateWindow(a)) { try layer.addTab(a, to: n(5)) }
        #expect(throws: LayoutError.windowNotFound(c)) { try layer.selectTab(c) }
        #expect(layer == before)
    }

    @Test func addTabAppendsAndSelectsAtTheContentRect() throws {
        var layer = try floatingGroup()
        try layer.addTab(d, to: n(5))
        #expect(layer.groups[0].members == [a, b, d])
        #expect(layer.groups[0].selected == 2)
        expectGroupInvariant(layer)
        try layer.addTab(c, to: n(5))  // an already floating window joins too
        #expect(layer.groups[0].members == [a, b, d, c])
        expectGroupInvariant(layer)
    }

    @Test func selectTabChangesOnlyTheSelection() throws {
        var layer = try floatingGroup()
        let frames = layer.windows
        try layer.selectTab(a)
        #expect(layer.groups[0].selected == 0)
        #expect(layer.windows == frames)
        expectGroupInvariant(layer)
    }

    @Test func aMemberMovedMovesTheWholeGroup() throws {
        var layer = try floatingGroup()
        let content = Rect(x: 300, y: 400, width: 500, height: 250)
        try layer.setFrame(content, for: b)
        #expect(layer.groups[0].frame == TabBand.frame(ofContent: content))
        #expect(layer.frame(of: a) == content && layer.frame(of: b) == content)
        #expect(layer.frame(of: c) == floatC)
        expectGroupInvariant(layer)
    }

    @Test func removingDownToOneDissolvesWithTheSurvivorAtTheWholeFrame() throws {
        var layer = try floatingGroup()
        try layer.remove(b)
        #expect(layer.groups.isEmpty)
        #expect(layer.frame(of: a) == floatA, "the band did not return to the survivor")
        expectGroupInvariant(layer)
    }

    @Test func removingFromALargerGroupKeepsASelectionInRange() throws {
        var layer = try floatingGroup()
        try layer.addTab(d, to: n(5))
        try layer.remove(d)  // the selected last tab: the new last is selected
        #expect(layer.groups[0].members == [a, b] && layer.groups[0].selected == 1)
        try layer.addTab(d, to: n(5))
        try layer.remove(a)  // before the selection: it shifts down
        #expect(layer.groups[0].members == [b, d] && layer.groups[0].selected == 1)
        expectGroupInvariant(layer)
    }

    @Test func rekeyAndTitleStrippingRewriteMembers() throws {
        var layer = try floatingGroup()
        let renamed = makeWindow(20)
        try layer.rekey(from: b, to: renamed)
        #expect(layer.groups[0].members == [a, renamed])
        expectGroupInvariant(layer)
        let titled = makeWindow(1, title: "Doc")
        var titledLayer = DesktopLayer()
        try titledLayer.add(titled, frame: floatA)
        try titledLayer.group(id: n(5), target: titled, adding: b)
        titledLayer.mapWindows { WindowRef(identity: $0.identity) }
        #expect(titledLayer.groups[0].members.map(\.titleHint) == ["", ""])
    }

    @Test func theInvariantHoldsAfterEveryMutator() throws {
        var layer = try floatingGroup()
        expectGroupInvariant(layer)
        try layer.addTab(d, to: n(5)); expectGroupInvariant(layer)
        try layer.selectTab(a); expectGroupInvariant(layer)
        try layer.setFrame(Rect(x: 20, y: 60, width: 300, height: 300), for: d); expectGroupInvariant(layer)
        try layer.setState(.absent, for: b); expectGroupInvariant(layer)
        try layer.rekey(from: d, to: makeWindow(40)); expectGroupInvariant(layer)
        try layer.remove(a); expectGroupInvariant(layer)
        try layer.remove(b); expectGroupInvariant(layer)
        #expect(layer.groups.isEmpty)
    }

    @Test func aGroupRoundTripsThroughJSON() throws {
        let layer = try floatingGroup()
        let data = try JSONEncoder().encode(layer)
        #expect(String(decoding: data, as: UTF8.self).contains("\"groups\""))
        #expect(try JSONDecoder().decode(DesktopLayer.self, from: data) == layer)
    }

    @Test func aLayerWithoutGroupsWritesNoKeyAndOldFilesDecode() throws {
        var layer = DesktopLayer()
        try layer.add(a, frame: floatA)
        #expect(!String(decoding: try JSONEncoder().encode(layer), as: UTF8.self).contains("groups"))
        // Verbatim from Tests/TransomMacTests/LayoutFileV1Fixture.swift: a desk written before floating groups.
        let old = try decodeLayer("""
            {
              "windows" : [
                {
                  "frame" : {
                    "height" : 300,
                    "width" : 400,
                    "x" : 900,
                    "y" : 300
                  },
                  "state" : "present",
                  "window" : {
                    "creationOrder" : 0,
                    "identity" : {
                      "bundleID" : "com.example.editor",
                      "pid" : 300,
                      "windowID" : 2
                    },
                    "titleHint" : ""
                  }
                }
              ]
            }
            """)
        #expect(old.groups.isEmpty)
        #expect(old.windows.count == 1 && old.windows[0].frame == Rect(x: 900, y: 300, width: 400, height: 300))
    }

    @Test func validationRejectsHostileGroups() throws {
        let good = try floatingGroup()
        let content = TabBand.content(of: floatA)
        func layer(_ groups: [FloatingTabGroup], also extra: [WindowRef] = []) throws -> DesktopLayer {
            var json = try JSONSerialization.jsonObject(with: try JSONEncoder().encode(good)) as! [String: Any]
            let encoded = try JSONEncoder().encode(groups)
            json["groups"] = try JSONSerialization.jsonObject(with: encoded)
            var decoded = try JSONDecoder().decode(DesktopLayer.self, from: try JSONSerialization.data(withJSONObject: json))
            for window in extra { try decoded.add(window, frame: content) }
            return decoded
        }
        let cases: [(String, [FloatingTabGroup])] = [
            ("one member", [FloatingTabGroup(id: n(5), members: [a], selected: 0, frame: floatA)]),
            ("a member not floating", [FloatingTabGroup(id: n(5), members: [a, d], selected: 0, frame: floatA)]),
            ("a window in two groups", [
                FloatingTabGroup(id: n(5), members: [a, b], selected: 0, frame: floatA),
                FloatingTabGroup(id: n(6), members: [b, c], selected: 0, frame: floatA),
            ]),
            ("a window twice in one group", [FloatingTabGroup(id: n(5), members: [a, a], selected: 0, frame: floatA)]),
            ("selected out of range", [FloatingTabGroup(id: n(5), members: [a, b], selected: 2, frame: floatA)]),
            ("negative selected", [FloatingTabGroup(id: n(5), members: [a, b], selected: -1, frame: floatA)]),
            ("a non-finite frame", [FloatingTabGroup(id: n(5), members: [a, b], selected: 0, frame: Rect(x: 0, y: 0, width: 1_000_001, height: 10))]),
            ("duplicate IDs", [
                FloatingTabGroup(id: n(5), members: [a, b], selected: 0, frame: floatA),
                FloatingTabGroup(id: n(5), members: [c, d], selected: 0, frame: floatA),
            ]),
        ]
        for (name, groups) in cases {
            let hostile = try layer(groups, also: name == "duplicate IDs" ? [d] : [])
            #expect(throws: LayoutError.self, "\(name) validated") { try hostile.validate() }
        }
        var many = DesktopLayer()
        var groups: [FloatingTabGroup] = []
        for i in 0...LayoutTree.maxNodes {
            let first = makeWindow(UInt32(1000 + 2 * i)), second = makeWindow(UInt32(1001 + 2 * i))
            try many.add(first, frame: floatA)
            try many.add(second, frame: floatA)
            groups.append(FloatingTabGroup(id: n(UInt64(10 + i)), members: [first, second], selected: 0, frame: floatA))
        }
        var json = try JSONSerialization.jsonObject(with: try JSONEncoder().encode(many)) as! [String: Any]
        json["groups"] = try JSONSerialization.jsonObject(with: try JSONEncoder().encode(groups))
        let tooMany = try JSONDecoder().decode(DesktopLayer.self, from: try JSONSerialization.data(withJSONObject: json))
        #expect(throws: LayoutError.tooManyNodes(limit: LayoutTree.maxNodes)) { try tooMany.validate() }
    }

    @Test func worldValidationRejectsGroupIDsOutsideTheSourceOrOnTheTree() throws {
        let key = DeskKey(displayUUID: "D1", spaceID: nil)
        var ids = IDSource()
        var desk = Desk()
        try desk.tree.insert(d, at: .left, of: .desktop, ids: &ids)  // the tree takes node 1
        try desk.desktop.add(a, frame: floatA)
        try desk.desktop.group(id: n(1), target: a, adding: b)
        #expect(throws: LayoutError.self, "a group ID equal to a tree node validated") {
            _ = try World(ids: IDSource(next: 10), desks: [key: desk])
        }
        var high = Desk()
        try high.desktop.add(a, frame: floatA)
        try high.desktop.group(id: n(10), target: a, adding: b)
        #expect(throws: LayoutError.self, "a group ID at the source's next value validated") {
            _ = try World(ids: IDSource(next: 10), desks: [key: high])
        }
        let ok = try World(ids: IDSource(next: 11), desks: [key: high])
        #expect(try World.decode(from: try ok.encoded()) == ok)
    }

    @Test func undoOfAGroupingBringsTheTargetBackToItsOwnFrame() throws {
        let key = DeskKey(displayUUID: "D1", spaceID: nil)
        var world = World()
        var history = UndoHistory()
        try world.addDesk(key)
        try world.reflow(key) { desk, _ throws(LayoutError) in
            try desk.desktop.add(a, frame: floatA)
            try desk.desktop.add(c, frame: floatC)
        }
        try world.edit(key, history: &history) { desk, ids throws(LayoutError) in
            try desk.desktop.remove(c)
            try desk.desktop.group(id: try ids.make(), target: a, adding: c)
        }
        // The user moves the group: an OS fact, which the undo of the grouping still reverts with it.
        try world.recordFloatingFrame(Rect(x: 50, y: 300, width: 400, height: 268), for: c)
        try world.undo(key, history: &history)
        let layer = try #require(world[key]?.desktop)
        #expect(layer.groups.isEmpty)
        #expect(layer.frame(of: a) == floatA)
        #expect(layer.frame(of: c) == floatC)
    }
}

/// Pattern 9: a group moves as one leaf (Float / Dock Group, whole-group drags).
@Suite struct WholeGroupEditTests {
    @Test func removingAndReinsertingATabsLeafKeepsMembersOrderAndSelection() throws {
        var tree = try groupBesideC(selected: 0, states: [a: .absent])
        var ids = IDSource(next: 4)
        let removed = try tree.removeLeaf(n(2))
        #expect(removed.node == .tabs(windows: [a, b], selected: 0))
        #expect(removed.states == [a.identity: .absent, b.identity: .present])
        #expect(tree.root == n(3) && tree.windows == [c], "the split did not collapse onto c")
        try tree.insertLeaf(removed.node, states: removed.states, at: .bottom, of: n(3), ids: &ids)
        let leaf = try #require(tree.leaf(containing: a))
        #expect(tree.node(leaf) == .tabs(windows: [a, b], selected: 0))
        #expect(tree.state(of: a) == .absent && tree.state(of: b) == .present)
        guard case .split(_, _, let weights)? = tree.node(try #require(tree.root)) else { Issue.record("no split root"); return }
        #expect(abs(weights.reduce(0, +) - 1) < 1e-12)
        try tree.validate()
    }

    @Test func aDuplicateMemberIdentityThrowsAndChangesNothing() throws {
        var tree = try groupBesideC()
        var ids = IDSource(next: 4)
        let before = tree, beforeIDs = ids
        #expect(throws: LayoutError.duplicateWindow(c)) {
            try tree.insertLeaf(.tabs(windows: [d, c], selected: 0), states: [d.identity: .present, c.identity: .present], at: .left, of: n(3), ids: &ids)
        }
        #expect(tree == before && ids == beforeIDs)
        #expect(throws: LayoutError.self, "states not matching the members inserted") {
            try tree.insertLeaf(.tabs(windows: [d, makeWindow(9)], selected: 0), states: [d.identity: .present], at: .left, of: n(3), ids: &ids)
        }
        #expect(tree == before && ids == beforeIDs)
    }

    @Test func theLastDockedLeafLeavingShowsAHiddenDesktop() throws {
        var tree = LayoutTree.withDesktop()
        var ids = IDSource()
        try tree.insert(a, at: .left, of: .desktop, ids: &ids)
        try tree.group(b, into: try #require(tree.leaf(containing: a)))
        try tree.setDesktopHidden(true)
        _ = try tree.removeLeaf(try #require(tree.leaf(containing: a)))
        #expect(tree.windows.isEmpty && tree.isDesktopHidden == false)
    }

    @Test func removeGroupAndAddGroupRoundTrip() throws {
        var layer = DesktopLayer()
        try layer.add(a, frame: floatA)
        try layer.add(c, frame: floatC)
        try layer.group(id: n(5), target: a, adding: b)
        try layer.setState(.absent, for: a)
        let before = layer
        let (group, states) = try layer.removeGroup(n(5))
        #expect(group == FloatingTabGroup(id: n(5), members: [a, b], selected: 1, frame: floatA))
        #expect(states == [a.identity: .absent, b.identity: .present])
        #expect(layer.groups.isEmpty && layer.windows.map(\.window) == [c])
        try layer.addGroup(group, states: states)
        #expect(layer.groups == before.groups)
        #expect(layer.frame(of: a) == TabBand.content(of: floatA) && layer.frame(of: b) == TabBand.content(of: floatA))
        #expect(layer.windows.first { $0.window == a }?.state == .absent)
        try layer.validate()
        #expect(throws: LayoutError.self) { try layer.addGroup(group, states: states) }
        #expect(throws: LayoutError.notATabGroup(n(9))) { _ = try layer.removeGroup(n(9)) }
    }

    @Test func aTabsLeafSwapsWithAPanelButTwoGroupsDoNot() throws {
        var tree = try groupBesideC()
        try tree.swap(b, c)
        #expect(tree.node(n(2)) == .panel(c) && tree.node(n(3)) == .tabs(windows: [a, b], selected: 1))
        var two = try groupBesideC()
        try two.group(d, into: n(3))
        let before = two
        #expect(throws: LayoutError.self) { try two.swap(a, d) }
        #expect(two == before)
    }
}

import PaneEngine
import PaneModel
import Testing

private let pid: Int32 = 500
private let bundleID = "com.example.tabs"
private let frame = Rect(x: 100, y: 100, width: 600, height: 400)

private func identity(_ id: UInt32) -> WindowIdentity {
    WindowIdentity(windowID: id, pid: pid, bundleID: bundleID)
}

private func cg(_ id: UInt32, _ bounds: Rect = frame, onScreen: Bool = false, layer: Int = 0, pid: Int32 = pid) -> CGWindowEntry {
    CGWindowEntry(windowID: id, pid: pid, bounds: bounds, layer: layer, onScreen: onScreen, alpha: 1)
}

private func visible(_ id: UInt32, _ tabCount: Int, _ bounds: Rect = frame) -> (id: UInt32, frame: Rect, tabCount: Int) {
    (id: id, frame: bounds, tabCount: tabCount)
}

/// A tracker that has seen visible 10 with tabCount 3 and hidden siblings 11 and 12.
private func threeTabs() -> (TabGroupTracker, TabResolution) {
    var tracker = TabGroupTracker()
    let resolution = tracker.update(pid: pid, bundleID: bundleID, visible: [visible(10, 3)], cgWindows: [cg(10, onScreen: true), cg(11), cg(12)])
    return (tracker, resolution)
}

@Suite struct TabGroupTrackerTests {
    @Test func aVisibleTabAndItsHiddenSiblingsFormOneGroupLedByTheVisibleTab() {
        let (tracker, resolution) = threeTabs()
        #expect(resolution.groupFor == [10: identity(10)])
        #expect(resolution.memberIDs == [10, 11, 12])
        #expect(resolution.tabCount == [identity(10): 3])
        #expect(tracker.isKnownMember(11, pid: pid))
    }

    @Test func switchingTabsRebindsTheVisibleTabToTheSameLeader() {
        var (tracker, _) = threeTabs()
        let resolution = tracker.update(pid: pid, bundleID: bundleID, visible: [visible(11, 3)], cgWindows: [cg(10), cg(11, onScreen: true), cg(12)])
        #expect(resolution.groupFor == [11: identity(10)])
        #expect(resolution.memberIDs == [10, 11, 12])
        #expect(resolution.tabCount == [identity(10): 3])
    }

    @Test(arguments: [(1.0, true), (1.01, false)])
    func aSiblingIsAMemberOnlyWithinOnePointOnEverySide(offset: Double, member: Bool) {
        var tracker = TabGroupTracker()
        let shifted = Rect(x: frame.x + offset, y: frame.y, width: frame.width, height: frame.height)
        let resolution = tracker.update(pid: pid, bundleID: bundleID, visible: [visible(10, 2)], cgWindows: [cg(10, onScreen: true), cg(11, shifted)])
        #expect(resolution.memberIDs.contains(11) == member)
        #expect(tracker.isKnownMember(11, pid: pid) == member)
    }

    @Test(arguments: [(1, false), (2, true)])
    func onlyTwoOrMoreTabsMakeAGroup(tabCount: Int, grouped: Bool) {
        var tracker = TabGroupTracker()
        let resolution = tracker.update(pid: pid, bundleID: bundleID, visible: [visible(10, tabCount)], cgWindows: [cg(10, onScreen: true), cg(11)])
        #expect((resolution.groupFor[10] != nil) == grouped)
        #expect(resolution.memberIDs == (grouped ? [10, 11] : []))
    }

    @Test(arguments: [cg(11, onScreen: true), cg(11, layer: 3), cg(11, pid: pid + 1)])
    func onscreenOtherLayerOrOtherPIDWindowsAreNeverMembers(entry: CGWindowEntry) {
        var tracker = TabGroupTracker()
        let resolution = tracker.update(pid: pid, bundleID: bundleID, visible: [visible(10, 2)], cgWindows: [cg(10, onScreen: true), entry])
        #expect(resolution.memberIDs == [10])
        #expect(!tracker.isKnownMember(11, pid: pid))
    }

    @Test func aClosedLeaderLeavesTheGroupItsIdentity() {
        var (tracker, _) = threeTabs()
        _ = tracker.update(pid: pid, bundleID: bundleID, visible: [visible(11, 3)], cgWindows: [cg(10), cg(11, onScreen: true), cg(12)])
        tracker.memberClosed(10, pid: pid)
        #expect(!tracker.isKnownMember(10, pid: pid))
        #expect(tracker.isKnownMember(11, pid: pid))
        #expect(tracker.isKnownMember(12, pid: pid))
        let resolution = tracker.update(pid: pid, bundleID: bundleID, visible: [visible(11, 2)], cgWindows: [cg(11, onScreen: true), cg(12)])
        #expect(resolution.groupFor == [11: identity(10)])
        #expect(resolution.memberIDs == [11, 12])
        #expect(resolution.tabCount == [identity(10): 2])
    }

    @Test func twoGroupsOfOneAppWithDifferentBoundsStaySeparate() {
        var tracker = TabGroupTracker()
        let other = Rect(x: 800, y: 100, width: 600, height: 400)
        let resolution = tracker.update(
            pid: pid, bundleID: bundleID, visible: [visible(10, 2), visible(20, 2, other)],
            cgWindows: [cg(10, onScreen: true), cg(11), cg(20, other, onScreen: true), cg(21, other)]
        )
        #expect(resolution.groupFor == [10: identity(10), 20: identity(20)])
        #expect(resolution.tabCount == [identity(10): 2, identity(20): 2])
        #expect(tracker.members(of: identity(10)) == [10, 11])
        #expect(tracker.members(of: identity(20)) == [20, 21])
    }

    @Test func aNewTabJoinsTheExistingGroup() {
        var (tracker, _) = threeTabs()
        let resolution = tracker.update(pid: pid, bundleID: bundleID, visible: [visible(13, 4)], cgWindows: [cg(10), cg(11), cg(12), cg(13, onScreen: true)])
        #expect(resolution.groupFor == [13: identity(10)])
        #expect(resolution.tabCount == [identity(10): 4])
    }

    @Test func aTabDraggedOutOfTheGroupIsNoLongerAMember() {
        var (tracker, _) = threeTabs()
        let away = Rect(x: 900, y: 300, width: 600, height: 400)
        let resolution = tracker.update(
            pid: pid, bundleID: bundleID, visible: [visible(10, 2), visible(11, 1, away)],
            cgWindows: [cg(10, onScreen: true), cg(11, away, onScreen: true), cg(12)]
        )
        #expect(resolution.groupFor == [10: identity(10)])
        #expect(resolution.memberIDs == [10, 12])
    }

    @Test func membersThatLeaveTheCGListLeaveTheGroupAndTheLastOneEndsIt() {
        var (tracker, _) = threeTabs()
        var resolution = tracker.update(pid: pid, bundleID: bundleID, visible: [], cgWindows: [cg(11)])
        #expect(resolution.memberIDs == [11])
        #expect(resolution.tabCount == [identity(10): 1])
        resolution = tracker.update(pid: pid, bundleID: bundleID, visible: [], cgWindows: [])
        #expect(resolution == TabResolution(groupFor: [:], memberIDs: [], tabCount: [:]))
        #expect(tracker.members(of: identity(10)).isEmpty)
    }

    @Test func aListedMinimizedTwinWithTheSameFrameIsNeverAHiddenTab() {
        for order in [[visible(20, 1), visible(10, 2)], [visible(10, 2), visible(20, 1)]] {
            var tracker = TabGroupTracker()
            let resolution = tracker.update(pid: pid, bundleID: bundleID, visible: order, cgWindows: [cg(10, onScreen: true), cg(11), cg(20)])
            #expect(resolution.groupFor == [10: identity(10)])
            #expect(resolution.memberIDs == [10, 11])
            #expect(resolution.tabCount == [identity(10): 2])
        }
    }

    @Test func aTrackedWindowOnAnotherSpaceWithTheSameFrameIsNeverAHiddenTab() {
        var tracker = TabGroupTracker()
        // 20 was tracked on another Space: unlisted and offscreen here, like a hidden tab, but not listed last refresh.
        let resolution = tracker.update(
            pid: pid, bundleID: bundleID, visible: [visible(10, 2)], cgWindows: [cg(10, onScreen: true), cg(11), cg(20)],
            tracked: [identity(20)]
        )
        #expect(resolution.memberIDs == [10, 11])
        #expect(resolution.tabCount == [identity(10): 2])
        #expect(resolution.folded.isEmpty)
    }

    @Test func aSameFrameGroupOnAnotherSpaceIsAGroupOfItsOwn() {
        var tracker = TabGroupTracker()
        _ = tracker.update(pid: pid, bundleID: bundleID, visible: [visible(10, 2)], cgWindows: [cg(10, onScreen: true), cg(11)])
        // Switched Space: 10 and 11 are offscreen in the same slot, but group 10 has no room under 30's AXTabs count.
        let resolution = tracker.update(
            pid: pid, bundleID: bundleID, visible: [visible(30, 2)], cgWindows: [cg(10), cg(11), cg(30, onScreen: true), cg(31)],
            tracked: [identity(10)]
        )
        #expect(resolution.groupFor == [30: identity(30)])
        #expect(tracker.members(of: identity(10)) == [10, 11])
        #expect(tracker.members(of: identity(30)) == [30, 31])
        #expect(resolution.folded.isEmpty)
    }

    @Test func aTrackedWindowListedLastRefreshThatGainsATabLeadsTheGroup() {
        var tracker = TabGroupTracker()
        _ = tracker.update(pid: pid, bundleID: bundleID, visible: [visible(10, 1)], cgWindows: [cg(10, onScreen: true)])
        let resolution = tracker.update(
            pid: pid, bundleID: bundleID, visible: [visible(11, 2)], cgWindows: [cg(10), cg(11, onScreen: true)], tracked: [identity(10)]
        )
        #expect(resolution.groupFor == [11: identity(10)])
        #expect(resolution.memberIDs == [10, 11])
        #expect(resolution.folded.isEmpty)
    }

    /// C2 with Space data: Cmd-T in A (10, Space 1) while an untracked same-frame twin Z sits on Space 2. The new tab
    /// takes A, which really became its hidden tab; ID order does not matter.
    @Test(arguments: [UInt32(5), 50])
    func cmdTTakesTheWindowThatBecameItsTabNotATwinOnAnotherSpace(twin: UInt32) {
        var tracker = TabGroupTracker()
        _ = tracker.update(
            pid: pid, bundleID: bundleID, visible: [visible(10, 1)], cgWindows: [cg(10, onScreen: true), cg(twin)],
            tracked: [identity(10)], spaces: [10: [1], twin: [2]]
        )
        // A hidden tab may report no Space.
        let resolution = tracker.update(
            pid: pid, bundleID: bundleID, visible: [visible(40, 2)], cgWindows: [cg(10), cg(twin), cg(40, onScreen: true)],
            tracked: [identity(10)], spaces: [40: [1], 10: [], twin: [2]]
        )
        #expect(resolution.groupFor == [40: identity(10)])
        #expect(tracker.members(of: identity(10)) == [10, 40])
        #expect(!resolution.memberIDs.contains(twin))
        #expect(resolution.folded.isEmpty)
    }

    /// The Cmd-T rule, with and without Space data: a shown tab that was not in the previous CG list takes the tracked
    /// standalone window listed last refresh, and leads a new group instead of joining a same-slot group with room.
    @Test(arguments: [false, true])
    func aBrandNewTabLeadsANewGroupWithTheStandaloneItCameFrom(spacesAvailable: Bool) {
        var tracker = TabGroupTracker()
        func spaces(_ map: [UInt32: Set<UInt64>]) -> [UInt32: Set<UInt64>]? { spacesAvailable ? map : nil }
        // Group T (30) on Space 2 with one unseen tab, so it has room; then A (10) is listed alone on Space 1.
        _ = tracker.update(pid: pid, bundleID: bundleID, visible: [visible(30, 2)], cgWindows: [cg(30, onScreen: true)], spaces: spaces([30: [2]]))
        _ = tracker.update(
            pid: pid, bundleID: bundleID, visible: [visible(10, 1)], cgWindows: [cg(10, onScreen: true), cg(30)],
            tracked: [identity(30), identity(10)], spaces: spaces([10: [1], 30: [2]])
        )
        let resolution = tracker.update(
            pid: pid, bundleID: bundleID, visible: [visible(40, 2)], cgWindows: [cg(5), cg(10), cg(30), cg(40, onScreen: true)],
            tracked: [identity(30), identity(10)], spaces: spaces([40: [1], 10: [], 30: [2], 5: []])
        )
        #expect(resolution.groupFor == [40: identity(10)])
        #expect(tracker.members(of: identity(10)) == [10, 40])
        #expect(tracker.members(of: identity(30)) == [30])
        #expect(resolution.folded.isEmpty)
    }

    /// S4 unchanged: a shown tab already in the previous CG list keeps today's ranking (untracked before standalone).
    @Test func aShownTabSeenBeforeKeepsTheUsualRanking() {
        var tracker = TabGroupTracker()
        _ = tracker.update(
            pid: pid, bundleID: bundleID, visible: [visible(10, 1)], cgWindows: [cg(10, onScreen: true), cg(30), cg(31)], tracked: [identity(10)]
        )
        let resolution = tracker.update(
            pid: pid, bundleID: bundleID, visible: [visible(30, 2)], cgWindows: [cg(10), cg(30, onScreen: true), cg(31)], tracked: [identity(10)]
        )
        #expect(resolution.groupFor == [30: identity(30)])
        #expect(tracker.members(of: identity(30)) == [30, 31])
        #expect(resolution.folded.isEmpty)
    }

    /// The ambiguity rule: hidden tabs may report no Space, so while a window known to be on another Space shares the
    /// frame slot, no candidate of unknown Space is taken, however many free slots the group has.
    @Test(arguments: [2, 3])
    func noUnknownSpaceCandidateIsTakenWhileAKnownOtherSpaceWindowSharesTheSlot(tabCount: Int) {
        var tracker = TabGroupTracker()
        var resolution = tracker.update(
            pid: pid, bundleID: bundleID, visible: [visible(30, tabCount)], cgWindows: [cg(10), cg(11), cg(30, onScreen: true), cg(31)],
            spaces: [30: [1], 31: [], 10: [2]]
        )
        #expect(resolution.groupFor == [30: identity(30)])
        #expect(tracker.members(of: identity(30)) == [30])
        #expect(resolution.tabCount == [identity(30): tabCount])
        // 10 left the CG list: nothing rules the unknown ones out any more, so the normal tiers take them.
        resolution = tracker.update(
            pid: pid, bundleID: bundleID, visible: [visible(30, tabCount)], cgWindows: [cg(11), cg(30, onScreen: true), cg(31)],
            spaces: [30: [1], 31: []]
        )
        #expect(tracker.members(of: identity(30)) == (tabCount == 3 ? [30, 31, 11] : [30, 11]))
        #expect(resolution.tabCount == [identity(30): tabCount])
    }

    /// Group G shows 30 on Space 1; its hidden tab 31 reports no Space while 10 (Space 2) shares the slot, so G knows
    /// no other member. Then 30 closes (or AX reports it invalid) and a window is listed: does it take G's identity?
    private func orphanHandoff(
        previous: CGWindowEntry = cg(31), listed: UInt32 = 31, listedSpace: Set<UInt64> = [1], tracked: [WindowIdentity] = [],
        shownGone: Bool = true
    ) -> TabResolution {
        var tracker = TabGroupTracker()
        let first = tracker.update(
            pid: pid, bundleID: bundleID, visible: [visible(30, 2)], cgWindows: [cg(10), cg(30, onScreen: true), previous],
            spaces: [30: [1], 10: [2], previous.windowID: []]
        )
        #expect(tracker.members(of: identity(30)) == [30])
        #expect(first.groupFor == [30: identity(30)])
        return tracker.update(
            pid: pid, bundleID: bundleID, visible: [visible(listed, 1)],
            cgWindows: [cg(10), cg(listed, onScreen: true)] + (shownGone ? [] : [cg(30)]),
            tracked: tracked + [identity(30)], spaces: [listed: listedSpace, 10: [2]], invalid: shownGone ? [] : [30]
        )
    }

    @Test(arguments: [true, false])
    func aFormerTabOfAGroupWithNoMemberLeftTakesItsIdentity(shownGone: Bool) {
        let resolution = orphanHandoff(shownGone: shownGone)
        #expect(resolution.groupFor == [31: identity(30)])
        #expect(resolution.tabCount[identity(30)] == 1)
    }

    @Test func aFormerTabExactlyOnePointOffStillTakesTheIdentity() {
        let shifted = Rect(x: frame.x + 1, y: frame.y, width: frame.width, height: frame.height)
        #expect(orphanHandoff(previous: cg(31, shifted)).groupFor == [31: identity(30)])
    }

    @Test(arguments: [
        ("absent from the previous CG list", cg(32), UInt32(31), Set<UInt64>([1]), false),
        ("onscreen in the previous CG list", cg(31, onScreen: true), 31, [1], false),
        ("on another Space", cg(31), 31, [3], false),
        ("already reported", cg(31), 31, [1], true),
        ("outside the slot", cg(31, Rect(x: frame.x + 1.01, y: frame.y, width: frame.width, height: frame.height)), 31, [1], false),
    ] as [(String, CGWindowEntry, UInt32, Set<UInt64>, Bool)])
    func aWindowWithoutFormerTabEvidenceNeverTakesTheIdentity(
        _ reason: String, previous: CGWindowEntry, listed: UInt32, listedSpace: Set<UInt64>, reported: Bool
    ) {
        let resolution = orphanHandoff(previous: previous, listed: listed, listedSpace: listedSpace, tracked: reported ? [identity(listed)] : [])
        #expect(resolution.groupFor.isEmpty, "\(reason)")
    }

    /// G1 shows 30 and took 10 as its hidden tab (bound with AXTabs 2). 10 is then listed with a tab bar.
    private func rebind(tabCount: Int, shownStillHidden: Bool = true, spaces: [UInt32: Set<UInt64>]? = nil) -> (TabGroupTracker, TabResolution) {
        var tracker = TabGroupTracker()
        _ = tracker.update(
            pid: pid, bundleID: bundleID, visible: [visible(30, 2)], cgWindows: [cg(10), cg(11), cg(12), cg(30, onScreen: true)],
            spaces: spaces.map { _ in [30: [1]] }
        )
        #expect(tracker.members(of: identity(30)) == [10, 30])
        let resolution = tracker.update(
            pid: pid, bundleID: bundleID, visible: [visible(10, tabCount)],
            cgWindows: [cg(10, onScreen: true), cg(11), cg(12)] + (shownStillHidden ? [cg(30)] : []), tracked: [identity(30)], spaces: spaces
        )
        return (tracker, resolution)
    }

    @Test func aMemberWhoseTabCountDiffersFromItsGroupsLeavesItWhileTheShownTabIsStillThere() {
        let (tracker, resolution) = rebind(tabCount: 3)
        #expect(resolution.groupFor == [10: identity(10)])
        #expect(tracker.members(of: identity(30)) == [30])
        #expect(tracker.members(of: identity(10)) == [10, 11, 12])
    }

    @Test func aMemberWithTheGroupsTabCountRebindsIt() {
        let (_, resolution) = rebind(tabCount: 2)
        #expect(resolution.groupFor == [10: identity(30)])
    }

    @Test func aMemberRebindsItsGroupOnceTheShownTabLeftTheCGList() {
        let (_, resolution) = rebind(tabCount: 3, shownStillHidden: false)
        #expect(resolution.groupFor == [10: identity(30)])
    }

    @Test func aMemberOnAnotherSpaceNeverRebindsTheGroup() {
        let (tracker, resolution) = rebind(tabCount: 2, spaces: [10: [2], 30: []])
        #expect(resolution.groupFor == [10: identity(10)])
        #expect(tracker.members(of: identity(30)) == [30])
    }
}

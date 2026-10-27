import TransomEngine
import TransomModel
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

    /// Review WR-01 (R1): a sweep's CG list taken before Cmd-T still shows A (10) onscreen and lacks the new tab 40.
    /// The tab still takes A, and only A: an onscreen same-frame window that was not A stays out.
    @Test func aNewTabMissingFromAStaleCGListStillTakesTheWindowItWasOpenedFrom() {
        var tracker = TabGroupTracker()
        _ = tracker.update(
            pid: pid, bundleID: bundleID, visible: [visible(10, 1)], cgWindows: [cg(5, onScreen: true), cg(10, onScreen: true)],
            tracked: [identity(10)]
        )
        let resolution = tracker.update(
            pid: pid, bundleID: bundleID, visible: [visible(40, 2)], cgWindows: [cg(5, onScreen: true), cg(10, onScreen: true)],
            tracked: [identity(10)]
        )
        #expect(resolution.groupFor == [40: identity(10)])
        #expect(tracker.members(of: identity(10)) == [10, 40])
        #expect(resolution.memberIDs == [10, 40])
        #expect(resolution.folded.isEmpty)
    }

    // MARK: 02-19 (G-02-10): a hidden tab keeps the CG bounds it had when hidden, so timing links a new tab to its opener

    private static let taller = Rect(x: frame.x, y: frame.y, width: frame.width, height: frame.height + 28)

    /// Standalone 10 listed alone, then Cmd-T: 40 shown 28 pt taller (Terminal's tab bar), 10 hidden at its old frame.
    private func cmdTTaller(spaces: [UInt32: Set<UInt64>]? = nil, spaceChanged: Bool = false) -> (TabGroupTracker, TabResolution) {
        var tracker = TabGroupTracker()
        _ = tracker.update(pid: pid, bundleID: bundleID, visible: [visible(10, 1)], cgWindows: [cg(10, onScreen: true)], tracked: [identity(10)])
        let resolution = tracker.update(
            pid: pid, bundleID: bundleID, visible: [visible(40, 2, Self.taller)], cgWindows: [cg(10), cg(40, Self.taller, onScreen: true)],
            tracked: [identity(10)], spaces: spaces, spaceChanged: spaceChanged
        )
        return (tracker, resolution)
    }

    /// (a) The opener was listed last update and went hidden now: it leads the group though its bounds differ.
    @Test func aNewTabTallerThanItsOpenerStillTakesIt() {
        let (tracker, resolution) = cmdTTaller()
        #expect(resolution.groupFor == [40: identity(10)])
        #expect(tracker.members(of: identity(10)) == [10, 40])
        #expect(resolution.folded.isEmpty)
    }

    /// (b) Two standalones went hidden in one refresh: the nearest by origin and width is the opener, in any order.
    @Test(arguments: [false, true])
    func twoWindowsGoneHiddenAreToldApartByOriginAndWidth(swapped: Bool) {
        var tracker = TabGroupTracker()
        let away = Rect(x: 800, y: frame.y, width: frame.width, height: frame.height)
        let tracked = swapped ? [identity(20), identity(10)] : [identity(10), identity(20)]
        _ = tracker.update(
            pid: pid, bundleID: bundleID, visible: [visible(10, 1), visible(20, 1, away)],
            cgWindows: [cg(10, onScreen: true), cg(20, away, onScreen: true)], tracked: tracked
        )
        let resolution = tracker.update(
            pid: pid, bundleID: bundleID, visible: [visible(40, 2, Self.taller)],
            cgWindows: [cg(10), cg(20, away), cg(40, Self.taller, onScreen: true)], tracked: tracked
        )
        #expect(resolution.groupFor == [40: identity(10)])
        #expect(tracker.members(of: identity(10)) == [10, 40])
        #expect(tracker.members(of: identity(20)).isEmpty)
        #expect(!resolution.memberIDs.contains(20))
    }

    /// (c) Without Space data, an update flagged `spaceChanged` links nothing by timing (02-17 rule). Known limit: a
    /// Cmd-T in the same update as such a Space switch is linked only if its opener is in the slot.
    @Test func aBlindSpaceSwitchLinksNoOpenerByTiming() {
        let (_, resolution) = cmdTTaller(spaceChanged: true)
        #expect(resolution.groupFor == [40: identity(40)])
    }

    /// (d) A window known to be on another Space is never the opener.
    @Test func aWindowOnAnotherSpaceIsNeverTheOpenerByTiming() {
        let (tracker, resolution) = cmdTTaller(spaces: [40: [1], 10: [2]])
        #expect(resolution.groupFor == [40: identity(40)])
        #expect(tracker.members(of: identity(10)).isEmpty)
    }

    /// (e) A hidden tab may report no Space: it can still be the opener.
    @Test func aHiddenOpenerWithNoSpaceIsStillTheOpener() {
        let (tracker, resolution) = cmdTTaller(spaces: [40: [1], 10: []])
        #expect(resolution.groupFor == [40: identity(10)])
        #expect(tracker.members(of: identity(10)) == [10, 40])
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
        shownGone: Bool = true, spaceChanged: Bool = false
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
            tracked: tracked + [identity(30)], spaces: [listed: listedSpace, 10: [2]], invalid: shownGone ? [] : [30],
            spaceChanged: spaceChanged
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

    /// With Space data a Space switch changes nothing: the former tab still takes the identity.
    @Test(arguments: [true, false])
    func withSpaceDataAFlaggedUpdateStillHandsTheIdentityToAFormerTab(shownGone: Bool) {
        #expect(orphanHandoff(shownGone: shownGone, spaceChanged: true).groupFor == [31: identity(30)])
    }

    /// Without Space data: G shows 30 (AXTabs 2) and takes 31, which ranks before 50; both sat offscreen in the slot.
    /// Then 30 and 31 are gone and 50 is listed onscreen on its own.
    private func fallbackOrphanHandoff(spaceChanged: Bool) -> (TabGroupTracker, TabResolution) {
        var tracker = TabGroupTracker()
        _ = tracker.update(pid: pid, bundleID: bundleID, visible: [visible(30, 2)], cgWindows: [cg(30, onScreen: true), cg(31), cg(50)])
        #expect(tracker.members(of: identity(30)) == [30, 31])
        let resolution = tracker.update(
            pid: pid, bundleID: bundleID, visible: [visible(50, 1)], cgWindows: [cg(50, onScreen: true)], tracked: [identity(30)],
            spaceChanged: spaceChanged
        )
        return (tracker, resolution)
    }

    @Test func withoutSpaceDataAnUnflaggedUpdateStillHandsTheIdentityToAFormerTab() {
        #expect(fallbackOrphanHandoff(spaceChanged: false).1.groupFor == [50: identity(30)])
    }

    /// 50 may be another Space's twin the switch just showed, so the handoff waits for the next update.
    @Test func withoutSpaceDataAFlaggedUpdateMakesNoOrphanHandoff() {
        let resolution = fallbackOrphanHandoff(spaceChanged: true).1
        #expect(resolution.groupFor.isEmpty)
        #expect(resolution.tabCount[identity(30)] == nil)
    }

    /// Tracked standalone 10 and 20 (elsewhere) listed; then 10 shows AXTabs 2 and 20 sits offscreen in its slot.
    private func fold(spaceChanged: Bool, spaces: [UInt32: Set<UInt64>]? = nil) -> (TabGroupTracker, TabResolution) {
        var tracker = TabGroupTracker()
        let away = Rect(x: 800, y: 100, width: 500, height: 300)
        let tracked = [identity(10), identity(20)]
        _ = tracker.update(
            pid: pid, bundleID: bundleID, visible: [visible(10, 1), visible(20, 1, away)], cgWindows: [cg(10, onScreen: true), cg(20, away, onScreen: true)],
            tracked: tracked, spaces: spaces
        )
        let resolution = tracker.update(
            pid: pid, bundleID: bundleID, visible: [visible(10, 2)], cgWindows: [cg(10, onScreen: true), cg(20)], tracked: tracked, spaces: spaces,
            spaceChanged: spaceChanged
        )
        return (tracker, resolution)
    }

    @Test func withoutSpaceDataAnUnflaggedUpdateFoldsATrackedWindowIntoAGroup() {
        #expect(fold(spaceChanged: false).1.folded == [identity(20)])
    }

    /// 20 may be a live window left on the other Space: no new fold in a flagged update without Space data.
    @Test func withoutSpaceDataAFlaggedUpdateFoldsNoTrackedWindow() {
        let (tracker, resolution) = fold(spaceChanged: true)
        #expect(resolution.folded.isEmpty)
        #expect(tracker.members(of: identity(10)) == [10])
    }

    @Test func withSpaceDataAFlaggedUpdateStillFoldsATrackedWindowOnTheSameSpace() {
        #expect(fold(spaceChanged: true, spaces: [10: [1], 20: [1]]).1.folded == [identity(20)])
    }

    /// A window folded at an unflagged update stays a member, and folded, at the next, flagged, update.
    @Test func aFlaggedUpdateKeepsAWindowFoldedEarlier() {
        var (tracker, _) = fold(spaceChanged: false)
        let resolution = tracker.update(
            pid: pid, bundleID: bundleID, visible: [visible(10, 2)], cgWindows: [cg(10, onScreen: true), cg(20)],
            tracked: [identity(10), identity(20)], spaceChanged: true
        )
        #expect(resolution.folded == [identity(20)])
        #expect(tracker.members(of: identity(10)) == [10, 20])
    }

    /// The Cmd-T rule holds in a flagged update without Space data: a Space switch cannot make a tab brand new.
    @Test func aFlaggedUpdateStillLetsACmdTTabLeadTheGroupWithTheWindowItCameFrom() {
        var tracker = TabGroupTracker()
        _ = tracker.update(pid: pid, bundleID: bundleID, visible: [visible(10, 1)], cgWindows: [cg(10, onScreen: true)])
        let resolution = tracker.update(
            pid: pid, bundleID: bundleID, visible: [visible(11, 2)], cgWindows: [cg(10), cg(11, onScreen: true)], tracked: [identity(10)],
            spaceChanged: true
        )
        #expect(resolution.groupFor == [11: identity(10)])
        #expect(resolution.memberIDs == [10, 11])
        #expect(resolution.folded.isEmpty)
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

    /// A changed AXTabs count is Cmd-T, a background tab or a closed tab, so it alone never refuses a rebind (review CR-01).
    @Test func aMemberWhoseTabCountChangedStillRebindsItsGroupWhileTheShownTabIsStillThere() {
        let (tracker, resolution) = rebind(tabCount: 3)
        #expect(resolution.groupFor == [10: identity(30)])
        #expect(tracker.members(of: identity(30)).isSuperset(of: [10, 30]))
        #expect(tracker.members(of: identity(10)).isEmpty)
    }

    /// A member refused for being on another Space leads its own group, which never takes the refused group's tabs.
    @Test func aMemberOnAnotherSpaceNeverTakesItsOldGroupsTabs() {
        let (tracker, resolution) = rebind(tabCount: 4, spaces: [10: [2], 30: []])
        #expect(resolution.groupFor == [10: identity(10)])
        #expect(tracker.members(of: identity(30)) == [30])
        #expect(tracker.members(of: identity(10)) == [10, 11, 12])
    }

    /// A group's own leader refused for being on another Space never founds a second group under the same identity.
    @Test func aRefusedLeaderNeverFoundsASecondGroupUnderItsIdentity() {
        var tracker = TabGroupTracker()
        _ = tracker.update(pid: pid, bundleID: bundleID, visible: [visible(10, 1)], cgWindows: [cg(10, onScreen: true)], spaces: [10: [1]])
        _ = tracker.update(
            pid: pid, bundleID: bundleID, visible: [visible(40, 2)], cgWindows: [cg(10), cg(40, onScreen: true)], tracked: [identity(10)],
            spaces: [40: [1]]
        )
        #expect(tracker.members(of: identity(10)) == [10, 40])
        let resolution = tracker.update(
            pid: pid, bundleID: bundleID, visible: [visible(10, 3)], cgWindows: [cg(10, onScreen: true), cg(40), cg(50)],
            tracked: [identity(10)], spaces: [10: [2]]
        )
        #expect(resolution.tabCount.count == 1)
        #expect(resolution.groupFor[10] == nil)
        #expect(tracker.members(of: identity(10)) == [40])
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

    // MARK: 02-16: a corrected window ID (WindowTracker.rekey)

    @Test func aRekeyedLeaderRenamesTheIDAndHandsTheGroupToTheNewLeader() {
        var (tracker, _) = threeTabs()
        var other = TabGroupTracker()
        _ = other.update(pid: pid + 1, bundleID: bundleID, visible: [visible(10, 3)], cgWindows: [cg(10, onScreen: true, pid: pid + 1), cg(11, pid: pid + 1), cg(12, pid: pid + 1)])
        tracker.rekey(pid: pid + 1, from: 10, to: 20, newLeader: nil)
        #expect(tracker.members(of: identity(10)) == [10, 11, 12], "another pid's rekey changes nothing here")

        tracker.rekey(pid: pid, from: 10, to: 20, newLeader: identity(20))
        #expect(tracker.members(of: identity(20)) == [20, 11, 12])
        #expect(tracker.members(of: identity(10)).isEmpty)
        #expect(tracker.shownTab(containing: 20, pid: pid) == 20)
        #expect(!tracker.isKnownMember(10, pid: pid))
        let resolution = tracker.update(pid: pid, bundleID: bundleID, visible: [visible(20, 3)], cgWindows: [cg(20, onScreen: true), cg(11), cg(12)])
        #expect(resolution.groupFor == [20: identity(20)])
        #expect(resolution.memberIDs == [20, 11, 12])
    }

    @Test func aRekeyedHiddenTabIsRenamedAndTheLeaderStays() {
        var (tracker, _) = threeTabs()
        tracker.rekey(pid: pid, from: 11, to: 21, newLeader: identity(21))
        #expect(tracker.members(of: identity(10)) == [10, 21, 12])
        #expect(tracker.isKnownMember(21, pid: pid))
        #expect(!tracker.isKnownMember(11, pid: pid))
        #expect(tracker.shownTab(containing: 21, pid: pid) == 10)
    }
}

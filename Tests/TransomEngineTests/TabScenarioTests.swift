import TransomEngine
import TransomModel
import TransomTestSupport
import Testing

private let pid: Int32 = 600
private let bundleID = "com.example.tabs"
private let frame = Rect(x: 100, y: 100, width: 600, height: 400)

private func ref(_ id: UInt32) -> WindowRef {
    WindowRef(identity: WindowIdentity(windowID: id, pid: pid, bundleID: bundleID))
}

/// Every event already yielded (the fake yields synchronously). Ends the stream, so call it once per fake.
private func drain(_ stream: AsyncStream<WindowEvent>) async -> [WindowEvent] {
    let reader = Task {
        var events: [WindowEvent] = []
        for await event in stream { events.append(event) }
        return events
    }
    try? await Task.sleep(for: .milliseconds(100))
    reader.cancel()
    return await reader.value
}

private func created(_ events: [WindowEvent]) -> [WindowInfo] {
    events.compactMap { if case .windowCreated(let info) = $0 { info } else { nil } }
}

private func destroyed(_ events: [WindowEvent]) -> [WindowRef] {
    events.compactMap { if case .windowDestroyed(let ref) = $0 { ref } else { nil } }
}

/// One app with a three-tab window (10 visible; 11 and 12 hidden), after the initial sweep.
private func threeTabs() async -> FakeWindowSystem {
    let fake = FakeWindowSystem()
    await fake.addApp(FakeApp(pid: pid, bundleID: bundleID))
    await fake.tabGroup(ids: [10, 11, 12], frame: frame, pid: pid, visible: 10)
    await fake.refreshAll()
    return fake
}

/// Space data off; on with hidden tabs reporting no Space; on with hidden tabs reporting their group's Space.
private let modes: [(spacesAvailable: Bool, hiddenTabsReportSpace: Bool)] = [(false, false), (true, false), (true, true)]

/// A fake with one app and Space data on or off.
private func spacesFake(_ spacesAvailable: Bool, _ hiddenTabsReportSpace: Bool) async -> FakeWindowSystem {
    let fake = FakeWindowSystem()
    await fake.addApp(FakeApp(pid: pid, bundleID: bundleID))
    await fake.setSpacesAvailable(spacesAvailable)
    await fake.setHiddenTabsReportSpace(hiddenTabsReportSpace)
    return fake
}

/// One refresh (after `advancing` 250 ms), then the two safety invariants every scenario keeps in both modes:
/// a tracked window disappears only once the tab it showed closed or became a hidden tab of a tracked window, and
/// no window ID stands for two tracked windows.
private func refresh(_ fake: FakeWindowSystem, advancing: Bool = false, sourceLocation: SourceLocation = #_sourceLocation) async {
    let before = await fake.inventory().windows
    if advancing { await fake.advance(by: .milliseconds(250)) }
    await fake.refreshAll()
    let after = await fake.inventory().windows
    let windows = await fake.windows
    let shownGroups = Set(after.compactMap { windows[$0.visibleMemberID ?? $0.window.windowID]?.tabGroupID })
    for gone in before where !after.contains(where: { $0.window.identity == gone.window.identity }) {
        let shown = gone.visibleMemberID ?? gone.window.windowID
        guard let window = windows[shown], window.axValid, window.inCGList else { continue }
        let folded = window.tabGroupID.map { shownGroups.contains($0) } ?? false
        #expect(folded, "window \(gone.window.windowID) was reported destroyed while its tab \(shown) is alive", sourceLocation: sourceLocation)
    }
    var owner: [UInt32: WindowIdentity] = [:]
    for info in after {
        for id in Set([info.window.windowID, info.visibleMemberID ?? info.window.windowID]) {
            let previous = owner.updateValue(info.window.identity, forKey: id)
            #expect(previous == nil, "window ID \(id) is tracked under two identities", sourceLocation: sourceLocation)
        }
    }
}

/// A Space switch, then two refreshes 250 ms apart so new windows settle.
private func visit(_ fake: FakeWindowSystem, _ space: UInt64, sourceLocation: SourceLocation = #_sourceLocation) async {
    await fake.showSpace(space)
    await refresh(fake, sourceLocation: sourceLocation)
    await refresh(fake, advancing: true, sourceLocation: sourceLocation)
}

private func summary(_ fake: FakeWindowSystem) async -> [[UInt32]] {
    await fake.inventory().windows.map { [$0.window.windowID, $0.visibleMemberID ?? 0, UInt32($0.tabCount)] }
}

/// WIN-06 / D-08 on the fake: a tabbed window is one tracked window that follows its visible tab.
@Suite struct TabScenarioTests {
    @Test func threeTabsAreOneWindowLedByTheVisibleTab() async {
        let fake = await threeTabs()
        let inventory = await fake.inventory().windows
        #expect(inventory.count == 1)
        let info = inventory.first
        #expect(info?.window == ref(10))
        #expect(info?.visibleMemberID == 10)
        #expect(info?.tabCount == 3)
        #expect(created(await drain(fake.events)).map(\.window) == [ref(10)])
    }

    @Test func aTabSwitchRebindsTheVisibleTabWithoutCreatingOrDestroying() async {
        let fake = await threeTabs()
        await fake.selectTab(11)
        await fake.refreshAll()
        let info = await fake.windowInfo(ref(10))
        #expect(info?.window == ref(10))
        #expect(info?.visibleMemberID == 11)
        #expect(info?.tabCount == 3)
        #expect(await fake.inventory().windows.count == 1)
        let events = await drain(fake.events)
        #expect(created(events).map(\.window) == [ref(10)])
        #expect(destroyed(events).isEmpty)
        #expect(events.contains(.windowFocused(ref(10))))
    }

    @Test func closingTheVisibleTabKeepsTheGroup() async {
        let fake = await threeTabs()
        await fake.selectTab(11)
        await fake.refreshAll()
        await fake.close(11)
        await fake.selectTab(12)
        await fake.refreshAll()
        await fake.refreshAll()
        let info = await fake.windowInfo(ref(10))
        #expect(info?.visibleMemberID == 12)
        #expect(info?.tabCount == 2)
        #expect(await fake.inventory().windows.count == 1)
        #expect(destroyed(await drain(fake.events)).isEmpty)
    }

    @Test func closingTheLastTabsDestroysTheGroupOnce() async {
        let fake = await threeTabs()
        await fake.selectTab(11)
        await fake.refreshAll()
        await fake.close(11)
        await fake.selectTab(12)
        await fake.refreshAll()
        await fake.close(10)
        await fake.close(12)
        await fake.refreshAll()
        await fake.refreshAll()
        #expect(await fake.windowInfo(ref(10)) == nil)
        #expect(await fake.inventory().windows.isEmpty)
        let events = await drain(fake.events)
        #expect(destroyed(events) == [ref(10)])
        #expect(created(events).map(\.window) == [ref(10)])
    }

    /// C1: Cmd-T in a standalone window with no twin anywhere.
    @Test(arguments: modes)
    func aStandaloneWindowThatGainsATabStaysOneWindowLedByItself(spacesAvailable: Bool, hiddenTabsReportSpace: Bool) async {
        let fake = await spacesFake(spacesAvailable, hiddenTabsReportSpace)
        await fake.open(.standard(id: 10, pid: pid, frame: frame, space: 1))
        await fake.showSpace(1)
        await refresh(fake)
        await fake.newTab(40, in: 10)
        for _ in 0..<3 { await refresh(fake, advancing: true) }
        #expect(await summary(fake) == [[10, 40, 2]])

        await fake.selectTab(10)
        await refresh(fake)
        #expect(await summary(fake) == [[10, 10, 2]])
        let events = await drain(fake.events)
        #expect(created(events).map(\.window) == [ref(10)])
        #expect(destroyed(events).isEmpty)
    }

    /// G-02-10 E1 (Terminal): Cmd-N then Cmd-T, where the new tab is 28 pt taller (the tab bar) and the opener goes
    /// hidden at its old frame. Bounds cannot link them; timing does.
    @Test(arguments: modes)
    func aCmdTWhoseNewTabIsTallerStaysOneWindowLedByItsOpener(spacesAvailable: Bool, hiddenTabsReportSpace: Bool) async {
        let fake = await spacesFake(spacesAvailable, hiddenTabsReportSpace)
        await fake.open(.standard(id: 10, pid: pid, frame: frame, space: 1))
        await fake.showSpace(1)
        await refresh(fake)
        let taller = Rect(x: frame.x, y: frame.y, width: frame.width, height: frame.height + 28)
        await fake.newTab(40, in: 10, frame: taller)
        for _ in 0..<3 { await refresh(fake, advancing: true) }
        var rows = await summary(fake)
        #expect(rows == [[10, 40, 2]])

        await fake.selectTab(10)
        await refresh(fake)
        rows = await summary(fake)
        #expect(rows == [[10, 10, 2]])

        await fake.newTab(50, in: 10)
        for _ in 0..<2 { await refresh(fake, advancing: true) }
        rows = await summary(fake)
        #expect(rows == [[10, 50, 3]])
        let events = await drain(fake.events)
        #expect(created(events).map(\.window) == [ref(10)])
        #expect(destroyed(events).isEmpty)
    }

    /// Standalone 10 with tab 40 shown; then 40 goes 28 pt shorter by `resize` while hidden 10 keeps `frame`;
    /// then Cmd-T opens 50 at the hidden sibling's frame (G-02-10 E4, Finder).
    private func resizedGroupGainsATab(_ fake: FakeWindowSystem, resize: (FakeWindowSystem, Rect) async -> Void) async -> [[UInt32]] {
        await fake.open(.standard(id: 10, pid: pid, frame: frame, space: 1))
        await fake.showSpace(1)
        await refresh(fake)
        await fake.newTab(40, in: 10)
        for _ in 0..<2 { await refresh(fake, advancing: true) }
        var rows = await summary(fake)
        #expect(rows == [[10, 40, 2]])

        let shorter = Rect(x: frame.x, y: frame.y, width: frame.width, height: frame.height - 28)
        await resize(fake, shorter)
        await refresh(fake, advancing: true)
        rows = await summary(fake)
        #expect(rows == [[10, 40, 2]])
        #expect(await fake.windows[10]?.frame == frame)

        await fake.newTab(50, in: 40, frame: frame)
        for _ in 0..<3 { await refresh(fake, advancing: true) }
        return await summary(fake)
    }

    /// G-02-10 E4 (Finder): the shown tab of a two-tab group is resized, its hidden sibling keeps the old frame, and
    /// Cmd-T opens at the sibling's frame. One group, under its first identity.
    @Test(arguments: modes)
    func aCmdTAfterTheShownTabWasResizedStaysOneGroup(spacesAvailable: Bool, hiddenTabsReportSpace: Bool) async {
        let fake = await spacesFake(spacesAvailable, hiddenTabsReportSpace)
        let rows = await resizedGroupGainsATab(fake) { await $0.userMove(40, to: $1) }
        #expect(rows == [[10, 50, 3]])
        let events = await drain(fake.events)
        #expect(created(events).map(\.window) == [ref(10)])
        #expect(destroyed(events).isEmpty)
    }

    /// Cmd-W on the shown tab of that resized group shows the next tab under the same identity (WIN-06, WIN-09).
    @Test(arguments: modes)
    func cmdWInAResizedGroupFollowsTheNextTab(spacesAvailable: Bool, hiddenTabsReportSpace: Bool) async {
        let fake = await spacesFake(spacesAvailable, hiddenTabsReportSpace)
        var rows = await resizedGroupGainsATab(fake) { await $0.userMove(40, to: $1) }
        #expect(rows == [[10, 50, 3]])
        await fake.close(50)
        await fake.selectTab(40)
        for _ in 0..<2 { await refresh(fake, advancing: true) }
        rows = await summary(fake)
        #expect(rows == [[10, 40, 2]])
        #expect(destroyed(await drain(fake.events)).isEmpty)
    }

    /// A Transom frame write moves only the group's shown tab, as the live AX write does; a later Cmd-T stays one group.
    @Test(arguments: modes)
    func aFrameWriteToATabGroupThenCmdTStaysOneGroup(spacesAvailable: Bool, hiddenTabsReportSpace: Bool) async {
        let fake = await spacesFake(spacesAvailable, hiddenTabsReportSpace)
        let rows = await resizedGroupGainsATab(fake) { await $0.perform([.setFrame(ref(10), $1)]) }
        #expect(rows == [[10, 50, 3]])
        let events = await drain(fake.events)
        #expect(created(events).map(\.window) == [ref(10)])
        #expect(destroyed(events).isEmpty)
    }

    /// 02-19 known limit: W (5), a same-frame window of the same app, leaves the Space (moved, not a Space switch) in
    /// the same refresh as Cmd-T in O (10) opens 40 taller. Without Space data both went hidden at the same origin and
    /// width, so the lowest ID, W, is taken as the opener and leads the group: an identity misattributed. When W
    /// returns as a single window it rebinds its group alone (the leader stays a member), and 40 founds a fresh
    /// identity. Nothing is destroyed. With Space data W is known to be on Space 2 and O is the opener.
    @Test(arguments: modes)
    func knownLimitAWindowLeavingTheSpaceWithACmdTCanBeTakenAsItsOpener(spacesAvailable: Bool, hiddenTabsReportSpace: Bool) async {
        let fake = await spacesFake(spacesAvailable, hiddenTabsReportSpace)
        await fake.open(.standard(id: 5, pid: pid, frame: frame, space: 1))
        await fake.open(.standard(id: 10, pid: pid, frame: frame, space: 1))
        await fake.showSpace(1)
        await refresh(fake)
        let taller = Rect(x: frame.x, y: frame.y, width: frame.width, height: frame.height + 28)
        await fake.newTab(40, in: 10, frame: taller)
        await fake.update(5) {
            $0.space = 2
            $0.listedInAX = false
            $0.onScreen = false
        }
        for _ in 0..<3 { await refresh(fake, advancing: true) }
        var rows = await summary(fake)
        #expect(rows == (spacesAvailable ? [[5, 5, 1], [10, 40, 2]] : [[5, 40, 2], [10, 10, 1]]))

        await fake.update(5) {
            $0.space = 1
            $0.listedInAX = true
            $0.onScreen = true
        }
        for _ in 0..<2 { await refresh(fake, advancing: true) }
        rows = await summary(fake)
        #expect(rows == (spacesAvailable ? [[5, 5, 1], [10, 40, 2]] : [[5, 5, 1], [10, 10, 1], [40, 40, 2]]))
        let events = await drain(fake.events)
        #expect(created(events).map(\.window) == (spacesAvailable ? [ref(5), ref(10)] : [ref(5), ref(10), ref(40)]))
        #expect(destroyed(events).isEmpty)
    }

    /// Review D1 (iteration 4): A (10) gains tab 40; then Cmd-T (50) and a click back on tab 10 land in one refresh,
    /// so the leader is listed with a new AXTabs count while the old shown tab sits offscreen.
    @Test(arguments: modes)
    func cmdTAndASwitchToTheLeaderInOneRefreshStayOneGroup(spacesAvailable: Bool, hiddenTabsReportSpace: Bool) async {
        let fake = await spacesFake(spacesAvailable, hiddenTabsReportSpace)
        await fake.open(.standard(id: 10, pid: pid, frame: frame, space: 1))
        await fake.showSpace(1)
        await refresh(fake)
        await fake.newTab(40, in: 10)
        for _ in 0..<2 { await refresh(fake, advancing: true) }
        #expect(await summary(fake) == [[10, 40, 2]])

        await fake.newTab(50, in: 10)
        await fake.selectTab(10)
        for _ in 0..<2 { await refresh(fake, advancing: true) }
        #expect(await summary(fake) == [[10, 10, 3]])
        let events = await drain(fake.events)
        #expect(created(events).map(\.window) == [ref(10)])
        #expect(destroyed(events).isEmpty)
    }

    /// Review D2 (iteration 4): tabs 10 (leader), 40 and 50, 50 shown; Cmd-T (60) and a click on 40 in one refresh.
    @Test(arguments: modes)
    func cmdTAndASwitchToAnotherTabInOneRefreshStayOneGroup(spacesAvailable: Bool, hiddenTabsReportSpace: Bool) async {
        let fake = await spacesFake(spacesAvailable, hiddenTabsReportSpace)
        await fake.open(.standard(id: 10, pid: pid, frame: frame, space: 1))
        await fake.showSpace(1)
        await refresh(fake)
        await fake.newTab(40, in: 10)
        for _ in 0..<2 { await refresh(fake, advancing: true) }
        await fake.newTab(50, in: 10)
        for _ in 0..<2 { await refresh(fake, advancing: true) }
        #expect(await summary(fake) == [[10, 50, 3]])

        await fake.newTab(60, in: 10)
        await fake.selectTab(40)
        for _ in 0..<2 { await refresh(fake, advancing: true) }
        #expect(await summary(fake) == [[10, 40, 4]])
        await fake.selectTab(50)
        await refresh(fake, advancing: true)
        #expect(await summary(fake) == [[10, 50, 4]])
        let events = await drain(fake.events)
        #expect(created(events).map(\.window) == [ref(10)])
        #expect(destroyed(events).isEmpty)
    }

    /// C3: Window > Merge All Windows. The merged window is reported gone only after a second refresh agrees.
    @Test(arguments: modes)
    func mergingTwoTrackedWindowsLeavesOneGroupAndReportsTheOtherGone(spacesAvailable: Bool, hiddenTabsReportSpace: Bool) async {
        let fake = await spacesFake(spacesAvailable, hiddenTabsReportSpace)
        await fake.open(.standard(id: 10, pid: pid, frame: frame, space: 1))
        await fake.open(.standard(id: 20, pid: pid, frame: Rect(x: 800, y: 100, width: 500, height: 300), space: 1))
        await fake.showSpace(1)
        await refresh(fake)
        // 20 joins 10's frame as its hidden tab.
        await fake.update(20) {
            $0.frame = frame
            $0.tabGroupID = 10
        }
        await fake.update(10) { $0.tabGroupID = 10 }
        await fake.selectTab(10)
        await refresh(fake)
        #expect(await summary(fake) == [[10, 10, 2], [20, 20, 1]], "a fold is never destroyed on its first refresh")
        await refresh(fake)
        #expect(await summary(fake) == [[10, 10, 2]])
        #expect(destroyed(await drain(fake.events)) == [ref(20)])
    }

    /// C4: a listed minimised twin with the same frame is never a hidden tab.
    @Test(arguments: modes)
    func aListedMinimizedTwinStaysItsOwnWindow(spacesAvailable: Bool, hiddenTabsReportSpace: Bool) async {
        let fake = await spacesFake(spacesAvailable, hiddenTabsReportSpace)
        await fake.tabGroup(ids: [30, 31], frame: frame, pid: pid, visible: 30, space: 1)
        var twin = FakeWindow.standard(id: 32, pid: pid, frame: frame, space: 1)
        twin.snapshot.minimized = true
        await fake.open(twin)
        await fake.showSpace(1)
        await fake.update(32) { $0.onScreen = false }
        await refresh(fake)
        await refresh(fake, advancing: true)
        #expect(await summary(fake) == [[30, 30, 2], [32, 32, 1]])
        let events = await drain(fake.events)
        #expect(created(events).map(\.window) == [ref(30), ref(32)])
        #expect(destroyed(events).isEmpty)
    }

    /// Review S4: A (10) tracked on Space 1, tab group 30 + 31 in the same slot on Space 2, first seen after the switch.
    @Test(arguments: modes)
    func aTrackedWindowNeverLeadsAGroupOnAnotherSpaceWithTheSameFrame(spacesAvailable: Bool, hiddenTabsReportSpace: Bool) async {
        let fake = await spacesFake(spacesAvailable, hiddenTabsReportSpace)
        await fake.tabGroup(ids: [30, 31], frame: frame, pid: pid, visible: 30, space: 2)
        await fake.open(.standard(id: 10, pid: pid, frame: frame, space: 1))
        await fake.showSpace(1)
        await refresh(fake)
        for space: UInt64 in [2, 1, 2] { await visit(fake, space) }
        #expect(await summary(fake) == [[10, 10, 1], [30, 30, 2]])
        let events = await drain(fake.events)
        #expect(created(events).map(\.window) == [ref(10), ref(30)])
        #expect(destroyed(events).isEmpty)
    }

    /// Review S6: tab group 30 + 31 tracked on Space 2; A (10) opened in the same slot on Space 1; back and forth.
    @Test(arguments: modes)
    func aWindowOnAnotherSpaceWithTheSameFrameIsNeverFoldedIntoAGroup(spacesAvailable: Bool, hiddenTabsReportSpace: Bool) async {
        let fake = await spacesFake(spacesAvailable, hiddenTabsReportSpace)
        await fake.tabGroup(ids: [30, 31], frame: frame, pid: pid, visible: 30, space: 2)
        await fake.showSpace(2)
        await refresh(fake)
        await fake.open(.standard(id: 10, pid: pid, frame: frame, space: 1))
        for space: UInt64 in [1, 2, 1] { await visit(fake, space) }
        #expect(await summary(fake) == [[10, 10, 1], [30, 30, 2]])
        let events = await drain(fake.events)
        #expect(created(events).map(\.window) == [ref(30), ref(10)])
        #expect(destroyed(events).isEmpty)
    }

    /// Review S5: A (10) already exists on Space 1, untracked, when the group is first seen on Space 2. Without Space
    /// data it may fill the group's free slot at first, but once it is listed on its own Space it is its own window.
    @Test(arguments: modes)
    func anUntrackedTwinOnAnotherSpaceLeavesTheGroupOnceItIsListed(spacesAvailable: Bool, hiddenTabsReportSpace: Bool) async {
        let fake = await spacesFake(spacesAvailable, hiddenTabsReportSpace)
        await fake.tabGroup(ids: [30, 31], frame: frame, pid: pid, visible: 30, space: 2)
        await fake.open(.standard(id: 10, pid: pid, frame: frame, space: 1))
        await fake.showSpace(2)
        await refresh(fake)
        for space: UInt64 in [1, 2, 1] { await visit(fake, space) }
        let inventory = await fake.inventory().windows
        #expect(inventory.map(\.window) == [ref(10), ref(30)])
        #expect(inventory.map(\.visibleMemberID) == [10, 30])
        let events = await drain(fake.events)
        #expect(created(events).map(\.window) == [ref(30), ref(10)])
        #expect(destroyed(events).isEmpty)
    }

    @Test func anUntabbedWindowOfTheSameAppIsItsOwnWindow() async {
        let fake = FakeWindowSystem()
        await fake.addApp(FakeApp(pid: pid, bundleID: bundleID))
        await fake.tabGroup(ids: [10, 11, 12], frame: frame, pid: pid, visible: 10)
        await fake.open(.standard(id: 20, pid: pid, frame: Rect(x: 800, y: 100, width: 500, height: 300)))
        await fake.refreshAll()
        let inventory = await fake.inventory().windows
        #expect(inventory.map(\.window) == [ref(10), ref(20)])
        #expect(inventory.map(\.tabCount) == [3, 1])
        #expect(inventory.map(\.visibleMemberID) == [10, 20])
    }
}

/// D-08 / WIN-09 across Spaces (02-14): the reviewer's C2, C5 and C7, with Space data (hidden tabs reporting their
/// Space or none) and without it. Without Space data only the two safety invariants are promised for C5 and its
/// variants: the two groups may be tracked as one window (accepted single-Space limit).
@Suite struct SpaceTabScenarioTests {
    private static let c2Cases: [(Bool, Bool, UInt32)] = modes.flatMap { mode in
        [UInt32(5), 50].map { twin in (mode.spacesAvailable, mode.hiddenTabsReportSpace, twin) }
    }

    /// C2: Cmd-T in A (10, Space 1) while an untracked same-frame twin Z sits on Space 2; then visit Space 2 and return.
    @Test(arguments: c2Cases)
    func cmdTWithATwinOnAnotherSpaceTakesTheWindowItWasOpenedFrom(spacesAvailable: Bool, hiddenTabsReportSpace: Bool, twin: UInt32) async {
        let fake = await spacesFake(spacesAvailable, hiddenTabsReportSpace)
        await fake.open(.standard(id: 10, pid: pid, frame: frame, space: 1))
        await fake.open(.standard(id: twin, pid: pid, frame: frame, space: 2))
        await fake.showSpace(1)
        await refresh(fake)
        await refresh(fake, advancing: true)
        await fake.newTab(40, in: 10)
        await refresh(fake)
        await refresh(fake, advancing: true)
        #expect(await summary(fake) == [[10, 40, 2]])
        await visit(fake, 2)
        await visit(fake, 1)
        let a: [UInt32] = [10, 40, 2]
        let z: [UInt32] = [twin, twin, 1]
        #expect(await summary(fake) == (twin < 10 ? [z, a] : [a, z]))
        let events = await drain(fake.events)
        #expect(created(events).map(\.window) == [ref(10), ref(twin)])
        #expect(destroyed(events).isEmpty)
    }

    /// C5: G1 = 30 + 31 on Space 1 (seen first) and G2 = 10 + 11 on Space 2 in the same slot; switch 1, 2, 1.
    private func c5(_ spacesAvailable: Bool, _ hiddenTabsReportSpace: Bool, visiting spaces: [UInt64] = [2, 1]) async -> FakeWindowSystem {
        let fake = await spacesFake(spacesAvailable, hiddenTabsReportSpace)
        await fake.tabGroup(ids: [30, 31], frame: frame, pid: pid, visible: 30, space: 1)
        await fake.tabGroup(ids: [10, 11], frame: frame, pid: pid, visible: 10, space: 2)
        await fake.showSpace(1)
        await refresh(fake)
        for space in spaces {
            await visit(fake, space)
            if spacesAvailable { #expect(await fake.windowInfo(ref(30))?.visibleMemberID == 30, "G1 follows the other Space's group") }
        }
        return fake
    }

    @Test(arguments: modes)
    func twoSameFrameGroupsOnTwoSpacesStayTwoWindows(spacesAvailable: Bool, hiddenTabsReportSpace: Bool) async {
        let fake = await c5(spacesAvailable, hiddenTabsReportSpace)
        if spacesAvailable { #expect(await summary(fake) == [[10, 10, 2], [30, 30, 2]]) }
        let events = await drain(fake.events)
        #expect(destroyed(events).isEmpty)
        if spacesAvailable { #expect(created(events).map(\.window) == [ref(30), ref(10)]) }
    }

    /// C5 (a): on Space 1, close G1's shown tab 30. 31 takes G1's identity; G2 is untouched.
    @Test(arguments: modes)
    func closingAGroupsShownTabHandsItsIdentityToTheTabLeft(spacesAvailable: Bool, hiddenTabsReportSpace: Bool) async {
        let fake = await c5(spacesAvailable, hiddenTabsReportSpace)
        await fake.close(30)
        await fake.selectTab(31)
        await refresh(fake)
        await refresh(fake, advancing: true)
        if spacesAvailable { #expect(await summary(fake) == [[10, 10, 2], [30, 31, 1]]) }
        await visit(fake, 2)
        if spacesAvailable { #expect(await summary(fake) == [[10, 10, 2], [30, 31, 1]]) }
        let events = await drain(fake.events)
        #expect(destroyed(events).isEmpty)
        if spacesAvailable { #expect(created(events).map(\.window) == [ref(30), ref(10)]) }
    }

    /// C5 (b): as (a), but 30 stays in the CG list for one refresh after AX reports it invalid. 31 takes G1's identity
    /// in that same refresh, and the group never flickers to absent.
    @Test(arguments: modes)
    func anInvalidShownTabStillInTheCGListHandsOverAtOnce(spacesAvailable: Bool, hiddenTabsReportSpace: Bool) async {
        let fake = await c5(spacesAvailable, hiddenTabsReportSpace)
        await fake.update(30) {
            $0.axValid = false
            $0.listedInAX = false
            $0.onScreen = false
        }
        await fake.selectTab(31)
        await refresh(fake)
        if spacesAvailable {
            #expect(await summary(fake) == [[10, 10, 2], [30, 31, 1]])
            #expect(await fake.windowInfo(ref(30))?.state == .present)
        }
        await fake.update(30) { $0.inCGList = false }
        await refresh(fake)
        await refresh(fake, advancing: true)
        if spacesAvailable { #expect(await summary(fake) == [[10, 10, 2], [30, 31, 1]]) }
        let events = await drain(fake.events)
        #expect(destroyed(events).isEmpty)
        if spacesAvailable {
            #expect(created(events).map(\.window) == [ref(30), ref(10)])
            #expect(!events.contains { if case .windowStateChanged(ref(30), _) = $0 { true } else { false } })
        }
    }

    /// C5 (c): on Space 2, close G2's shown tab 10, the mirror image of (a).
    @Test(arguments: modes)
    func closingTheOtherSpacesShownTabHandsItsIdentityToItsTab(spacesAvailable: Bool, hiddenTabsReportSpace: Bool) async {
        let fake = await c5(spacesAvailable, hiddenTabsReportSpace, visiting: [2])
        await fake.close(10)
        await fake.selectTab(11)
        await refresh(fake)
        await refresh(fake, advancing: true)
        await visit(fake, 1)
        if spacesAvailable { #expect(await summary(fake) == [[10, 11, 1], [30, 30, 2]]) }
        let events = await drain(fake.events)
        #expect(destroyed(events).isEmpty)
        if spacesAvailable { #expect(created(events).map(\.window) == [ref(30), ref(10)]) }
    }

    /// C5 tab switches: select 31 in G1 and back, then 11 in G2 on Space 2. Each group keeps its identity.
    @Test(arguments: modes)
    func tabSwitchesInTwoSameFrameGroupsKeepEachGroupsIdentity(spacesAvailable: Bool, hiddenTabsReportSpace: Bool) async {
        let fake = await c5(spacesAvailable, hiddenTabsReportSpace)
        await fake.selectTab(31)
        await refresh(fake)
        if spacesAvailable { #expect(await summary(fake) == [[10, 10, 2], [30, 31, 2]]) }
        await fake.selectTab(30)
        await refresh(fake)
        if spacesAvailable { #expect(await summary(fake) == [[10, 10, 2], [30, 30, 2]]) }
        await visit(fake, 2)
        await fake.selectTab(11)
        await refresh(fake)
        if spacesAvailable { #expect(await summary(fake) == [[10, 11, 2], [30, 30, 2]]) }
        await visit(fake, 1)
        if spacesAvailable { #expect(await summary(fake) == [[10, 11, 2], [30, 30, 2]]) }
        let events = await drain(fake.events)
        #expect(destroyed(events).isEmpty)
        if spacesAvailable { #expect(created(events).map(\.window) == [ref(30), ref(10)]) }
    }

    /// C7: group T = 30 + 31 tracked on Space 2, A (10) on Space 1; Cmd-T in A opens N (40); then back to Space 2.
    private func c7(_ spacesAvailable: Bool, _ hiddenTabsReportSpace: Bool) async -> FakeWindowSystem {
        let fake = await spacesFake(spacesAvailable, hiddenTabsReportSpace)
        await fake.tabGroup(ids: [30, 31], frame: frame, pid: pid, visible: 30, space: 2)
        await fake.open(.standard(id: 10, pid: pid, frame: frame, space: 1))
        await fake.showSpace(2)
        await refresh(fake)
        await visit(fake, 1)
        await fake.newTab(40, in: 10)
        await refresh(fake)
        await refresh(fake, advancing: true)
        await visit(fake, 2)
        return fake
    }

    @Test(arguments: modes)
    func cmdTBesideAGroupOnAnotherSpaceLeadsItsOwnGroup(spacesAvailable: Bool, hiddenTabsReportSpace: Bool) async {
        let fake = await c7(spacesAvailable, hiddenTabsReportSpace)
        #expect(await summary(fake) == [[10, 40, 2], [30, 30, 2]])
        let events = await drain(fake.events)
        #expect(destroyed(events).isEmpty)
        #expect(created(events).map(\.window) == [ref(30), ref(10)])
    }

    /// C7 close: on Space 2, close T's shown tab 30; T's identity follows 31 and A's group is unaffected.
    @Test(arguments: modes)
    func closingTheOtherGroupsShownTabLeavesTheCmdTGroupAlone(spacesAvailable: Bool, hiddenTabsReportSpace: Bool) async {
        let fake = await c7(spacesAvailable, hiddenTabsReportSpace)
        await fake.close(30)
        await fake.selectTab(31)
        await refresh(fake)
        await refresh(fake, advancing: true)
        if spacesAvailable { #expect(await summary(fake) == [[10, 40, 2], [30, 31, 1]]) }
        await visit(fake, 1)
        if spacesAvailable { #expect(await summary(fake) == [[10, 40, 2], [30, 31, 1]]) }
        let events = await drain(fake.events)
        #expect(destroyed(events).isEmpty)
        if spacesAvailable { #expect(created(events).map(\.window) == [ref(30), ref(10)]) }
    }

    /// C7 switch: select 31 in T and back; A's group keeps showing 40.
    @Test(arguments: modes)
    func tabSwitchesInTheOtherGroupLeaveTheCmdTGroupAlone(spacesAvailable: Bool, hiddenTabsReportSpace: Bool) async {
        let fake = await c7(spacesAvailable, hiddenTabsReportSpace)
        await fake.selectTab(31)
        await refresh(fake)
        if spacesAvailable { #expect(await summary(fake) == [[10, 40, 2], [30, 31, 2]]) }
        await fake.selectTab(30)
        await refresh(fake)
        await visit(fake, 1)
        if spacesAvailable { #expect(await summary(fake) == [[10, 40, 2], [30, 30, 2]]) }
        let events = await drain(fake.events)
        #expect(destroyed(events).isEmpty)
        if spacesAvailable { #expect(created(events).map(\.window) == [ref(30), ref(10)]) }
    }

    private static let closeCases: [(Bool, Bool, Bool)] = modes.flatMap { mode in
        [false, true].map { first in (mode.spacesAvailable, mode.hiddenTabsReportSpace, first) }
    }

    /// A group that closes entirely while a brand-new same-frame window N (50) appears, in the same update or one
    /// update earlier: N is never the group's tab. The group is destroyed by CloseRule and N is created on its own.
    @Test(arguments: closeCases)
    func aNewWindowInTheSlotOfAClosedGroupNeverInheritsIt(spacesAvailable: Bool, hiddenTabsReportSpace: Bool, newWindowFirst: Bool) async {
        let fake = await spacesFake(spacesAvailable, hiddenTabsReportSpace)
        await fake.tabGroup(ids: [30, 31], frame: frame, pid: pid, visible: 30, space: 1)
        await fake.showSpace(1)
        await refresh(fake)
        await refresh(fake, advancing: true)
        if newWindowFirst {
            await fake.open(.standard(id: 50, pid: pid, frame: frame, space: 1))
            await refresh(fake)
        }
        await fake.close(30)
        await fake.close(31)
        if !newWindowFirst { await fake.open(.standard(id: 50, pid: pid, frame: frame, space: 1)) }
        for _ in 0..<3 {
            await refresh(fake, advancing: true)
            #expect(await fake.windowInfo(ref(30))?.visibleMemberID != 50)
        }
        #expect(await summary(fake) == [[50, 50, 1]])
        let events = await drain(fake.events)
        #expect(destroyed(events) == [ref(30)])
        #expect(created(events).map(\.window) == [ref(30), ref(50)])
    }

    /// G = 30 + 31 on Space 1 (shown 30) and an untracked same-frame standard window Z (50) on Space 2, after two refreshes.
    private func groupBesideATwinOnSpace2(_ spacesAvailable: Bool, _ hiddenTabsReportSpace: Bool) async -> FakeWindowSystem {
        let fake = await spacesFake(spacesAvailable, hiddenTabsReportSpace)
        await fake.tabGroup(ids: [30, 31], frame: frame, pid: pid, visible: 30, space: 1)
        await fake.open(.standard(id: 50, pid: pid, frame: frame, space: 2))
        await fake.showSpace(1)
        await refresh(fake)
        await refresh(fake, advancing: true)
        return fake
    }

    /// 02-14 known limit 3: the whole group closes in the same update as a switch to Space 2, which shows Z. Z was
    /// offscreen in G's slot at the last refresh, but the switch's notification flags the update, so Z never inherits G.
    @Test(arguments: modes)
    func aSpaceSwitchAsAWholeGroupClosesNeverHandsTheGroupToTheShownTwin(spacesAvailable: Bool, hiddenTabsReportSpace: Bool) async {
        let fake = await groupBesideATwinOnSpace2(spacesAvailable, hiddenTabsReportSpace)
        await fake.close(30)
        await fake.close(31)
        await fake.showSpace(2)
        for _ in 0..<3 {
            await refresh(fake, advancing: true)
            #expect(await fake.windowInfo(ref(30))?.visibleMemberID != 50)
        }
        #expect(await summary(fake) == [[50, 50, 1]])
        let events = await drain(fake.events)
        #expect(destroyed(events) == [ref(30)])
        #expect(created(events).map(\.window) == [ref(30), ref(50)])
    }

    /// Asserts a known limit, NOT desired behaviour: without Space data and without the Space-switch notification
    /// (it reached main only after the ingest of the update that already saw the new Space), the shown twin Z wrongly
    /// inherits the closed group. It shows the race scenario exercises the handoff and that the flag is what closes it.
    /// Invert the expectation to the race's (`[[50, 50, 1]]`, G destroyed) when this residual limit closes.
    @Test func knownLimitWithoutTheSpaceNotificationTheShownTwinTakesTheClosedGroup() async {
        let fake = await groupBesideATwinOnSpace2(false, false)
        await fake.close(30)
        await fake.close(31)
        await fake.showSpace(2, notifies: false)
        for _ in 0..<3 { await refresh(fake, advancing: true) }
        #expect(await summary(fake) == [[30, 50, 1]])
        #expect(destroyed(await drain(fake.events)).isEmpty)
    }
}

/// The fold guard (D-09, WIN-09): a window folded into another window's tab group is reported destroyed only after it
/// stayed a hidden member, unlisted, across two consecutive refreshes in which the group's shown tab did not change.
@Suite struct FoldGuardTests {
    private let clock = ContinuousClock()

    private func snapshot(tabs: Int?, frame: Rect) -> WindowSnapshot {
        WindowSnapshot(
            role: "AXWindow", subrole: "AXStandardWindow", modal: false, main: false, minimized: false, fullScreen: false,
            close: .enabled, minimize: .enabled, zoom: .enabled, fullScreenButton: .enabled,
            tabGroup: tabs.map { TabGroupFact(tabCount: $0) }, frame: frame
        )
    }

    /// One full refresh: `listed` windows with their frame and AXTabs, the other known windows probed unlisted, and
    /// `onScreen`/`offScreen` CG entries at `frame`, except `away` which sits elsewhere.
    private func step(
        _ tracker: inout WindowTracker, listed: [(UInt32, Int?)], onScreen: [UInt32], offScreen: [UInt32], initial: Bool = false,
        spaceChanged: Bool = false, spaces: [UInt32: Set<UInt64>]? = nil
    ) -> [WindowEvent] {
        let away = Rect(x: 800, y: 100, width: 500, height: 300)
        func bounds(_ id: UInt32) -> Rect { id == 20 && listed.contains { $0.0 == 20 && $0.1 == nil } ? away : frame }
        let ids = Set(listed.map(\.0))
        let probed = tracker.knownWindowIDs(pid: pid).filter { !ids.contains($0) }
        let windows = listed.map { WindowObservation(windowID: $0.0, idSource: .axPrivate, read: .success(snapshot(tabs: $0.1, frame: bounds($0.0))), title: "") }
            + probed.map { WindowObservation(windowID: $0, idSource: .axPrivate, read: .success(snapshot(tabs: nil, frame: frame)), title: "", listedInAXWindows: false) }
        let cg = onScreen.map { CGWindowEntry(windowID: $0, pid: pid, bounds: bounds($0), layer: 0, onScreen: true, alpha: 1) }
            + offScreen.map { CGWindowEntry(windowID: $0, pid: pid, bounds: frame, layer: 0, onScreen: false, alpha: 1) }
        return tracker.ingest(AppObservation(pid: pid, bundleID: bundleID, windows: windows), context: ObservationContext(
            cgWindows: cg, initialSweep: initial, now: clock.now, windowSpaces: spaces, spaceChanged: spaceChanged))
    }

    /// A (10) and B (20, elsewhere) tracked; then Merge All Windows makes 20 a hidden tab of 10's three-tab group.
    private func merged() -> WindowTracker {
        var tracker = WindowTracker(settleDelay: .zero)
        _ = step(&tracker, listed: [(10, nil), (20, nil)], onScreen: [10, 20], offScreen: [], initial: true)
        return tracker
    }

    @Test func aFoldedWindowIsDestroyedOnlyOnTheSecondRefreshWithTheSameShownTab() {
        var tracker = merged()
        #expect(destroyed(step(&tracker, listed: [(10, 3)], onScreen: [10], offScreen: [20, 30])).isEmpty)
        #expect(tracker.info(for: ref(20).identity) != nil)
        #expect(destroyed(step(&tracker, listed: [(10, 3)], onScreen: [10], offScreen: [20, 30])) == [ref(20)])
        #expect(destroyed(step(&tracker, listed: [(10, 3)], onScreen: [10], offScreen: [20, 30])).isEmpty)
        #expect(tracker.sortedWindows().map(\.window) == [ref(10)])
    }

    @Test func aShownTabChangeStartsTheCountOver() {
        var tracker = merged()
        #expect(destroyed(step(&tracker, listed: [(10, 3)], onScreen: [10], offScreen: [20, 30])).isEmpty)
        #expect(destroyed(step(&tracker, listed: [(30, 3)], onScreen: [30], offScreen: [10, 20])).isEmpty)
        #expect(tracker.info(for: ref(20).identity) != nil)
        #expect(destroyed(step(&tracker, listed: [(30, 3)], onScreen: [30], offScreen: [10, 20])) == [ref(20)])
    }

    @Test func aFoldedWindowListedAgainStartsTheCountOver() {
        var tracker = merged()
        #expect(destroyed(step(&tracker, listed: [(10, 3)], onScreen: [10], offScreen: [20, 30])).isEmpty)
        // Dragged back out: listed on its own again.
        #expect(destroyed(step(&tracker, listed: [(10, 2), (20, nil)], onScreen: [10, 20], offScreen: [30])).isEmpty)
        #expect(destroyed(step(&tracker, listed: [(10, 3)], onScreen: [10], offScreen: [20, 30])).isEmpty)
        #expect(tracker.info(for: ref(20).identity) != nil)
        #expect(destroyed(step(&tracker, listed: [(10, 3)], onScreen: [10], offScreen: [20, 30])) == [ref(20)])
    }

    /// Review WR-01 (R1): Cmd-T in A (10) lands between a sweep's CG snapshot and the AX read, so that update lists the
    /// new tab 40 while its CG list still shows 10 onscreen and lacks 40. One window throughout, and 10 is never destroyed.
    @Test func cmdTSeenWithAStaleSweepCGListStaysOneWindow() {
        var tracker = WindowTracker(settleDelay: .zero)
        var events = step(&tracker, listed: [(10, nil)], onScreen: [10], offScreen: [], initial: true)
        events += step(&tracker, listed: [(10, nil)], onScreen: [10], offScreen: [])
        events += step(&tracker, listed: [(40, 2)], onScreen: [10], offScreen: [])
        #expect(tracker.sortedWindows().map { [$0.window.windowID, $0.visibleMemberID ?? 0, UInt32($0.tabCount)] } == [[10, 40, 2]])
        for _ in 0..<3 { events += step(&tracker, listed: [(40, 2)], onScreen: [40], offScreen: [10]) }
        for _ in 0..<2 { events += step(&tracker, listed: [(10, 2)], onScreen: [10], offScreen: [40]) }
        #expect(tracker.sortedWindows().map { [$0.window.windowID, $0.visibleMemberID ?? 0, UInt32($0.tabCount)] } == [[10, 10, 2]])
        #expect(destroyed(events).isEmpty)
        #expect(created(events).map(\.window) == [ref(10)])
    }

    /// Without Space data a flagged update (a Space switch) neither counts towards nor completes the fold guard.
    @Test func withoutSpaceDataAFlaggedUpdateNeitherCountsNorDestroysAFold() {
        var tracker = merged()
        #expect(destroyed(step(&tracker, listed: [(10, 3)], onScreen: [10], offScreen: [20, 30])).isEmpty)
        #expect(destroyed(step(&tracker, listed: [(10, 3)], onScreen: [10], offScreen: [20, 30], spaceChanged: true)).isEmpty)
        #expect(tracker.info(for: ref(20).identity) != nil)
        #expect(destroyed(step(&tracker, listed: [(10, 3)], onScreen: [10], offScreen: [20, 30])) == [ref(20)])
    }

    @Test func withSpaceDataAFlaggedUpdateCompletesTheFoldGuardAsUsual() {
        var tracker = merged()
        let spaces: [UInt32: Set<UInt64>] = [10: [1], 20: [1], 30: [1]]
        #expect(destroyed(step(&tracker, listed: [(10, 3)], onScreen: [10], offScreen: [20, 30], spaces: spaces)).isEmpty)
        #expect(destroyed(step(&tracker, listed: [(10, 3)], onScreen: [10], offScreen: [20, 30], spaceChanged: true, spaces: spaces)) == [ref(20)])
    }
}

/// Review GAPS2 (CR-01, WR-01, WR-02, WR-03) through WindowTracker, with per-window reads the fake cannot fail.
@Suite struct TimingLinkTrackerTests {
    private let clock = ContinuousClock()
    private static let away = Rect(x: 900, y: 300, width: 400, height: 300)
    private static let shorter = Rect(x: frame.x, y: frame.y, width: frame.width, height: frame.height - 28)
    private static let taller = Rect(x: frame.x, y: frame.y, width: frame.width, height: frame.height + 28)

    private func snapshot(_ tabs: Int?, _ frame: Rect, minimized: Bool = false) -> WindowSnapshot {
        WindowSnapshot(
            role: "AXWindow", subrole: "AXStandardWindow", modal: false, main: false, minimized: minimized, fullScreen: false,
            close: .enabled, minimize: .enabled, zoom: .enabled, fullScreenButton: .enabled,
            tabGroup: tabs.map { TabGroupFact(tabCount: $0) }, frame: frame
        )
    }

    private func listed(_ id: UInt32, _ tabs: Int?, _ frame: Rect = frame, minimized: Bool = false) -> WindowObservation {
        WindowObservation(windowID: id, idSource: .axPrivate, read: .success(snapshot(tabs, frame, minimized: minimized)), title: "")
    }

    private func unlisted(_ id: UInt32) -> WindowObservation {
        WindowObservation(windowID: id, idSource: .axPrivate, read: .success(snapshot(nil, frame)), title: "", listedInAXWindows: false)
    }

    private func cg(_ id: UInt32, _ bounds: Rect = frame, onScreen: Bool = false) -> CGWindowEntry {
        CGWindowEntry(windowID: id, pid: pid, bounds: bounds, layer: 0, onScreen: onScreen, alpha: 1)
    }

    private func ingest(
        _ tracker: inout WindowTracker, _ windows: [WindowObservation], _ cgWindows: [CGWindowEntry], initial: Bool = false
    ) -> [WindowEvent] {
        tracker.ingest(AppObservation(pid: pid, bundleID: bundleID, windows: windows),
                       context: ObservationContext(cgWindows: cgWindows, initialSweep: initial, now: clock.now))
    }

    private func rows(_ tracker: WindowTracker) -> [[UInt32]] {
        tracker.sortedWindows().map { [$0.window.windowID, $0.visibleMemberID ?? 0, UInt32($0.tabCount)] }
    }

    /// CR-01 (P6): W (10) is minimized (listed, offscreen) beside group B (20 shown, 21 hidden). In the refresh of a
    /// Cmd-T in B, W's read times out (-25204). B keeps the new tab, W keeps its own row, and it stays that way.
    @Test func aCmdTInAGroupBesideAMinimizedWindowWhoseReadTimedOutStaysInTheGroup() {
        var tracker = WindowTracker(settleDelay: .zero)
        let w = listed(10, nil, Self.away, minimized: true)
        let before = [cg(10, Self.away), cg(20, onScreen: true), cg(21)]
        var events = ingest(&tracker, [w, listed(20, 2)], before, initial: true)
        events += ingest(&tracker, [w, listed(20, 2)], before)
        #expect(rows(tracker) == [[10, 10, 1], [20, 20, 2]])
        let timedOut = WindowObservation(windowID: 10, idSource: .axPrivate, read: .failure(.cannotComplete), title: "")
        let after = [cg(10, Self.away), cg(20), cg(21), cg(50, onScreen: true)]
        events += ingest(&tracker, [timedOut, listed(50, 3), unlisted(20)], after)
        #expect(rows(tracker) == [[10, 10, 1], [20, 50, 3]])
        for _ in 0..<4 { events += ingest(&tracker, [w, listed(50, 3), unlisted(20)], after) }
        #expect(rows(tracker) == [[10, 10, 1], [20, 50, 3]])
        #expect(destroyed(events).isEmpty)
        #expect(created(events).map(\.window) == [ref(10), ref(20)])
    }

    /// WR-01: W (5) is minimized at O's (10) frame. Cmd-T in O opens 40 taller, and W's read times out in that refresh.
    /// W is still listed in AXWindows, so it never "went hidden" and O stays the opener.
    @Test func aListedWindowWhoseReadFailedIsNeverTakenAsTheOpener() {
        var tracker = WindowTracker(settleDelay: .zero)
        let w = listed(5, nil, minimized: true)
        let before = [cg(5), cg(10, onScreen: true)]
        var events = ingest(&tracker, [w, listed(10, nil)], before, initial: true)
        events += ingest(&tracker, [w, listed(10, nil)], before)
        let timedOut = WindowObservation(windowID: 5, idSource: .axPrivate, read: .failure(.cannotComplete), title: "")
        let after = [cg(5), cg(10), cg(40, Self.taller, onScreen: true)]
        events += ingest(&tracker, [timedOut, listed(40, 2, Self.taller), unlisted(10)], after)
        for _ in 0..<3 { events += ingest(&tracker, [w, listed(40, 2, Self.taller), unlisted(10)], after) }
        #expect(rows(tracker) == [[5, 5, 1], [10, 40, 2]])
        #expect(destroyed(events).isEmpty)
        #expect(created(events).map(\.window) == [ref(5), ref(10)])
    }

    /// WR-02 (P2T): the sweep sees 219 (AXTabs 3) with 216 and 208 hidden 28 pt shorter, so 219 is the group's only
    /// known member. Cmd-W on 219 shows 216 at the group frame: the same window follows it, nothing closes or opens.
    @Test func cmdWAfterARelaunchKeepsTheGroupsIdentity() {
        var tracker = WindowTracker(settleDelay: .zero)
        var events = ingest(&tracker, [listed(219, 3)], [cg(219, onScreen: true), cg(216, Self.shorter), cg(208, Self.shorter)], initial: true)
        let gone = WindowObservation(windowID: 219, idSource: .axPrivate, read: .failure(.invalidElement), title: "", listedInAXWindows: false)
        for _ in 0..<3 { events += ingest(&tracker, [listed(216, 2), gone], [cg(216, onScreen: true), cg(208, Self.shorter)]) }
        #expect(rows(tracker) == [[219, 216, 2]])
        #expect(destroyed(events).isEmpty)
        #expect(created(events).map(\.window) == [ref(219)])
    }

    /// WR-03 (P3T): `cmdTSeenWithAStaleSweepCGListStaysOneWindow` with Terminal's taller first Cmd-T. One window
    /// throughout, and nothing is destroyed or created.
    @Test func aTallerCmdTSeenWithAStaleSweepCGListStaysOneWindow() {
        var tracker = WindowTracker(settleDelay: .zero)
        var events = ingest(&tracker, [listed(10, nil)], [cg(10, onScreen: true)], initial: true)
        events += ingest(&tracker, [listed(10, nil)], [cg(10, onScreen: true)])
        events += ingest(&tracker, [listed(40, 2, Self.taller), unlisted(10)], [cg(10, onScreen: true)])
        #expect(rows(tracker) == [[10, 40, 2]])
        for _ in 0..<3 { events += ingest(&tracker, [listed(40, 2, Self.taller), unlisted(10)], [cg(10), cg(40, Self.taller, onScreen: true)]) }
        #expect(rows(tracker) == [[10, 40, 2]])
        #expect(destroyed(events).isEmpty)
        #expect(created(events).map(\.window) == [ref(10)])
    }
}

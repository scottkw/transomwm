import TransomEngine
import TransomModel
import TransomTestSupport
import Testing

private let pid: Int32 = 400
private let otherPID: Int32 = 401
private let bundleID = "com.example.close"

private func ref(_ id: UInt32, pid: Int32 = pid) -> WindowRef {
    WindowRef(identity: WindowIdentity(windowID: id, pid: pid, bundleID: pid == otherPID ? "com.example.other" : bundleID))
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

private func destroyed(_ events: [WindowEvent]) -> [WindowRef] {
    events.compactMap { if case .windowDestroyed(let ref) = $0 { ref } else { nil } }
}

private func created(_ events: [WindowEvent]) -> [WindowInfo] {
    events.compactMap { if case .windowCreated(let info) = $0 { info } else { nil } }
}

/// One app with standard windows `ids`, after the initial sweep.
private func fake(_ ids: [UInt32] = [1, 2]) async -> FakeWindowSystem {
    let fake = FakeWindowSystem()
    await fake.addApp(FakeApp(pid: pid, bundleID: bundleID))
    for id in ids { await fake.open(.standard(id: id, pid: pid, frame: Rect(x: Double(id) * 10, y: 25, width: 400, height: 300))) }
    await fake.refreshAll()
    return fake
}

/// Two apps with five windows each, after the initial sweep.
private func tenWindows() async -> FakeWindowSystem {
    let fake = FakeWindowSystem()
    await fake.addApp(FakeApp(pid: pid, bundleID: bundleID))
    await fake.addApp(FakeApp(pid: otherPID, bundleID: "com.example.other"))
    for id in UInt32(1)...10 {
        await fake.open(.standard(id: id, pid: id <= 5 ? pid : otherPID, frame: Rect(x: Double(id) * 10, y: 25, width: 400, height: 300)))
    }
    await fake.refreshAll()
    return fake
}

/// Locks for 5 refresh rounds a second apart, unlocks, and refreshes until every app answers again.
private func blank(_ fake: FakeWindowSystem, gate: Bool, axInvalid: Bool = false) async {
    await fake.setLocked(true, gate: gate, axInvalid: axInvalid)
    for _ in 0..<5 {
        await fake.advance(by: .seconds(1))
        await fake.refreshAll()
    }
    await fake.setLocked(false)
    for _ in 0..<3 {
        await fake.advance(by: .seconds(1))
        await fake.refreshAll()
    }
}

@Suite struct CloseScenarioTests {
    @Test func aClosedWindowIsDestroyedOnce() async {
        let fake = await fake()
        await fake.close(1)
        await fake.refreshAll()
        await fake.refreshAll()
        #expect(destroyed(await drain(fake.events)) == [ref(1)])
        #expect(await fake.windowInfo(ref(1)) == nil)
        #expect(await fake.windowInfo(ref(2)) != nil)
    }

    @Test func anInvalidElementStillInTheCGListIsKeptUntilItLeaves() async {
        let fake = await fake()
        await fake.update(1) { $0.axValid = false }
        await fake.refreshAll()
        #expect(await fake.windowInfo(ref(1)) != nil)
        await fake.update(1) { $0.inCGList = false }
        await fake.refreshAll()
        #expect(destroyed(await drain(fake.events)) == [ref(1)])
    }

    @Test func aHungAppNeverLosesAWindowOverFiveRefreshes() async {
        let fake = await fake()
        await fake.update(1) { $0.axValid = false }
        await fake.setHung(pid: pid, true)
        for _ in 0..<5 {
            await fake.advance(by: .seconds(1))
            await fake.refreshAll()
        }
        #expect(destroyed(await drain(fake.events)).isEmpty)
        #expect(await fake.windowInfo(ref(1)) != nil)
    }

    @Test func aTerminatedAppsWindowsCloseOnlyOnceTheyLeaveTheCGList() async {
        let fake = await fake()
        await fake.terminate(pid: pid)
        await fake.refreshAll()
        #expect(await fake.inventory().windows.count == 2)
        await fake.update(1) { $0.inCGList = false }
        await fake.update(2) { $0.inCGList = false }
        await fake.refreshAll()
        #expect(Set(destroyed(await drain(fake.events))) == [ref(1), ref(2)])
        #expect(await fake.inventory().windows.isEmpty)
    }

    @Test(arguments: [false, true])
    func lockBlankingClosesNothing(axInvalid: Bool) async {
        let fake = await tenWindows()
        await blank(fake, gate: true, axInvalid: axInvalid)
        #expect(destroyed(await drain(fake.events)).isEmpty)
        #expect(await fake.inventory().windows.count == 10)
    }

    @Test func withoutTheGateABlankingThatAnswersInvalidClosesEverything() async {
        let fake = await tenWindows()
        await blank(fake, gate: false, axInvalid: true)
        // They come back as new windows after the unlock: the churn the gate prevents.
        #expect(destroyed(await drain(fake.events)).count == 10, "the gate is what keeps these windows")
    }

    @Test func blankingWithoutTheGateAlsoClosesNothingBecauseEveryReadTimesOut() async {
        let fake = await tenWindows()
        await blank(fake, gate: false)
        #expect(destroyed(await drain(fake.events)).isEmpty)
        #expect(await fake.inventory().windows.count == 10)
    }

    @Test func aReusedIDIsANewWindow() async throws {
        let fake = await fake([100])
        let old = try #require(await fake.windowInfo(ref(100)))
        await fake.close(100)
        await fake.refreshAll()
        await fake.advance(by: .seconds(10))
        await fake.open(.standard(id: 100, pid: pid, frame: Rect(x: 500, y: 25, width: 400, height: 300)))
        await fake.refreshAll()
        await fake.advance(by: .milliseconds(300))
        await fake.refreshAll()
        let events = await drain(fake.events)
        let destroyedAt = try #require(events.firstIndex(of: .windowDestroyed(ref(100))))
        let reborn = try #require(created(Array(events[destroyedAt...])).first)
        #expect(reborn.window == ref(100))
        #expect(reborn.window.creationOrder > old.window.creationOrder)
        #expect(reborn.frame.x == 500)
    }

    @Test func aWindowThatLeftAXWindowsIsProbedAndClosedOnlyOnBothSources() async {
        let fake = await fake()
        await fake.update(1) { $0.listedInAX = false }
        await fake.refreshAll()
        #expect(await fake.windowInfo(ref(1)) != nil)
        await fake.close(1)
        await fake.refreshAll()
        #expect(destroyed(await drain(fake.events)) == [ref(1)])
    }

    @Test func minimisedIsAbsentAndRestoredIsPresentAndFullscreenIsFullscreen() async {
        let fake = await fake([1])
        await fake.update(1) { $0.snapshot.minimized = true }
        await fake.refreshAll()
        await fake.update(1) { $0.snapshot.minimized = false }
        await fake.refreshAll()
        await fake.update(1) { $0.snapshot.fullScreen = true }
        await fake.refreshAll()
        let states = await drain(fake.events).compactMap { if case .windowStateChanged(_, let s) = $0 { s } else { nil } }
        #expect(states == [.absent, .present, .fullscreen])
    }

    /// G-03-9: a lingering CG entry with no Space closes a terminated app's window instead of rechecking forever.
    @Test func aTerminatedAppsGhostWithNoSpaceCloses() async {
        let fake = await spacesFake()
        await fake.terminate(pid: pid)
        #expect(await fake.windowInfo(ref(1)) != nil, "a CG entry on a Space is WindowServer lag")
        await fake.lingerInCG(1, spaces: [])
        await fake.refreshAll()
        #expect(destroyed(await drain(fake.events)).contains(ref(1)))
    }

    /// WR-10: a terminated app's tab group whose members all linger on no Space closes; the ghost tabs never keep it.
    @Test func aTerminatedAppsGhostTabGroupCloses() async {
        let fake = FakeWindowSystem()
        await fake.setSpacesAvailable(true)
        await fake.addApp(FakeApp(pid: pid, bundleID: bundleID))
        await fake.tabGroup(ids: [1, 2], frame: Rect(x: 10, y: 25, width: 400, height: 300), pid: pid, visible: 1, space: 1)
        await fake.refreshAll()
        await fake.terminate(pid: pid)
        await fake.lingerInCG(1, spaces: [])
        await fake.lingerInCG(2, spaces: [])
        await fake.refreshAll()
        #expect(destroyed(await drain(fake.events)).contains(ref(1)))
        #expect(await fake.windowInfo(ref(1)) == nil)
    }

    /// 02-14: a hidden native tab reports no Space; its group stays tracked whole.
    @Test func aHiddenTabWithNoSpaceStaysTrackedOverFiveRefreshes() async throws {
        let fake = FakeWindowSystem()
        await fake.setSpacesAvailable(true)
        await fake.addApp(FakeApp(pid: pid, bundleID: bundleID))
        await fake.tabGroup(ids: [1, 2], frame: Rect(x: 10, y: 25, width: 400, height: 300), pid: pid, visible: 1, space: 1)
        await fake.refreshAll()
        for round in 0..<5 {
            if round == 2 { await fake.selectTab(2) }
            await fake.advance(by: .seconds(1))
            await fake.refreshAll()
        }
        #expect(destroyed(await drain(fake.events)).isEmpty)
        #expect(try #require(await fake.windowInfo(ref(1))).tabCount == 2)
    }

    /// Without the Spaces lookup an empty set is unknown, never empty: the ghost keeps rechecking.
    @Test func withTheLookupOffAGhostKeepsRechecking() async {
        let fake = await fake()
        await fake.lingerInCG(1, spaces: [])
        for _ in 0..<5 {
            await fake.advance(by: .seconds(1))
            await fake.refreshAll()
        }
        #expect(destroyed(await drain(fake.events)).isEmpty)
        #expect(await fake.windowInfo(ref(1)) != nil)
    }

    /// D-23: macOS 27 keeps a closed window its app retains in the CG list, offscreen on its Space. With AX -25202 and
    /// the Space shown, that is the second source: it closes in one refresh.
    @Test func aKeptAliveWindowClosesOnceOffscreenOnTheShownSpace() async {
        let fake = await shownSpaceFake()
        await fake.lingerInCG(1, spaces: [1])
        await fake.refreshAll()
        #expect(destroyed(await drain(fake.events)) == [ref(1)])
        #expect(await fake.windowInfo(ref(2)) != nil)
    }

    /// D-23: the kept-alive window shown again later is a new window.
    @Test func aKeptAliveWindowShownAgainIsANewWindow() async throws {
        let fake = await shownSpaceFake()
        await fake.lingerInCG(1, spaces: [1])
        await fake.refreshAll()
        await fake.update(1) {
            $0.axValid = true
            $0.listedInAX = true
            $0.onScreen = true
        }
        await fake.refreshAll()
        await fake.advance(by: .milliseconds(300))
        await fake.refreshAll()
        let events = await drain(fake.events)
        let destroyedAt = try #require(events.firstIndex(of: .windowDestroyed(ref(1))))
        #expect(created(Array(events[destroyedAt...])).first?.window == ref(1))
    }

    /// An element being rebuilt, or WindowServer lag: invalid in AX but still on screen is kept.
    @Test func anInvalidWindowStillOnScreenIsKept() async {
        let fake = await shownSpaceFake()
        await fake.update(1) {
            $0.axValid = false
            $0.listedInAX = false
        }
        await refreshFiveTimes(fake)
        #expect(destroyed(await drain(fake.events)).isEmpty)
        #expect(await fake.windowInfo(ref(1)) != nil)
    }

    @Test func aKeptAliveGhostOnAnotherSpaceIsKept() async {
        let fake = await shownSpaceFake()
        await fake.lingerInCG(1, spaces: [2])
        await refreshFiveTimes(fake)
        #expect(destroyed(await drain(fake.events)).isEmpty)
        #expect(await fake.windowInfo(ref(1)) != nil)
    }

    /// Two sources: CG alone (offscreen on the shown Space) never closes an AX-valid window.
    @Test func anAXValidWindowOffscreenOnTheShownSpaceIsKept() async {
        let fake = await shownSpaceFake()
        await fake.update(1) {
            $0.listedInAX = false
            $0.onScreen = false
        }
        await refreshFiveTimes(fake)
        #expect(destroyed(await drain(fake.events)).isEmpty)
        #expect(await fake.windowInfo(ref(1)) != nil)
    }
}

private func refreshFiveTimes(_ fake: FakeWindowSystem) async {
    for _ in 0..<5 {
        await fake.advance(by: .seconds(1))
        await fake.refreshAll()
    }
}

/// `spacesFake()` with one display showing Space 1 (D-23).
private func shownSpaceFake() async -> FakeWindowSystem {
    let fake = FakeWindowSystem()
    await fake.setSpacesAvailable(true)
    await fake.setDisplays([DisplayInfo(uuid: "main", frame: Rect(x: 0, y: 0, width: 1440, height: 900),
                                        visibleFrame: Rect(x: 0, y: 25, width: 1440, height: 875), currentSpaceID: 1)])
    await fake.addApp(FakeApp(pid: pid, bundleID: bundleID))
    for id: UInt32 in [1, 2] {
        await fake.open(.standard(id: id, pid: pid, frame: Rect(x: Double(id) * 10, y: 25, width: 400, height: 300), space: 1))
    }
    await fake.refreshAll()
    return fake
}

/// One app with windows 1 and 2 on Space 1, Spaces data on, after the initial sweep.
private func spacesFake() async -> FakeWindowSystem {
    let fake = FakeWindowSystem()
    await fake.setSpacesAvailable(true)
    await fake.addApp(FakeApp(pid: pid, bundleID: bundleID))
    for id: UInt32 in [1, 2] {
        await fake.open(.standard(id: id, pid: pid, frame: Rect(x: Double(id) * 10, y: 25, width: 400, height: 300), space: 1))
    }
    await fake.refreshAll()
    return fake
}

@Suite struct QuickRecheckTests {
    private static let identity = WindowIdentity(windowID: 7, pid: pid, bundleID: bundleID)
    private static let cg = [CGWindowEntry(windowID: 7, pid: pid, bounds: Rect(x: 0, y: 25, width: 400, height: 300), layer: 0, onScreen: true, alpha: 1)]

    private static func app(_ read: Result<WindowSnapshot, AXFailure>) -> AppObservation {
        AppObservation(pid: pid, bundleID: bundleID, windows: [WindowObservation(windowID: 7, idSource: .axPrivate, read: read, title: "")])
    }

    @Test func aRecheckAsksForAQuickRefreshAtMost8TimesInARow() {
        var tracker = WindowTracker()
        let standard = FakeWindow.standard(id: 7, pid: pid, frame: Rect(x: 0, y: 25, width: 400, height: 300)).snapshot
        _ = tracker.ingest(Self.app(.success(standard)), context: ObservationContext(cgWindows: Self.cg, initialSweep: true, now: .now))
        #expect(!tracker.needsQuickRecheck(pid: pid))
        for _ in 0..<WindowTracker.maxQuickRechecks {
            _ = tracker.ingest(Self.app(.failure(.invalidElement)), context: ObservationContext(cgWindows: Self.cg, now: .now))
            #expect(tracker.needsQuickRecheck(pid: pid))
        }
        _ = tracker.ingest(Self.app(.failure(.invalidElement)), context: ObservationContext(cgWindows: Self.cg, now: .now))
        #expect(!tracker.needsQuickRecheck(pid: pid), "a window that never settles is left to the sweep")
        let events = tracker.ingest(Self.app(.failure(.invalidElement)), context: ObservationContext(now: .now))
        #expect(events == [.windowDestroyed(WindowRef(identity: Self.identity))])
        #expect(!tracker.needsQuickRecheck(pid: pid))
    }
}

/// One app with the native tab group 1, 2, 3 (tab 1 shown) on Space 1, one display showing Space 1, after the initial
/// sweep (D-25).
private func tabGroupFake(spaces: Bool = true, hiddenTabsReportSpace: Bool = false) async -> FakeWindowSystem {
    let fake = FakeWindowSystem()
    await fake.setSpacesAvailable(spaces)
    await fake.setHiddenTabsReportSpace(hiddenTabsReportSpace)
    await fake.setDisplays([DisplayInfo(uuid: "main", frame: Rect(x: 0, y: 0, width: 1440, height: 900),
                                        visibleFrame: Rect(x: 0, y: 25, width: 1440, height: 875), currentSpaceID: 1)])
    await fake.addApp(FakeApp(pid: pid, bundleID: bundleID))
    await fake.tabGroup(ids: [1, 2, 3], frame: Rect(x: 10, y: 25, width: 400, height: 300), pid: pid, visible: 1, space: 1)
    await fake.refreshAll()
    return fake
}

/// The CG shape of a whole tab group closed and kept alive: each entry's Spaces while it lingers, or nil once it left
/// the CG list.
private struct KeptAliveShape: Sendable, CustomTestStringConvertible {
    let name: String
    let shown: Set<UInt64>?
    let hidden: Set<UInt64>?
    var testDescription: String { name }

    static let all: [KeptAliveShape] = [
        KeptAliveShape(name: "27.2: shown ordered out, hidden no Space", shown: [1], hidden: []),
        KeptAliveShape(name: "shown ordered out, hidden on the Space", shown: [1], hidden: [1]),
        KeptAliveShape(name: "15.7: all on no Space", shown: [], hidden: []),
        KeptAliveShape(name: "shown no Space, hidden on the Space", shown: [], hidden: [1]),
        KeptAliveShape(name: "shown ordered out, hidden left the CG list", shown: [1], hidden: nil),
        KeptAliveShape(name: "shown left the CG list, hidden no Space", shown: nil, hidden: []),
    ]
}

/// Closed and kept alive (`spaces`), or closed and gone from AX and the CG list (nil).
private func closeKeptAlive(_ fake: FakeWindowSystem, _ id: UInt32, spaces: Set<UInt64>?) async {
    if let spaces {
        await fake.lingerInCG(id, spaces: spaces)
    } else {
        await fake.close(id)
        await fake.update(id) {
            $0.listedInAX = false  // a released window is no longer in AXWindows
            $0.onScreen = false
        }
    }
}

/// D-25: macOS 27 (and 15.7) keep a whole native tab group its app closed and retains in the CG list, its shown tab
/// AX -25202, no tab listed or on screen. Once that holds twice, `settleDelay` apart, the group closes once; a live
/// group's hidden tabs, a Cmd-W's next tab, a minimised group, a hidden app and the lookup off never close one.
@Suite struct KeptAliveTabGroupTests {
    @Test(arguments: KeptAliveShape.all)
    fileprivate func aKeptAliveTabGroupClosesOnceAfterTheSettleDelay(shape: KeptAliveShape) async {
        let fake = await tabGroupFake()
        await closeKeptAlive(fake, 1, spaces: shape.shown)
        await closeKeptAlive(fake, 2, spaces: shape.hidden)
        await closeKeptAlive(fake, 3, spaces: shape.hidden)
        await fake.refreshAll()
        #expect(await fake.windowInfo(ref(1)) != nil, "closed before settleDelay")
        await fake.advance(by: .milliseconds(300))
        await fake.refreshAll()
        #expect(await fake.windowInfo(ref(1)) == nil)
        await refreshFiveTimes(fake)
        let events = await drain(fake.events)
        #expect(destroyed(events) == [ref(1)])
        #expect(created(events).map(\.window) == [ref(1)])
    }

    @Test func aKeptAliveTabGroupClosedOnAnotherSpaceWaitsForItsSpace() async {
        let fake = await tabGroupFake()
        await fake.showSpace(2)
        await fake.refreshAll()
        await fake.lingerInCG(1, spaces: [1])
        await fake.lingerInCG(2, spaces: [])
        await fake.lingerInCG(3, spaces: [])
        await refreshFiveTimes(fake)
        #expect(await fake.windowInfo(ref(1)) != nil, "closed while its Space was not shown")
        await fake.showSpace(1)
        await fake.refreshAll()
        await fake.advance(by: .milliseconds(300))
        await fake.refreshAll()
        #expect(await fake.windowInfo(ref(1)) == nil)
        #expect(destroyed(await drain(fake.events)) == [ref(1)])
    }

    /// 27.2 (`.build/09-30-tabs-vm27.log`): the first refresh after the close still sees the shown tab on screen in
    /// CG. The group is rechecked, never decided absent, so a refresh follows and the group closes within 1 s.
    @Test func aKeptAliveTabGroupStillOnScreenAtTheFirstRefreshIsRechecked() async throws {
        let fake = await tabGroupFake()
        await fake.lingerInCG(1, spaces: [1])
        await fake.lingerInCG(2, spaces: [])
        await fake.lingerInCG(3, spaces: [])
        await fake.update(1) { $0.onScreen = true }
        await fake.refreshAll()
        #expect(await fake.needsQuickRecheck(pid: pid), "no follow-up refresh was asked for")
        #expect(try #require(await fake.windowInfo(ref(1))).state == .present)
        await fake.update(1) { $0.onScreen = false }
        await fake.advance(by: .milliseconds(250))
        await fake.refreshAll()
        #expect(await fake.windowInfo(ref(1)) != nil, "closed before the look held settleDelay")
        #expect(await fake.needsQuickRecheck(pid: pid))
        await fake.advance(by: .milliseconds(250))
        await fake.refreshAll()
        #expect(await fake.windowInfo(ref(1)) == nil)
        #expect(destroyed(await drain(fake.events)) == [ref(1)])
    }

    /// The transient AppKit may show after a Cmd-W: the shown tab is gone before the next tab is listed.
    @Test func cmdWInAKeptAliveTabGroupFollowsTheNextTab() async throws {
        let fake = await tabGroupFake()
        await fake.lingerInCG(1, spaces: [1])
        await fake.refreshAll()
        await fake.selectTab(2)
        await fake.advance(by: .milliseconds(300))
        await fake.refreshAll()
        await fake.refreshAll()
        let info = try #require(await fake.windowInfo(ref(1)))
        #expect(info.visibleMemberID == 2)
        #expect(info.tabCount == 2)
        #expect(info.state == .present)
        let events = await drain(fake.events)
        #expect(destroyed(events).isEmpty)
        #expect(created(events).map(\.window) == [ref(1)])
    }

    @Test(arguments: [false, true])
    func aLiveTabGroupOnTheShownSpaceKeepsItsHiddenTabs(hiddenTabsReportSpace: Bool) async throws {
        let fake = await tabGroupFake(hiddenTabsReportSpace: hiddenTabsReportSpace)
        for round in 0..<5 {
            if round == 2 { await fake.selectTab(2) }
            await fake.advance(by: .seconds(1))
            await fake.refreshAll()
        }
        let info = try #require(await fake.windowInfo(ref(1)))
        #expect(info.tabCount == 3)
        #expect(info.visibleMemberID == 2)
        #expect(destroyed(await drain(fake.events)).isEmpty)
    }

    @Test func aMinimisedTabGroupIsNeverClosed() async throws {
        let fake = await tabGroupFake()
        await fake.update(1) {
            $0.snapshot.minimized = true
            $0.onScreen = false
        }
        await refreshFiveTimes(fake)
        #expect(try #require(await fake.windowInfo(ref(1))).state == .absent)
        #expect(destroyed(await drain(fake.events)).isEmpty)
    }

    /// Pins the not-hidden condition: a hidden app's tabs are neither listed nor on screen.
    @Test func aHiddenAppsTabGroupIsKeptWithItsShownTabGone() async {
        let fake = await tabGroupFake()
        await fake.addApp(FakeApp(pid: pid, bundleID: bundleID, hidden: true))
        await fake.lingerInCG(1, spaces: [1])
        await refreshFiveTimes(fake)
        #expect(await fake.windowInfo(ref(1)) != nil)
        #expect(destroyed(await drain(fake.events)).isEmpty)
    }

    @Test func withTheLookupOffAKeptAliveTabGroupStays() async {
        let fake = await tabGroupFake(spaces: false)
        await fake.lingerInCG(1, spaces: [1])
        await fake.lingerInCG(2, spaces: [])
        await fake.lingerInCG(3, spaces: [])
        await refreshFiveTimes(fake)
        #expect(await fake.windowInfo(ref(1)) != nil)
        #expect(destroyed(await drain(fake.events)).isEmpty)
    }
}

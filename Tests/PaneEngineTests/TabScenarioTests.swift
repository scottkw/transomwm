import PaneEngine
import PaneModel
import PaneTestSupport
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

    @Test func aStandaloneWindowThatGainsATabStaysOneWindowLedByItself() async {
        let fake = FakeWindowSystem()
        await fake.addApp(FakeApp(pid: pid, bundleID: bundleID))
        await fake.open(.standard(id: 10, pid: pid, frame: frame))
        await fake.refreshAll()
        // Cmd-T: AppKit opens tab 11 in window 10's frame and shows it; 10 becomes a hidden tab.
        await fake.update(10) { $0.snapshot.tabGroup = TabGroupFact(tabCount: 2) }
        var tab = FakeWindow.standard(id: 11, pid: pid, frame: frame)
        tab.snapshot.tabGroup = TabGroupFact(tabCount: 2)
        await fake.open(tab)
        await fake.selectTab(11)
        for _ in 0..<3 {
            await fake.advance(by: .milliseconds(250))
            await fake.refreshAll()
        }
        var inventory = await fake.inventory().windows
        #expect(inventory.map(\.window) == [ref(10)])
        #expect(inventory.map(\.tabCount) == [2])
        #expect(inventory.map(\.visibleMemberID) == [11])

        await fake.selectTab(10)
        await fake.refreshAll()
        inventory = await fake.inventory().windows
        #expect(inventory.map(\.window) == [ref(10)])
        #expect(inventory.map(\.visibleMemberID) == [10])
        #expect(inventory.map(\.tabCount) == [2])
        let events = await drain(fake.events)
        #expect(created(events).map(\.window) == [ref(10)])
        #expect(destroyed(events).isEmpty)
    }

    @Test func mergingTwoTrackedWindowsLeavesOneGroupAndReportsTheOtherGone() async {
        let fake = FakeWindowSystem()
        await fake.addApp(FakeApp(pid: pid, bundleID: bundleID))
        await fake.open(.standard(id: 10, pid: pid, frame: frame))
        await fake.open(.standard(id: 20, pid: pid, frame: Rect(x: 800, y: 100, width: 500, height: 300)))
        await fake.refreshAll()
        // Window > Merge All Windows: 20 joins 10's frame as its hidden tab.
        await fake.update(20) { $0.frame = frame }
        for id: UInt32 in [10, 20] { await fake.update(id) { $0.snapshot.tabGroup = TabGroupFact(tabCount: 2) } }
        await fake.selectTab(10)
        await fake.refreshAll()
        await fake.refreshAll()
        let inventory = await fake.inventory().windows
        #expect(inventory.map(\.window) == [ref(10)])
        #expect(inventory.map(\.tabCount) == [2])
        #expect(destroyed(await drain(fake.events)) == [ref(20)])
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

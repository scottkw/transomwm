import Testing
@testable import TransomEngine
import TransomModel
import TransomTestSupport

private let pid: Int32 = 200
private let bundleID = "com.example.fake"
private let frame = Rect(x: 0, y: 25, width: 800, height: 600)

private func ref(_ id: UInt32) -> WindowRef {
    WindowRef(identity: WindowIdentity(windowID: id, pid: pid, bundleID: bundleID))
}

/// A fake with one app and one standard window, refreshed once.
private func fakeWithOneWindow() async -> FakeWindowSystem {
    let fake = FakeWindowSystem()
    await fake.addApp(FakeApp(pid: pid, bundleID: bundleID))
    await fake.open(.standard(id: 42, pid: pid, frame: frame))
    await fake.refreshAll()
    return fake
}

/// The next event, or nil if none arrives within one second (so a missing event fails instead of hanging).
private func nextEvent(_ stream: AsyncStream<WindowEvent>) async -> WindowEvent? {
    await withTaskGroup(of: WindowEvent?.self) { group in
        group.addTask {
            var iterator = stream.makeAsyncIterator()
            return await iterator.next()
        }
        group.addTask {
            try? await Task.sleep(for: .seconds(1))
            return nil
        }
        let first = await group.next() ?? nil
        group.cancelAll()
        return first
    }
}

@Suite struct FakeWindowSystemTests {
    @Test func openingAWindowAndRefreshingYieldsWindowCreated() async throws {
        let fake = await fakeWithOneWindow()
        let event = await nextEvent(fake.events)
        guard case .windowCreated(let info) = event else {
            Issue.record("expected windowCreated, got \(String(describing: event))")
            return
        }
        #expect(info.window == ref(42))
        #expect(info.frame == frame)
    }

    @Test func inventoryListsTheRefreshedWindow() async {
        let fake = await fakeWithOneWindow()
        #expect(await fake.inventory().windows.map(\.window) == [ref(42)])
    }

    @Test func windowInfoReturnsAKnownWindowAndNilForAnUnknownOne() async {
        let fake = await fakeWithOneWindow()
        #expect(await fake.windowInfo(ref(42))?.frame == frame)
        #expect(await fake.windowInfo(ref(43)) == nil)
    }

    @Test func aHungAppAddsNoWindows() async {
        let fake = FakeWindowSystem()
        await fake.addApp(FakeApp(pid: pid, bundleID: bundleID, hung: true))
        await fake.open(.standard(id: 42, pid: pid, frame: frame))
        await fake.refreshAll()
        #expect(await fake.inventory().windows.isEmpty)
    }

    @Test func performRecordsCommandsInOrder() async {
        let fake = FakeWindowSystem()
        let commands: [WindowCommand] = [.setFrame(ref(1), frame), .focus(ref(2)), .raise(ref(1))]
        await fake.perform(Array(commands.prefix(2)))
        await fake.perform(Array(commands.suffix(1)))
        #expect(await fake.performed == commands)
    }

    // MARK: 02-19 (G-02-10): hidden tabs keep the frame they had when hidden, as on macOS 15.7.7

    /// The CG bounds the fake reports for `id` right now.
    private func cgBounds(_ fake: FakeWindowSystem, _ id: UInt32) async -> Rect? {
        await fake.inventory().liveWindows?.first { $0.windowID == id }?.bounds
    }

    @Test func aNewTabOpensAtItsOwnFrameAndTheTabItHidKeepsItsFrame() async {
        let fake = await fakeWithOneWindow()
        let taller = Rect(x: frame.x, y: frame.y, width: frame.width, height: frame.height + 28)
        await fake.newTab(40, in: 42, frame: taller)
        #expect(await cgBounds(fake, 40) == taller)
        #expect(await cgBounds(fake, 42) == frame)
    }

    @Test func aNewTabWithoutAFrameOpensAtTheShownTabsFrame() async {
        let fake = await fakeWithOneWindow()
        let taller = Rect(x: frame.x, y: frame.y, width: frame.width, height: frame.height + 28)
        await fake.newTab(40, in: 42)
        #expect(await cgBounds(fake, 40) == frame, "the host is shown: its frame, as before")
        await fake.newTab(50, in: 42, frame: taller)
        await fake.newTab(60, in: 42)
        #expect(await cgBounds(fake, 60) == taller, "the group's shown tab (50), not the hidden host")
    }

    @Test func showingATabGivesItTheGroupFrameAndLeavesTheOthersAlone() async {
        let fake = await fakeWithOneWindow()
        let taller = Rect(x: frame.x, y: frame.y, width: frame.width, height: frame.height + 28)
        await fake.newTab(40, in: 42, frame: taller)
        await fake.selectTab(42)
        #expect(await cgBounds(fake, 42) == taller)
        #expect(await cgBounds(fake, 40) == taller)
    }

    @Test func aFrameWriteToATabGroupMovesOnlyItsShownTab() async {
        let fake = await fakeWithOneWindow()
        await fake.newTab(40, in: 42)
        await fake.refreshAll()
        let smaller = Rect(x: frame.x, y: frame.y, width: frame.width, height: frame.height - 28)
        await fake.perform([.setFrame(ref(42), smaller)])
        #expect(await cgBounds(fake, 40) == smaller)
        #expect(await cgBounds(fake, 42) == frame)
    }

    @Test func aTabShownFirstInANewGroupKeepsItsFrame() async {
        let fake = await fakeWithOneWindow()
        let other = Rect(x: 300, y: 300, width: 500, height: 300)
        var tab = FakeWindow.standard(id: 43, pid: pid, frame: other)
        tab.tabGroupID = 42
        await fake.open(tab)
        await fake.update(42) { $0.tabGroupID = 42 }
        await fake.selectTab(43)
        #expect(await cgBounds(fake, 43) == other)
        #expect(await cgBounds(fake, 42) == frame)
    }
}

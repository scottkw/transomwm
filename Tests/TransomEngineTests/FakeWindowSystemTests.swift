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
}

import PaneEngine
import PaneModel
import PaneTestSupport
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
private func blank(_ fake: FakeWindowSystem, gate: Bool) async {
    await fake.setLocked(true, gate: gate)
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

    @Test func lockBlankingClosesNothing() async {
        let fake = await tenWindows()
        await blank(fake, gate: true)
        #expect(destroyed(await drain(fake.events)).isEmpty)
        #expect(await fake.inventory().windows.count == 10)
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
}

import PaneEngine
import PaneModel
import PaneTestSupport
import Testing

private let hungPID: Int32 = 301
private let slowPID: Int32 = 302
private let normalPID: Int32 = 303

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

private func responsiveness(_ events: [WindowEvent]) -> [WindowEvent] {
    events.filter { if case .appResponsiveness = $0 { true } else { false } }
}

/// A (to be hung), B (slow, 300 ms) and C (normal), one window each, after the initial sweep.
private func threeApps() async -> FakeWindowSystem {
    let fake = FakeWindowSystem()
    await fake.addApp(FakeApp(pid: hungPID, bundleID: "com.example.hung"))
    await fake.addApp(FakeApp(pid: slowPID, bundleID: "com.example.slow", responseDelay: .milliseconds(300)))
    await fake.addApp(FakeApp(pid: normalPID, bundleID: "com.example.normal"))
    for (id, pid) in [(1, hungPID), (2, slowPID), (3, normalPID)] {
        await fake.open(.standard(id: UInt32(id), pid: pid, frame: Rect(x: Double(id) * 100, y: 25, width: 400, height: 300)))
    }
    await fake.refreshAll()
    await fake.setHung(pid: hungPID, true)
    await fake.refreshAll()
    await fake.refreshAll()
    return fake
}

@Suite struct ResponsivenessScenarioTests {
    @Test func onlyTheHungAppIsDegradedAndItKeepsItsWindow() async {
        let fake = await threeApps()
        let inventory = await fake.inventory()
        #expect(inventory.degradedPIDs == [hungPID])
        #expect(inventory.windows.contains { $0.window.pid == hungPID && $0.window.windowID == 1 })
        #expect(responsiveness(await drain(fake.events)) == [.appResponsiveness(pid: hungPID, degraded: true)])
    }

    @Test func aHungAppDoesNotDelayAnotherAppsNewWindow() async {
        let fake = await threeApps()
        await fake.open(.standard(id: 4, pid: normalPID, frame: Rect(x: 600, y: 25, width: 400, height: 300)))
        await fake.refresh(pid: normalPID)
        await fake.advance(by: .milliseconds(250))
        await fake.refresh(pid: normalPID)
        #expect(await fake.inventory().windows.contains { $0.window.pid == normalPID && $0.window.windowID == 4 })
        #expect(await fake.inventory().degradedPIDs == [hungPID])
    }

    @Test func theHungAppRecoversAtTheFirstProbe2sLater() async {
        let fake = await threeApps()
        await fake.setHung(pid: hungPID, false)
        await fake.advance(by: .milliseconds(1900))
        await fake.refresh(pid: hungPID)
        #expect(await fake.inventory().degradedPIDs == [hungPID], "probed before the 2 s interval")
        await fake.advance(by: .milliseconds(100))
        await fake.refresh(pid: hungPID)
        #expect(await fake.inventory().degradedPIDs.isEmpty)
        #expect(responsiveness(await drain(fake.events)) == [
            .appResponsiveness(pid: hungPID, degraded: true), .appResponsiveness(pid: hungPID, degraded: false),
        ])
    }

    @Test func aRecoveredAppIsRefreshedInFull() async {
        let fake = await threeApps()
        await fake.update(1) { $0.frame = Rect(x: 50, y: 60, width: 400, height: 300) }
        await fake.setHung(pid: hungPID, false)
        await fake.advance(by: .seconds(2))
        await fake.refresh(pid: hungPID)
        let frame = await fake.inventory().windows.first { $0.window.pid == hungPID }?.frame
        #expect(frame == Rect(x: 50, y: 60, width: 400, height: 300))
    }

    @Test func aStillHungProbeKeepsTheAppDegraded() async {
        let fake = await threeApps()
        await fake.advance(by: .seconds(2))
        await fake.refreshAll()
        #expect(await fake.inventory().degradedPIDs == [hungPID])
        #expect(responsiveness(await drain(fake.events)).count == 1)
    }
}

import PaneEngine
import PaneModel
import PaneTestSupport
import Testing

private let excludedPID: Int32 = 900
private let otherPID: Int32 = 901
private let excludedBundle = "com.apple.Safari"
private let otherBundle = "com.example.other"
private let start = Rect(x: 40, y: 80, width: 400, height: 300)
private let target = Rect(x: 300, y: 300, width: 400, height: 300)

private func ref(_ id: UInt32, pid: Int32 = excludedPID, bundleID: String = excludedBundle) -> WindowRef {
    WindowRef(identity: WindowIdentity(windowID: id, pid: pid, bundleID: bundleID))
}

private let otherRef = ref(2, pid: otherPID, bundleID: otherBundle)

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

private func applied(_ events: [WindowEvent]) -> [WindowRef] {
    events.compactMap { if case .frameApplied(let ref, _, _) = $0 { ref } else { nil } }
}

private func changed(_ events: [WindowEvent]) -> [WindowInfo] {
    events.compactMap { if case .windowChanged(let info) = $0 { info } else { nil } }
}

/// Safari (window 1, excluded below) and another app (window 2), after the initial sweep.
private func twoApps() async -> FakeWindowSystem {
    let fake = FakeWindowSystem()
    await fake.addApp(FakeApp(pid: excludedPID, bundleID: excludedBundle))
    await fake.addApp(FakeApp(pid: otherPID, bundleID: otherBundle))
    await fake.open(.standard(id: 1, pid: excludedPID, frame: start))
    await fake.open(.standard(id: 2, pid: otherPID, frame: Rect(x: 500, y: 80, width: 400, height: 300)))
    await fake.refreshAll()
    return fake
}

/// D-12 / WIN-08: an excluded app's windows stay tracked and marked, and no command ever reaches them.
@Suite struct ExclusionScenarioTests {
    @Test func matchingIsCaseInsensitiveAndExact() {
        #expect(ExclusionFilter.isExcluded("com.apple.safari", in: ["com.apple.Safari"]))
        #expect(ExclusionFilter.isExcluded("COM.APPLE.SAFARI", in: ["com.apple.Safari"]))
        #expect(!ExclusionFilter.isExcluded("com.apple.SafariTechnologyPreview", in: ["com.apple.Safari"]))
        #expect(!ExclusionFilter.isExcluded("com.apple", in: ["com.apple.Safari"]))
        #expect(!ExclusionFilter.isExcluded("com.apple.Safari", in: []))
    }

    @Test func admitSplitsCommandsByBundleIDPreservingOrder() {
        let excludedRef = ref(1)
        let commands: [WindowCommand] = [.setFrame(excludedRef, target), .setFrame(otherRef, target), .focus(excludedRef), .raise(otherRef)]
        let split = ExclusionFilter.admit(commands, excluded: ["com.apple.safari"])
        #expect(split.admitted == [.setFrame(otherRef, target), .raise(otherRef)])
        #expect(split.dropped == [.setFrame(excludedRef, target), .focus(excludedRef)])
    }

    @Test func anEmptyListAdmitsEverything() {
        let commands: [WindowCommand] = [.setFrame(ref(1), target), .setHidden(otherRef, true)]
        let split = ExclusionFilter.admit(commands, excluded: [])
        #expect(split.admitted == commands)
        #expect(split.dropped.isEmpty)
    }

    @Test func anExcludedAppsWindowIsNeverMovedButStaysTrackedAndMarked() async throws {
        let fake = await twoApps()
        await fake.setExcluded([excludedBundle])
        await fake.perform([.setFrame(ref(1), target), .setFrame(otherRef, target)])
        let events = await drain(fake.events)
        #expect(applied(events) == [otherRef], "only the other app's window is written")
        #expect(await fake.windows[1]?.frame == start)
        #expect(await fake.dropped == [.setFrame(ref(1), target)])
        let info = try #require(await fake.inventory().windows.first { $0.window == ref(1) })
        #expect(info.isExcluded)
        #expect(info.frame == start)
        let other = try #require(await fake.inventory().windows.first { $0.window == otherRef })
        #expect(!other.isExcluded)
    }

    @Test func excludingAndUnexcludingFlipTheFlagWithWindowChanged() async throws {
        let fake = await twoApps()
        await fake.setExcluded(["COM.APPLE.SAFARI"])
        await fake.setExcluded([])
        await fake.perform([.setFrame(ref(1), target)])
        let events = await drain(fake.events)
        #expect(changed(events).map(\.window) == [ref(1), ref(1)], "one windowChanged per flip, only for the affected app")
        #expect(changed(events).map(\.isExcluded) == [true, false])
        #expect(applied(events) == [ref(1)], "the same setFrame is applied once un-excluded")
        #expect(await fake.windows[1]?.frame == target)
        #expect(await fake.dropped.isEmpty)
    }

    @Test func aWindowOpenedInAnExcludedAppStartsExcluded() async throws {
        let fake = await twoApps()
        await fake.setExcluded([excludedBundle])
        await fake.open(.standard(id: 3, pid: excludedPID, frame: Rect(x: 60, y: 90, width: 300, height: 200)))
        await fake.refreshAll()
        await fake.advance(by: .milliseconds(250))
        await fake.refreshAll()
        let events = await drain(fake.events)
        let created = events.compactMap { if case .windowCreated(let info) = $0, info.window == ref(3) { info } else { nil } }
        #expect(created.map(\.isExcluded) == [true])
    }

    @Test func aFrameHeldForAHungAppIsNeverWrittenOnceTheAppIsExcluded() async {
        let fake = await twoApps()
        await fake.setHung(pid: excludedPID, true)
        await fake.perform([.setFrame(ref(1), target)])
        await fake.setExcluded([excludedBundle])
        await fake.setHung(pid: excludedPID, false)
        await fake.advance(by: .seconds(2))
        await fake.refreshAll()
        #expect(applied(await drain(fake.events)).isEmpty)
        #expect(await fake.windows[1]?.frame == start)
    }

    @Test func settingTheSameListAgainReportsNothing() async {
        let fake = await twoApps()
        await fake.setExcluded([excludedBundle])
        await fake.setExcluded([excludedBundle.lowercased()])
        #expect(changed(await drain(fake.events)).count == 1)
    }
}

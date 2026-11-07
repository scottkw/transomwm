import ApplicationServices
import TransomEngine
import TransomMac
import TransomModel
import TransomPrivate
import Testing

/// The fixture pid's windowCreated and windowDestroyed events since `mark`.
@MainActor private func churn(_ log: EventLog, pid: Int32, since mark: Int) -> [WindowEvent] {
    log.events.dropFirst(mark).filter {
        switch $0 {
        case .windowCreated(let info): info.window.pid == pid
        case .windowDestroyed(let ref): ref.pid == pid
        default: false
        }
    }
}

@MainActor private func axWindows(_ pid: Int32) -> [AXUIElement] {
    var value: CFTypeRef?
    guard AXUIElementCopyAttributeValue(AXUIElementCreateApplication(pid), kAXWindowsAttribute as CFString, &value) == .success
    else { return [] }
    return value as? [AXUIElement] ?? []
}

@MainActor private func windowID(of element: AXUIElement) -> UInt32? {
    var id: CGWindowID = 0
    return AXWindowID.function?(element, &id) == .success ? id : nil
}

/// D-25: one line per tab of its AX, CG and Space facts, so a closed group can be told from a live one.
@MainActor private func printTabFacts(_ phase: String, ids: [UInt32], elements: [UInt32: AXUIElement], pid: Int32) {
    let cg = CGWindowList.snapshot() ?? []
    let spaces = SkyLightSpaces.spaces(of: ids)
    let listed = Set(axWindows(pid).compactMap { windowID(of: $0) })
    let shown = Set(Displays.current().compactMap(\.currentSpaceID))
    for id in ids.sorted() {
        var role: CFTypeRef?
        let ax = elements[id].map { String(AXUIElementCopyAttributeValue($0, kAXRoleAttribute as CFString, &role).rawValue) } ?? "no-element"
        let entry = cg.first { $0.windowID == id }
        print("tab group facts: \(phase) id=\(id) ax=\(ax) listed=\(listed.contains(id)) inCG=\(entry != nil) onScreen=\(String(describing: entry?.onScreen)) spaces=\(String(describing: spaces?[id])) shown=\(shown)")
    }
}

/// WIN-06 / D-08 live: the fixture's three-tab window is one tracked window that follows its visible tab, and a
/// tab switch or a closed tab never looks like a window closing and another opening.
@Suite(.serialized, .enabled(if: IntegrationEnv.trusted, "needs a process with the Accessibility grant"))
@MainActor struct TabsIntegrationTests {
    @Test(.timeLimit(.minutes(1)))
    func aTabbedWindowIsOneWindowThatFollowsItsVisibleTab() async throws {
        let fixture = try await FixtureProcess.launch(["tabs:3"])
        defer { fixture.terminate() }
        let pid = fixture.pid
        let system = AXWindowSystem(appFilter: { candidate, _ in candidate == pid })
        let log = EventLog(system)
        await system.start()

        func tracked() async -> [WindowInfo] {
            await system.inventory().windows.filter { $0.window.pid == pid }
        }
        func churn(since mark: Int) -> [WindowEvent] {
            log.events.dropFirst(mark).filter {
                switch $0 {
                case .windowCreated(let info): info.window.pid == pid
                case .windowDestroyed(let ref): ref.pid == pid
                default: false
                }
            }
        }
        let tabIDs = Set(fixture.windows.map(\.id))
        #expect(tabIDs.count == 3)
        #expect(await waitUntil(timeout: .seconds(2)) { await tracked().first?.tabCount == 3 }, "no tracked window with 3 tabs")
        let windows = await tracked()
        #expect(windows.count == 1, "three tabs were tracked as \(windows.count) windows")
        let group = try #require(windows.first)
        let shown = try #require(group.visibleMemberID)
        #expect(tabIDs.contains(shown))

        // Switch to a tab that is not showing: the same window follows it.
        let target = try #require(fixture.windows.first { $0.id != shown })
        var mark = log.events.count
        _ = try await fixture.send("select-tab \(target.index)")
        let switched = await waitUntil(timeout: .seconds(1)) { await tracked().first?.visibleMemberID == target.id }
        #expect(switched, "visibleMemberID did not follow the selected tab within 1 s")
        #expect(await tracked().map(\.window.identity) == [group.window.identity])
        #expect(churn(since: mark).isEmpty, "a tab switch created or destroyed a window")

        // Close the visible tab: the group lives on with two tabs.
        mark = log.events.count
        _ = try await fixture.send("close \(target.index)")
        let shrunk = await waitUntil(timeout: .seconds(1)) { await tracked().first?.tabCount == 2 }
        #expect(shrunk, "tabCount did not drop to 2 within 1 s of closing the visible tab")
        #expect(await tracked().map(\.window.identity) == [group.window.identity])
        #expect(churn(since: mark).isEmpty, "closing one tab created or destroyed a window")
    }

    /// D-25: an app that closes a whole native tab group and keeps its windows alive (window controllers) must free
    /// the group's tile. Logs every tab's AX, CG and Space facts while the group is live and after the close.
    @Test(.timeLimit(.minutes(1)))
    func aNativeTabGroupItsAppClosesWholeAndKeepsAliveLeaves() async throws {
        let fixture = try await FixtureProcess.launch(["tabs:3"])
        defer { fixture.terminate() }
        let pid = fixture.pid
        let ids = fixture.windows.map(\.id).sorted()
        try #require(ids.count == 3, "the fixture reported \(ids.count) tabs")

        // Each tab's own element, read while it is the selected tab; the last tab stays selected.
        var elements: [UInt32: AXUIElement] = [:]
        for window in fixture.windows.sorted(by: { $0.index < $1.index }) {
            _ = try await fixture.send("select-tab \(window.index)")
            _ = await waitUntil(timeout: .seconds(1)) {
                guard let element = axWindows(pid).first(where: { windowID(of: $0) == window.id }) else { return false }
                elements[window.id] = element
                return true
            }
        }

        let system = AXWindowSystem(appFilter: { candidate, _ in candidate == pid })
        let log = EventLog(system)
        await system.start()
        func tracked() async -> [WindowInfo] {
            await system.inventory().windows.filter { $0.window.pid == pid }
        }
        func printTracked(_ phase: String) async {
            let windows = await tracked()
            let first = windows.first
            print("tab group tracked: \(phase) windows=\(windows.count) state=\(String(describing: first?.state)) tabCount=\(String(describing: first?.tabCount)) visible=\(String(describing: first?.visibleMemberID))")
        }
        let grouped = await waitUntil(timeout: .seconds(2)) {
            let windows = await tracked()
            return windows.count == 1 && windows.first?.tabCount == 3
        }
        try #require(grouped, "no single tracked window with 3 tabs")

        // Live control: a live group's hidden tabs are never closed.
        var mark = log.events.count
        try await Task.sleep(for: .seconds(1))
        printTabFacts("live", ids: ids, elements: elements, pid: pid)
        await printTracked("live")
        let live = await tracked()
        #expect(live.count == 1 && live.first?.tabCount == 3, "the live group did not stay one window with 3 tabs")
        #expect(churn(log, pid: pid, since: mark).isEmpty, "a live tab group created or destroyed a window")

        mark = log.events.count
        let pressed = ContinuousClock.now
        _ = try await fixture.send("close-group \(fixture.windows[0].index)")
        printTabFacts("closed+0", ids: ids, elements: elements, pid: pid)
        let gone = await waitUntil(timeout: .seconds(3)) { await tracked().isEmpty }
        let latency = pressed.duration(to: .now)
        printTabFacts("closed+wait", ids: ids, elements: elements, pid: pid)
        print("tab group close latency: \(latency) gone=\(gone)")
        try await Task.sleep(until: pressed + .seconds(3))
        printTabFacts("closed+3s", ids: ids, elements: elements, pid: pid)
        await printTracked("closed+3s")

        let events = churn(log, pid: pid, since: mark)
        let destroyed = events.filter { if case .windowDestroyed = $0 { true } else { false } }
        let created = events.filter { if case .windowCreated = $0 { true } else { false } }
        #expect(gone, "the closed tab group was still tracked 3 s after its app closed it")
        #expect(latency < Arranger.closeConfirmation, "the group left after \(latency), not within Arranger.closeConfirmation")
        #expect(destroyed.count == 1, "expected one windowDestroyed, got \(destroyed.count)")
        #expect(created.isEmpty, "a former tab came back as a new window: \(created)")
    }

    /// D-25 guard, live: a Cmd-W on the shown tab of a group whose app keeps its windows alive keeps the group; the
    /// next tab follows and nothing is created or destroyed.
    @Test(.timeLimit(.minutes(1)))
    func closingTheShownTabOfAKeptAliveGroupKeepsTheGroup() async throws {
        let fixture = try await FixtureProcess.launch(["tabs:3"])
        defer { fixture.terminate() }
        let pid = fixture.pid
        let system = AXWindowSystem(appFilter: { candidate, _ in candidate == pid })
        let log = EventLog(system)
        await system.start()
        func tracked() async -> [WindowInfo] {
            await system.inventory().windows.filter { $0.window.pid == pid }
        }
        let grouped = await waitUntil(timeout: .seconds(2)) {
            let windows = await tracked()
            return windows.count == 1 && windows.first?.tabCount == 3
        }
        try #require(grouped, "no single tracked window with 3 tabs")
        let group = try #require(await tracked().first)
        let shown = try #require(group.visibleMemberID)
        let target = try #require(fixture.windows.first { $0.id == shown })
        let mark = log.events.count

        _ = try await fixture.send("close-keep \(target.index)")
        let replied = ContinuousClock.now
        var nextListed: Duration?
        while replied.duration(to: .now) < .seconds(1) {
            if axWindows(pid).contains(where: { windowID(of: $0).map { $0 != shown } ?? false }) {
                nextListed = replied.duration(to: .now)
                break
            }
            try await Task.sleep(for: .milliseconds(10))
        }
        if let nextListed {
            print("cmd-w facts: next tab listed after \(Int(nextListed / .milliseconds(1))) ms")
        } else {
            print("cmd-w facts: next tab not listed within 1 s")
        }

        let shrunk = await waitUntil(timeout: .seconds(1)) { await tracked().first?.tabCount == 2 }
        try await Task.sleep(for: .milliseconds(1500))
        let entry = CGWindowList.snapshot()?.first { $0.windowID == shown }
        let spaces = SkyLightSpaces.spaces(of: [shown])?[shown]
        print("cmd-w closed tab: inCG=\(entry != nil) onScreen=\(String(describing: entry?.onScreen)) spaces=\(String(describing: spaces))")

        let after = await tracked()
        #expect(shrunk, "tabCount did not drop to 2 within 1 s of the Cmd-W")
        #expect(after.first?.tabCount == 2, "tabCount is \(String(describing: after.first?.tabCount)), not 2")
        #expect(after.map(\.window.identity) == [group.window.identity], "the group's identity did not stay the only tracked window")
        #expect(after.first?.visibleMemberID != shown, "the closed tab is still the visible member")
        #expect(churn(log, pid: pid, since: mark).isEmpty, "a Cmd-W in a kept-alive group created or destroyed a window")
    }
}

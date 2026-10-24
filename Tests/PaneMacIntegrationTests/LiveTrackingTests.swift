import PaneEngine
import PaneMac
import PaneModel
import Testing

/// Every event an `AXWindowSystem` emits, collected on MainActor.
@MainActor final class EventLog {
    private(set) var events: [WindowEvent] = []
    private var task: Task<Void, Never>?

    init(_ system: AXWindowSystem) {
        task = Task { [weak self] in
            for await event in system.events { self?.events.append(event) }
        }
    }

    deinit { task?.cancel() }

    func wait(_ timeout: Duration, for match: (WindowEvent) -> Bool) async -> Bool {
        await waitUntil(timeout: timeout) { self.events.contains(where: match) }
    }
}

/// A system started before the fixture launches, so everything it learns comes from live tracking.
@MainActor private func liveSystem() async throws -> (AXWindowSystem, EventLog, FixtureProcess) {
    let system = AXWindowSystem(appFilter: { _, bundle in bundle == "unbundled:PaneFixtureApp" })
    let log = EventLog(system)
    await system.start()
    let fixture = try await FixtureProcess.launch(["standard"])
    return (system, log, fixture)
}

/// The fixture's tracked window, once it has appeared (from a fresh launch, within `timeout`).
@MainActor private func trackedWindow(_ system: AXWindowSystem, _ fixture: FixtureProcess, id: UInt32, timeout: Duration = .seconds(2)) async throws -> WindowInfo {
    func find() async -> WindowInfo? {
        await system.inventory().windows.first { $0.window.pid == fixture.pid && $0.window.windowID == id }
    }
    _ = await waitUntil(timeout: timeout) { await find() != nil }
    return try #require(await find(), "window \(id) of pid \(fixture.pid) never tracked")
}

@Suite(.serialized, .enabled(if: IntegrationEnv.trusted, "needs a process with the Accessibility grant"))
@MainActor struct LiveTrackingTests {
    @Test(.timeLimit(.minutes(1)))
    func anAppLaunchedAfterStartIsTrackedWithin2s() async throws {
        let (system, log, fixture) = try await liveSystem()
        defer { fixture.terminate() }
        let printed = try #require(fixture.windows.first)
        _ = try await trackedWindow(system, fixture, id: printed.id)
        let pid = fixture.pid
        #expect(log.events.contains(.appLaunched(pid: pid, bundleID: "unbundled:PaneFixtureApp")))
    }

    @Test(.timeLimit(.minutes(1)))
    func aWindowOpenedLaterIsCreatedWithin1s() async throws {
        let (system, log, fixture) = try await liveSystem()
        defer { fixture.terminate() }
        _ = try await trackedWindow(system, fixture, id: try #require(fixture.windows.first).id)
        let reply = try await fixture.send("open standard")
        let opened = try #require(reply.compactMap(FixtureWindow.init(line:)).first)
        let created = await log.wait(.seconds(1)) {
            if case .windowCreated(let info) = $0 { info.window.windowID == opened.id } else { false }
        }
        #expect(created, "no windowCreated for \(opened.id) within 1 s")
    }

    @Test(.timeLimit(.minutes(1)))
    func aMoveIsReportedWithin1s() async throws {
        let (system, log, fixture) = try await liveSystem()
        defer { fixture.terminate() }
        let info = try await trackedWindow(system, fixture, id: try #require(fixture.windows.first).id)
        _ = try await fixture.send("move 0 300 300")
        let moved = await log.wait(.seconds(1)) {
            guard case .windowMoved(let ref, let frame) = $0, ref.identity == info.window.identity else { return false }
            return abs(frame.x - 300) <= 1 && abs(frame.y - 300) <= 1
        }
        #expect(moved, "no windowMoved to (300, 300) within 1 s")
    }

    @Test(.timeLimit(.minutes(1)))
    func aMinimiseIsReportedAsAbsentWithin1s() async throws {
        let (system, log, fixture) = try await liveSystem()
        defer { fixture.terminate() }
        let info = try await trackedWindow(system, fixture, id: try #require(fixture.windows.first).id)
        _ = try await fixture.send("minimize 0")
        let absent = await log.wait(.seconds(1)) {
            $0 == .windowStateChanged(info.window, .absent)
        }
        #expect(absent, "no windowStateChanged(.absent) within 1 s")
    }

    @Test(.timeLimit(.minutes(1)))
    func theWindowCarriesItsDisplayUUID() async throws {
        let (system, _, fixture) = try await liveSystem()
        defer { fixture.terminate() }
        let info = try await trackedWindow(system, fixture, id: try #require(fixture.windows.first).id)
        let expected = Coordinates.displayUUID(for: info.frame, among: Displays.current())
        #expect(expected != nil)
        #expect(info.displayUUID == expected)
    }

    @Test(.timeLimit(.minutes(1)))
    func quittingTheAppEmitsAppTerminatedWithin2s() async throws {
        let (system, log, fixture) = try await liveSystem()
        _ = try await trackedWindow(system, fixture, id: try #require(fixture.windows.first).id)
        let pid = fixture.pid
        fixture.terminate()
        let terminated = await log.wait(.seconds(2)) { $0 == .appTerminated(pid: pid) }
        #expect(terminated, "no appTerminated within 2 s")
    }
}

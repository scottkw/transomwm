import CoreGraphics
import PaneEngine
@testable import PaneMac
import PaneModel
import Testing

private let multipleDisplays: Bool = {
    var count: UInt32 = 0
    return CGGetActiveDisplayList(0, nil, &count) == .success && count > 1
}()

/// A system tracking only `fixtures`, started, with each fixture's first window tracked.
@MainActor private func tracking(_ fixtures: [FixtureProcess]) async throws -> (AXWindowSystem, EventLog, [PaneModel.WindowRef]) {
    let pids = Set(fixtures.map(\.pid))
    let system = AXWindowSystem(appFilter: { pid, _ in pids.contains(pid) })
    let log = EventLog(system)
    await system.start()
    var refs: [PaneModel.WindowRef] = []
    for fixture in fixtures {
        let id = try #require(fixture.windows.first).id
        func find() async -> WindowInfo? {
            await system.inventory().windows.first { $0.window.pid == fixture.pid && $0.window.windowID == id }
        }
        _ = await waitUntil(timeout: .seconds(2)) { await find() != nil }
        refs.append(try #require(await find(), "window \(id) of pid \(fixture.pid) never tracked").window)
    }
    return (system, log, refs)
}

private func applied(_ events: [WindowEvent], _ ref: PaneModel.WindowRef) -> [(requested: Rect, actual: Rect)] {
    events.compactMap {
        guard case .frameApplied(let window, let requested, let actual) = $0, window == ref else { return nil }
        return (requested, actual)
    }
}

private func near(_ a: Double, _ b: Double) -> Bool { abs(a - b) <= 1 }

private func near(_ a: Rect, _ b: Rect) -> Bool {
    near(a.x, b.x) && near(a.y, b.y) && near(a.width, b.width) && near(a.height, b.height)
}

/// WIN-04 / D-16 / D-17 live: Pane moves and resizes fixture windows (only ones these tests launched), reads every
/// write back, learns a refused size, keeps only the latest of a burst, and a frozen app delays only itself.
@Suite(.serialized, .enabled(if: IntegrationEnv.trusted, "needs a process with the Accessibility grant"))
@MainActor struct FrameWriteIntegrationTests {
    @Test(.timeLimit(.minutes(1)))
    func aWindowMovesAndResizesExactlyAndReadsBack() async throws {
        let fixture = try await FixtureProcess.launch(["standard"])
        defer { fixture.terminate() }
        let (system, log, refs) = try await tracking([fixture])
        let ref = try #require(refs.first)
        let target = Rect(x: 200, y: 200, width: 400, height: 300)

        await system.perform([.setFrame(ref, target)])
        #expect(await log.wait(.seconds(1)) { if case .frameApplied(ref, _, _) = $0 { true } else { false } }, "no frameApplied within 1 s")
        let write = try #require(applied(log.events, ref).first)
        #expect(write.requested == target)
        #expect(near(write.actual, target), "read back \(write.actual)")
        _ = try await fixture.send("list")
        let reported = try #require(fixture.windows.first { $0.id == ref.windowID }).frame
        #expect(near(reported, target), "the fixture reports \(reported)")
    }

    @Test(.timeLimit(.minutes(1)))
    func aRefusedSizeIsReadBackAndLearned() async throws {
        let fixture = try await FixtureProcess.launch(["minsize:250x150"])
        defer { fixture.terminate() }
        let (system, log, refs) = try await tracking([fixture])
        let ref = try #require(refs.first)

        let small = Rect(x: 100, y: 120, width: 100, height: 80)
        await system.perform([.setFrame(ref, small)])
        #expect(await log.wait(.seconds(1)) { if case .frameApplied(ref, _, _) = $0 { true } else { false } }, "no frameApplied within 1 s")
        let actual = try #require(applied(log.events, ref).first).actual
        #expect(near(actual.width, 250) && near(actual.height, 150), "read back \(actual.size)")
        #expect(await system.windowInfo(ref)?.learnedMinimum == nil, "one read-back is not learned")
        // A second refused write that reads back the same size confirms it.
        await system.perform([.setFrame(ref, small)])
        _ = await waitUntil(timeout: .seconds(1)) { applied(log.events, ref).count >= 2 }
        let learned = try #require(await system.windowInfo(ref)?.learnedMinimum)
        #expect(near(learned.width, 250) && near(learned.height, 150), "learned \(learned)")
    }

    @Test(.timeLimit(.minutes(1)))
    func aBurstQueuedWhileTheDrainIsHeldWritesOnlyTheLatest() async throws {
        let fixture = try await FixtureProcess.launch(["standard"])
        defer { fixture.terminate() }
        let id = try #require(fixture.windows.first).id
        let (_, hints) = AsyncStream<AXEventHint>.makeStream()
        // The app thread on its own: its latest-wins slots (T-02-34) are what is under test.
        let thread = AXAppThread(pid: fixture.pid, bundleID: "test.burst", hints: hints)
        defer { thread.stop() }
        let observed = await thread.observe()
        #expect(observed?.windows.contains { $0.windowID == id } == true, "the window is not in the thread's element cache")
        let ref = PaneModel.WindowRef(identity: WindowIdentity(windowID: id, pid: fixture.pid, bundleID: "test.burst"))
        let burst = (0..<10).map { Rect(x: 100 + Double($0) * 10, y: 200, width: 400, height: 300) }

        thread.drainEnabled = false
        for rect in burst { thread.enqueueFrame(windowID: id, rect: rect, ref: ref) }
        let reader = Task {
            var results: [FrameWriteResult] = []
            for await result in thread.frameResults { results.append(result) }
            return results
        }
        thread.drainEnabled = true
        try? await Task.sleep(for: .milliseconds(500))
        reader.cancel()
        let results = await reader.value
        #expect(results.count == 1, "the held burst was written \(results.count) times")
        #expect(results.first?.requested == burst.last)
        _ = try await fixture.send("list")
        let reported = try #require(fixture.windows.first { $0.id == id }).frame
        #expect(near(reported.x, 190), "the fixture ends at \(reported)")
    }

    @Test(.timeLimit(.minutes(1)))
    func aFrozenAppDoesNotDelayAnotherAppsWrite() async throws {
        let frozen = try await FixtureProcess.launch(["standard"])
        defer {
            frozen.resume()
            frozen.terminate()
        }
        let other = try await FixtureProcess.launch(["standard"])
        defer { other.terminate() }
        let (system, log, refs) = try await tracking([frozen, other])
        let otherRef = refs[1]
        let target = Rect(x: 300, y: 250, width: 420, height: 320)

        frozen.stop()
        // A write queued for the frozen app occupies only its own thread.
        await system.perform([.setFrame(refs[0], Rect(x: 50, y: 60, width: 400, height: 300))])
        let clock = ContinuousClock()
        let started = clock.now
        await system.perform([.setFrame(otherRef, target)])
        let written = await log.wait(.seconds(1)) { if case .frameApplied(otherRef, _, _) = $0 { true } else { false } }
        #expect(written, "the other app's write did not complete within 1 s while one app was stopped")
        #expect(started.duration(to: clock.now) < .seconds(1))
        #expect(near(try #require(applied(log.events, otherRef).first).actual, target))
        frozen.resume()
    }

    @Test(.timeLimit(.minutes(1)), .enabled(if: multipleDisplays, "needs two displays; the manual UAT in 02-13 covers it"))
    func aWindowMovedOntoTheSecondDisplayReportsThatDisplay() async throws {
        let fixture = try await FixtureProcess.launch(["standard"])
        defer { fixture.terminate() }
        let (system, _, refs) = try await tracking([fixture])
        let ref = try #require(refs.first)
        let start = try #require(await system.windowInfo(ref)?.displayUUID)
        let second = try #require(await system.inventory().displays.first { $0.uuid != start })
        let visible = second.visibleFrame

        await system.perform([.setFrame(ref, Rect(x: visible.x + 50, y: visible.y + 50, width: 400, height: 300))])
        let moved = await waitUntil(timeout: .seconds(2)) { await system.windowInfo(ref)?.displayUUID == second.uuid }
        #expect(moved, "displayUUID did not change to the second display")
    }
}

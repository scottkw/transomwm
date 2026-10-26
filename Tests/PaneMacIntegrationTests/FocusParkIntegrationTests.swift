import PaneEngine
@testable import PaneMac
import PaneModel
import Testing

/// A system tracking only `fixture`, started, with every one of its windows tracked.
@MainActor private func tracking(_ fixture: FixtureProcess) async throws -> (AXWindowSystem, [PaneModel.WindowRef]) {
    let system = AXWindowSystem(appFilter: { pid, _ in pid == fixture.pid })
    await system.start()
    var refs: [PaneModel.WindowRef] = []
    for window in fixture.windows {
        func find() async -> WindowInfo? {
            await system.inventory().windows.first { $0.window.pid == fixture.pid && $0.window.windowID == window.id }
        }
        _ = await waitUntil(timeout: .seconds(2)) { await find() != nil }
        refs.append(try #require(await find(), "window \(window.id) never tracked").window)
    }
    return (system, refs)
}

private func intersection(_ a: Rect, _ b: Rect) -> (width: Double, height: Double) {
    (max(0, min(a.maxX, b.maxX) - max(a.minX, b.minX)), max(0, min(a.maxY, b.maxY) - max(a.minY, b.minY)))
}

/// Pattern 15 live: park, focus and raise against fixture windows only (never another app).
@Suite(.serialized, .enabled(if: IntegrationEnv.trusted, "needs a process with the Accessibility grant"))
@MainActor struct FocusParkIntegrationTests {
    @Test(.timeLimit(.minutes(1)))
    func parkLeavesOnlyASliverOnScreenAtTheSameSizeAndSetFrameBringsItBack() async throws {
        let fixture = try await FixtureProcess.launch(["standard"])
        defer { fixture.terminate() }
        let (system, refs) = try await tracking(fixture)
        let ref = try #require(refs.first)
        let old = try #require(fixture.windows.first).frame
        let uuid = try #require(await system.windowInfo(ref)?.displayUUID)
        let visible = try #require(await system.inventory().displays.first { $0.uuid == uuid }).visibleFrame

        await system.perform([.park(ref, displayUUID: uuid)])
        var frame = old
        let parked = await waitUntil(timeout: .seconds(2)) {
            guard (try? await fixture.send("list")) != nil, let reported = fixture.windows.first?.frame else { return false }
            frame = reported
            let shown = intersection(reported, visible)
            return shown.width * shown.height < 40 * 40
        }
        #expect(parked, "still on screen at \(frame) inside \(visible)")
        #expect(abs(frame.width - old.width) <= 1 && abs(frame.height - old.height) <= 1, "parking resized it to \(frame.size)")

        await system.perform([.setFrame(ref, old)])
        let back = await waitUntil(timeout: .seconds(2)) {
            guard (try? await fixture.send("list")) != nil, let reported = fixture.windows.first?.frame else { return false }
            return abs(reported.x - old.x) <= 1 && abs(reported.y - old.y) <= 1
        }
        #expect(back, "setFrame did not bring it back to \(old)")
    }
}

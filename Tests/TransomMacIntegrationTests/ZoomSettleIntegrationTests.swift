import AppKit
import Foundation
import TransomEngine
@testable import TransomMac
import TransomModel
import Testing

/// The fixture's listed frame for window `index`.
private func listed(_ fixture: FixtureProcess, _ index: Int) async throws -> Rect? {
    _ = try await fixture.send("list")
    return fixture.windows.first { $0.index == index }?.frame
}

/// D-A / ZOOM-07 live: a zoom on three docked fixture windows animates on the stage, writes once at settle and reveals
/// after the read-backs; zooming home puts every window back in its tile. Fixture windows only, VM only.
@Suite(.serialized, .enabled(if: IntegrationEnv.trusted, "needs a process with the Accessibility grant"))
@MainActor struct ZoomSettleIntegrationTests {
    /// Connects to the window server first. This suite runs beside others in a process with no NSApplication, and a
    /// CoreGraphics call racing the lazy connection on another thread trips `CGS_REQUIRE_INIT` (seen once in the VM).
    init() { _ = NSApplication.shared }

    @Test(.timeLimit(.minutes(1)))
    func zoomToOneWindowAndBackHome() async throws {
        let fixture = try await FixtureProcess.launch(["standard", "standard", "standard"])
        defer { fixture.terminate() }
        let fixturePID = fixture.pid
        let system = AXWindowSystem(appFilter: { pid, _ in pid == fixturePID })
        await system.start()
        let arrange = ArrangeController(system: system, zoomEnabled: true)
        defer { withExtendedLifetime(arrange) {} }  // its events loop ends with it
        await arrange.start()
        try #require(arrange.arranger.zoomEnabled)

        var refs: [TransomModel.WindowRef] = []
        for window in fixture.windows {
            func find() -> TransomModel.WindowRef? {
                arrange.arranger.windows.values.first { $0.window.pid == fixturePID && $0.window.windowID == window.id }?.window
            }
            _ = await waitUntil(timeout: .seconds(3)) { find().map { arrange.arranger.deskKey(of: $0) != nil } ?? false }
            refs.append(try #require(find(), "window \(window.id) never reached a desk"))
        }
        let display = try #require(Displays.current().first)
        let key = try #require(arrange.arranger.deskKey(of: refs[0]))

        // Small windows, so each fits inside the Desktop tile and is never clamped; each docks from the Desktop tile's
        // right edge band (as ArrangeIntegrationTests' minimum-size test does).
        for index in refs.indices { _ = try await fixture.send("resize \(index) 120 120") }
        for (index, ref) in refs.enumerated() {
            try await Task.sleep(for: .milliseconds(500))  // earlier docks' writes and clamps land first
            let desk = try #require(arrange.arranger.world[key])
            let desktop = try #require(try Planner.plan(desk: desk, area: display.visibleFrame, gap: 8, mins: [:]).desktopRect)
            let x = (desktop.minX + desktop.width * 0.8 - 60).rounded(), y = (desktop.midY - 60).rounded()
            _ = try await fixture.send("move \(index) \(Int(x)) \(Int(y))")
            let moved = await waitUntil(timeout: .seconds(2)) {
                arrange.arranger.windows[ref.identity].map { abs($0.frame.x - x) <= 1 && abs($0.frame.y - y) <= 1 } ?? false
            }
            try #require(moved, "the Arranger never saw window \(index) at \(x),\(y)")
            await arrange.dispatch(.dock, focused: ref)
            try #require(arrange.arranger.world[key]?.tree.state(of: ref) == .present, "window \(index) did not dock")
        }
        var tiles: [Rect] = []
        let tiled = await waitUntil(timeout: .seconds(3)) {
            tiles = []
            for index in refs.indices { if let frame = try? await listed(fixture, index) { tiles.append(frame) } }
            return tiles.count == 3 && refs.indices.allSatisfy { i in refs.indices.allSatisfy { j in i == j || !tiles[i].overlaps(tiles[j]) } }
                && tiles.allSatisfy { $0.width > 130 }
        }
        try #require(tiled, "the three fixture windows never tiled: \(tiles)")

        // Zoom in to window 0: it fills the visible frame (less the 8 pt outer gap), the other two are parked.
        let leaf = try #require(arrange.arranger.leafNode(of: refs[0]))
        // In the VM's SSH session NSScreen's visibleFrame may leave out the 25 pt menu bar or not, and can change between
        // the two mid-run (the engine then re-plans in the new area). Vertical checks therefore use the Arranger's current
        // visible frame and allow macOS pushing a window planned under the menu bar down by up to 32 pt; horizontal
        // geometry is exact.
        func visible() -> Rect { arrange.arranger.displays.first { $0.uuid == display.uuid }?.visibleFrame ?? display.visibleFrame }
        func vertical(_ frame: Rect, inset: Double) -> Bool {
            let area = visible()
            return frame.minY >= area.minY + inset - 2 && frame.maxY <= area.maxY + 1 && frame.height >= area.height - 2 * inset - 32
        }
        func fills(_ frame: Rect) -> Bool {
            abs(frame.x - (visible().x + 8)) <= 2 && abs(frame.width - (visible().width - 16)) <= 2 && vertical(frame, inset: 8)
        }
        await arrange.zoom(to: .node(leaf), displayUUID: display.uuid)
        let zoomedIn = await waitUntil(timeout: .seconds(3)) {
            guard let a = try? await listed(fixture, 0), let b = try? await listed(fixture, 1), let c = try? await listed(fixture, 2) else { return false }
            return fills(a) && Recovery.isStranded(b, displays: [display]) && Recovery.isStranded(c, displays: [display])
        }
        let zoomedFrame = try await listed(fixture, 0)
        #expect(zoomedIn, "after zooming in: \(String(describing: zoomedFrame)) vs visible \(visible())")
        #expect(await waitUntil(timeout: .seconds(3)) { arrange.zoomController?.isIdle == true }, "the stage never revealed")
        let settleIn = try #require(arrange.zoomController?.lastSettle)
        print("zoom settle in: \(settleIn.ms) ms, \(settleIn.windows) windows")

        // Zoom home: every window back in its tile.
        await arrange.zoom(to: .home, displayUUID: display.uuid)
        let home = await waitUntil(timeout: .seconds(3)) {
            for index in refs.indices {
                guard let frame = try? await listed(fixture, index), abs(frame.x - tiles[index].x) <= 2,
                    abs(frame.width - tiles[index].width) <= 2, vertical(frame, inset: 8)
                else { return false }
            }
            return true
        }
        var after: [Rect?] = []
        for index in refs.indices { after.append(try await listed(fixture, index)) }
        #expect(home, "after zooming home the windows are at \(after), not back in \(tiles)")
        #expect(await waitUntil(timeout: .seconds(3)) { arrange.zoomController?.isIdle == true }, "the stage never revealed")
        let settleOut = try #require(arrange.zoomController?.lastSettle)
        print("zoom settle home: \(settleOut.ms) ms, \(settleOut.windows) windows")
    }
}

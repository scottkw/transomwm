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

        // Small windows, each docking at the right edge band of the rightmost tile (or as the root of the empty desk).
        for index in refs.indices { _ = try await fixture.send("resize \(index) 120 120") }
        for (index, ref) in refs.enumerated() {
            try await Task.sleep(for: .milliseconds(500))  // earlier docks' writes and clamps land first
            let area = display.visibleFrame
            let x = (area.minX + area.width * 0.9 - 60).rounded(), y = (area.midY - 60).rounded()
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

    /// ZOOM-07 phase gate (04-08): 15 docked fixture windows, 10 rounds of zoom to a 3-window node and back home. Every
    /// window ends within 2 pt of its target (parked ones stranded) and the p95 of the 20 settles is within 500 ms. A
    /// settle is the write path only, from the first AX write to the last read-back (04-SPIKE verdict condition 4):
    /// `lastSettle`, with the capture budget, the animation and the 50 ms redraw delay excluded.
    @Test(.timeLimit(.minutes(3)))
    func fifteenWindowsSettleWithinBudget() async throws {
        let count = 15
        let fixture = try await FixtureProcess.launch(Array(repeating: "standard", count: count))
        defer { fixture.terminate() }
        let fixturePID = fixture.pid
        let system = AXWindowSystem(appFilter: { pid, _ in pid == fixturePID })
        await system.start()
        let arrange = ArrangeController(system: system, zoomEnabled: true)
        defer { withExtendedLifetime(arrange) {} }  // its events loop ends with it
        await arrange.start()
        try #require(arrange.arranger.zoomEnabled)

        var refs: [TransomModel.WindowRef] = []
        for window in fixture.windows.sorted(by: { $0.index < $1.index }) {
            func find() -> TransomModel.WindowRef? {
                arrange.arranger.windows.values.first { $0.window.pid == fixturePID && $0.window.windowID == window.id }?.window
            }
            _ = await waitUntil(timeout: .seconds(3)) { find().map { arrange.arranger.deskKey(of: $0) != nil } ?? false }
            refs.append(try #require(find(), "window \(window.id) never reached a desk"))
        }
        let key = try #require(arrange.arranger.deskKey(of: refs[0]))
        let display = try #require(Displays.current().first { $0.uuid == key.displayUUID })
        await arrange.dispatch(.arrangeAll, focused: refs[0])
        try #require(refs.allSatisfy { arrange.arranger.world[key]?.tree.state(of: $0) == .present }, "Arrange All did not dock all 15")

        func frames() async -> [Rect] {
            _ = try? await fixture.send("list")
            let listed = fixture.windows.sorted { $0.index < $1.index }.map(\.frame)
            return listed.count == count ? listed : []
        }
        func visible() -> Rect { arrange.arranger.displays.first { $0.uuid == display.uuid }?.visibleFrame ?? display.visibleFrame }
        func near(_ a: Rect, _ b: Rect) -> Bool {
            abs(a.x - b.x) <= 2 && abs(a.y - b.y) <= 2 && abs(a.width - b.width) <= 2 && abs(a.height - b.height) <= 2
        }
        /// Each window's target in `view`: its planned frame, or nil when the view parks it.
        func targets(_ view: ViewTarget) throws -> [Rect?] {
            let desk = try #require(arrange.arranger.world[key])
            let plan = try ViewPlanner.plan(desk: desk, view: view, area: visible(), gap: 8, mins: [:])
            return refs.map { plan.frames[$0] }
        }
        func misses(_ view: ViewTarget) async throws -> [String] {
            let wanted = try targets(view), actual = await frames()
            guard !actual.isEmpty else { return ["no list"] }
            return refs.indices.compactMap { i in
                if let target = wanted[i] { return near(actual[i], target) ? nil : "\(i): \(actual[i]) vs \(target)" }
                return Recovery.isStranded(actual[i], displays: [display]) ? nil : "\(i): \(actual[i]) not parked"
            }
        }
        var last: [String] = []
        let tiled = await waitUntil(timeout: .seconds(5)) {
            last = (try? await misses(.home)) ?? ["plan failed"]
            return last.isEmpty
        }
        try #require(tiled, "the 15 windows never reached their home tiles: \(last)")

        // The split holding exactly 3 windows (Arrange All's layout has one); else the smallest holding 2 or more.
        let tree = try #require(arrange.arranger.world[key]?.tree)
        let splits = tree.nodes.compactMap { id, node -> (NodeID, Int)? in
            guard case .split = node, let windows = try? tree.subtree(at: id).windows.count else { return nil }
            return (id, windows)
        }
        let node = try #require(splits.first { $0.1 == 3 } ?? splits.filter { $0.1 >= 2 }.min { $0.1 < $1.1 }, "no split to zoom to")
        print("zooming to \(node.0) holding \(node.1) windows")

        var settles: [Int] = []
        for round in 0..<10 {
            for view in [ViewTarget.node(node.0), .home] {
                await arrange.zoom(to: view, displayUUID: display.uuid)
                try #require(arrange.zoomController?.isIdle == false, "round \(round) \(view): the move never started")
                let revealed = await waitUntil(timeout: .seconds(5)) { arrange.zoomController?.isIdle == true }
                try #require(revealed, "round \(round) \(view): the stage never revealed")
                let settle = try #require(arrange.zoomController?.lastSettle)
                settles.append(settle.ms)
                let placed = await waitUntil(timeout: .seconds(1)) {
                    last = (try? await misses(view)) ?? ["plan failed"]
                    return last.isEmpty
                }
                #expect(placed, "round \(round) \(view): windows off target: \(last)")
                print("settle round \(round) \(view == .home ? "home" : "in"): \(settle.ms) ms, \(settle.windows) writes")
            }
        }
        let sorted = settles.sorted()
        let p50 = sorted[sorted.count / 2], p95 = sorted[Int((Double(sorted.count) * 0.95).rounded(.up)) - 1]
        print("settles \(settles)")
        print("p50 \(p50) ms")
        print("p95 \(p95) ms")
        #expect(settles.count == 20)
        #expect(p95 <= 500, "ZOOM-07: p95 \(p95) ms over the 500 ms write-path budget")
    }
}


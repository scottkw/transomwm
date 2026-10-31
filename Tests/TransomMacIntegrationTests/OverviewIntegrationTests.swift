import AppKit
import Foundation
import TransomEngine
@testable import TransomMac
import TransomModel
import Testing

/// OVER-01 / D-01 / D-02 live: Show Overview opens one panel per display with a tile per fixture window, the windows
/// never move, and Show Overview again or Esc closes it. Fixture windows only, VM only (it posts an Esc key event).
@Suite(.serialized, .enabled(if: IntegrationEnv.trusted, "needs a process with the Accessibility grant"))
@MainActor struct OverviewIntegrationTests {
    /// Connects to the window server first (see ZoomSettleIntegrationTests), as an agent app like Transom (LSUIElement).
    init() {
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.accessory)
    }

    @Test(.timeLimit(.minutes(1)))
    func overviewOpensPerDisplayAndCloses() async throws {
        let fixture = try await FixtureProcess.launch(["standard", "standard"])
        defer { fixture.terminate() }
        let fixturePID = fixture.pid
        let system = AXWindowSystem(appFilter: { pid, _ in pid == fixturePID })
        await system.start()
        let arrange = ArrangeController(system: system, zoomEnabled: true)
        defer { withExtendedLifetime(arrange) {} }  // its events loop ends with it
        await arrange.start()

        let tracked = await waitUntil(timeout: .seconds(3)) {
            fixture.windows.allSatisfy { window in arrange.arranger.windows.values.contains { $0.window.pid == fixturePID && $0.window.windowID == window.id } }
        }
        try #require(tracked, "the fixture windows were never tracked")
        func frames() async throws -> [Rect] {
            _ = try await fixture.send("list")
            return fixture.windows.sorted { $0.index < $1.index }.map(\.frame)
        }
        let before = try await frames()
        let main = try #require(arrange.arranger.displays.first?.uuid)
        let displayCount = arrange.arranger.displays.count

        await arrange.dispatch(.camera(.overview))
        let opened = await waitUntil(timeout: .seconds(2)) {
            arrange.overviewController?.isOpen == true && arrange.overviewController?.openPanels.count == displayCount
        }
        let overview = try #require(arrange.overviewController)
        try #require(opened, "the overview never opened on \(displayCount) displays: \(overview.openPanels)")
        #expect(overview.tileCount(display: main) >= 2)
        try await Task.sleep(for: .milliseconds(400))  // past the 250 ms move
        #expect(try await frames() == before, "the real windows moved while the overview was open")

        await arrange.dispatch(.camera(.overview))
        #expect(!overview.isOpen, "Show Overview again did not close it")

        await arrange.dispatch(.camera(.overview))
        try #require(await waitUntil(timeout: .seconds(2)) { overview.openPanels.count == displayCount }, "the overview did not open again")
        for down in [true, false] {
            CGEvent(keyboardEventSource: nil, virtualKey: 53, keyDown: down)?.post(tap: .cghidEventTap)  // Esc
        }
        // Esc reaches the overview's key panel: this process has no running NSApplication, so the test pumps AppKit's queue.
        let escaped = await waitUntil(timeout: .seconds(2)) {
            dispatchAppKitEvents()
            return !overview.isOpen
        }
        #expect(escaped, "Esc did not close the overview")
        try await Task.sleep(for: .milliseconds(400))
        #expect(try await frames() == before, "the real windows moved")
    }

    /// Surface 1 Motion, "Pick a parked or collapsed window": with the display zoomed in to window 0, picking parked
    /// window 1 in the overview closes it, then the camera frames window 1's leaf and focuses it at settle.
    @Test(.timeLimit(.minutes(1)))
    func pickParkedWindowFramesItsLeaf() async throws {
        let fixture = try await FixtureProcess.launch(["standard", "standard", "standard"])
        defer { fixture.terminate() }
        let fixturePID = fixture.pid
        let system = AXWindowSystem(appFilter: { pid, _ in pid == fixturePID })
        await system.start()
        let arrange = ArrangeController(system: system, zoomEnabled: true)
        defer { withExtendedLifetime(arrange) {} }
        await arrange.start()
        /// The overview's panel has a tracking area: AppKit events go through the nested pump (06-08).
        func pump(timeout: Duration = .seconds(3), until done: () async -> Bool) async -> Bool {
            await waitUntil(timeout: timeout) {
                dispatchAppKitEvents()
                return await done()
            }
        }
        func listed(_ index: Int) async -> Rect? {
            _ = try? await fixture.send("list")
            return fixture.windows.first { $0.index == index }?.frame
        }

        var refs: [TransomModel.WindowRef] = []
        for window in fixture.windows.sorted(by: { $0.index < $1.index }) {
            func find() -> TransomModel.WindowRef? {
                arrange.arranger.windows.values.first { $0.window.pid == fixturePID && $0.window.windowID == window.id }?.window
            }
            _ = await waitUntil(timeout: .seconds(3)) { find().map { arrange.arranger.deskKey(of: $0) != nil } ?? false }
            refs.append(try #require(find(), "window \(window.id) never reached a desk"))
        }
        let display = try #require(Displays.current().first)
        let key = try #require(arrange.arranger.deskKey(of: refs[0]))
        // Docked as in ZoomSettleIntegrationTests: small, each from the Desktop tile's right edge band.
        for index in refs.indices { _ = try await fixture.send("resize \(index) 120 120") }
        for (index, ref) in refs.enumerated() {
            try await Task.sleep(for: .milliseconds(500))
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
        try await Task.sleep(for: .milliseconds(500))

        // Frame window 0 (Frame Focused Window): windows 1 and 2 park.
        await arrange.camera(.frameWindow, displayUUID: display.uuid, focused: refs[0], pointer: Point(x: display.frame.midX, y: display.frame.midY))
        let parked = await waitUntil(timeout: .seconds(3)) {
            guard arrange.zoomController?.isIdle == true, let b = await listed(1), let c = await listed(2) else { return false }
            return Recovery.isStranded(b, displays: [display]) && Recovery.isStranded(c, displays: [display])
        }
        try #require(parked, "framing window 0 did not park windows 1 and 2")

        await arrange.dispatch(.camera(.overview))
        let overview = try #require(arrange.overviewController)
        let opened = await pump { overview.isOpen && overview.tileCount(display: display.uuid) == 3 }
        try #require(opened, "the overview did not show the three windows: \(overview.tileCount(display: display.uuid)) tiles")
        try await Task.sleep(for: .milliseconds(300))  // past the open move

        overview.pick(.tile(refs[1]))
        #expect(!overview.isOpen, "the pick did not close the overview")
        let leaf = try #require(arrange.arranger.leafNode(of: refs[1]))
        let tree = try #require(arrange.arranger.world[key]?.tree)
        let target = Navigator.target(leaf, in: tree)
        func visible() -> Rect { arrange.arranger.displays.first { $0.uuid == display.uuid }?.visibleFrame ?? display.visibleFrame }
        // A framed leaf fills the visible frame less the 8 pt outer gap (vertical slack as in ZoomSettleIntegrationTests).
        func fills(_ frame: Rect) -> Bool {
            let area = visible()
            return abs(frame.x - (area.x + 8)) <= 2 && abs(frame.width - (area.width - 16)) <= 2 && frame.minY >= area.minY + 6
                && frame.maxY <= area.maxY + 1 && frame.height >= area.height - 16 - 32
        }
        let framed = await pump(timeout: .seconds(4)) {
            guard arrange.arranger.view(on: display.uuid) == target, arrange.zoomController?.isIdle == true, let b = await listed(1) else { return false }
            return fills(b)
        }
        let frame = await listed(1)
        #expect(framed, "window 1 was not framed: \(String(describing: frame)) vs visible \(visible()), view \(arrange.arranger.view(on: display.uuid))")
        let focused = await pump { ((try? await fixture.send("frontmost")) ?? []).contains("frontmost index=1") }
        #expect(focused, "window 1 did not get focus at settle")
    }
}

import AppKit
import Foundation
import TransomEngine
@testable import TransomMac
import TransomModel
import Testing

/// Within 2 pt on every side (the fixture reports whole points).
private func near(_ a: Rect, _ b: Rect) -> Bool {
    abs(a.x - b.x) <= 2 && abs(a.y - b.y) <= 2 && abs(a.width - b.width) <= 2 && abs(a.height - b.height) <= 2
}

/// The fixture's windows as the system tracks them, once all of `fixture.windows` are present with a title.
@MainActor private func trackedWithTitles(_ system: AXWindowSystem, _ fixture: FixtureProcess) async throws -> [WindowInfo] {
    let ids = fixture.windows.sorted { $0.index < $1.index }.map(\.id)
    var found: [WindowInfo] = []
    _ = await waitUntil(timeout: .seconds(3)) {
        let inventory = await system.inventory()
        guard inventory.initialRefreshComplete else { return false }
        found = ids.compactMap { id in inventory.windows.first { $0.window.windowID == id && $0.state == .present } }
        return found.count == ids.count && found.allSatisfy { !$0.window.titleHint.isEmpty }
    }
    try #require(found.count == ids.count && found.allSatisfy { !$0.window.titleHint.isEmpty }, "the fixture windows were never tracked with titles")
    return found
}

/// VIEW-04, D-10, D-11 live: an app relaunched under a new pid while Transom was not running gets each window back
/// into its own tile, matched by the titles layout.json kept. Fixture windows only; the store is a temporary
/// directory, never the user's real layout.json.
@Suite(.serialized, .enabled(if: IntegrationEnv.trusted, "needs a process with the Accessibility grant"))
@MainActor struct RematchIntegrationTests {
    @Test(.timeLimit(.minutes(1)))
    func aRelaunchedAppGetsItsTilesBackAfterATransomRelaunch() async throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: "transom-rematch-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: directory) }

        // Session 1, built headlessly: [Fixture 0 | Fixture 1], saved with titles.
        let first = try await FixtureProcess.launch(["standard", "standard"])
        defer { first.terminate() }
        let firstPID = first.pid
        let firstSystem = AXWindowSystem(appFilter: { pid, _ in pid == firstPID })
        await firstSystem.start()
        let windows = try await trackedWithTitles(firstSystem, first).map(\.window)
        try #require(windows.map(\.titleHint) == ["Fixture 0", "Fixture 1"], "unexpected fixture titles \(windows.map(\.titleHint))")
        var builder = Arranger()
        _ = builder.handle(.inventory(await firstSystem.inventory()), now: .now)
        let key = try #require(builder.deskKey(of: windows[0]))
        var world = builder.world, history = UndoHistory()
        try world.edit(key, history: &history) { desk, ids throws(LayoutError) in
            for window in windows where desk.desktop.contains(window) { try desk.desktop.remove(window) }
            try desk.tree.applyDrop(.layoutEdge(.right), window: windows[0], ids: &ids)
            guard let leaf = desk.tree.leaf(containing: windows[0]) else { throw .windowNotFound(windows[0]) }
            try desk.tree.insert(windows[1], at: .right, of: leaf, ids: &ids)
        }
        try #require(world[key]?.tree.windows == windows)
        try LayoutStore(directory: directory).save(LayoutFile(world: world, homeFrames: [:], session: SessionRecord(cleanExit: true, launchedAt: Date())))
        first.terminate()

        // The app relaunches (new pid, new window IDs, same titles), then Transom does.
        let second = try await FixtureProcess.launch(["standard", "standard"])
        defer { second.terminate() }
        let secondPID = second.pid
        try #require(secondPID != firstPID)
        let system = AXWindowSystem(appFilter: { pid, _ in pid == secondPID })
        await system.start()
        _ = try await trackedWithTitles(system, second)
        let arrange = ArrangeController(system: system, store: LayoutStore(directory: directory))
        defer { withExtendedLifetime(arrange) {} }  // its events loop ends with it
        await arrange.start()

        let visible = try #require(Displays.current().first { $0.uuid == key.displayUUID }).visibleFrame
        let tiles = try Planner.plan(desk: try #require(world[key]), area: visible, gap: arrange.arranger.gap, mins: [:]).frames
        let wanted = [try #require(tiles[windows[0]]), try #require(tiles[windows[1]])]
        var frames: [Rect?] = []
        let back = await waitUntil(timeout: .seconds(5)) {
            _ = try? await second.send("list")
            frames = (0..<2).map { index in second.windows.first { $0.index == index }?.frame }
            return zip(frames, wanted).allSatisfy { frame, tile in frame.map { near($0, tile) } ?? false }
        }
        #expect(back, "Fixture 0 / Fixture 1 are at \(frames), not their tiles \(wanted)")
        let docked = arrange.arranger.world[key]?.tree.windows ?? []
        #expect(docked.map(\.pid) == [secondPID, secondPID], "the relaunched windows are not docked: \(docked)")
    }

    /// D-11, D-12a live: an app quits while Transom runs, so its two docked tiles stay reserved and the third tile keeps
    /// its size; it relaunches, and each window goes back into its own tile. Prints the order the events arrived in
    /// (RESEARCH Assumption A1). Fixture windows only; the store is a temporary directory.
    @Test(.timeLimit(.minutes(1)))
    func quitAndRelaunchRefillsBothTiles() async throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: "transom-quit-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: directory) }

        let first = try await FixtureProcess.launch(["standard", "standard"])
        defer { first.terminate() }
        let keeper = try await FixtureProcess.launch(["standard"])
        defer { keeper.terminate() }
        let firstPID = first.pid
        // By bundle, not by pid: the relaunched fixture must reach the tracker as a launch.
        let system = AXWindowSystem(appFilter: { _, bundle in bundle == "unbundled:TransomFixtureApp" })
        await system.start()
        let windows = try await trackedWithTitles(system, first).map(\.window)
        let third = try await trackedWithTitles(system, keeper)[0].window
        let arrange = ArrangeController(system: system, store: LayoutStore(directory: directory))
        defer { withExtendedLifetime(arrange) {} }
        await arrange.start()
        var order: [String] = []
        arrange.onEvent = { event in
            switch event {
            case .appTerminated(let pid) where pid == firstPID: order.append("appTerminated")
            case .windowDestroyed(let window) where window.pid == firstPID: order.append("windowDestroyed \(window.windowID)")
            default: break
            }
        }
        for window in windows + [third] {
            await arrange.dispatch(.dock, focused: window)
            try #require(arrange.arranger.deskKey(of: window).flatMap { arrange.arranger.world[$0]?.tree.state(of: window) } == .present, "\(window) did not dock")
        }
        func current(_ fixture: FixtureProcess, _ index: Int) async -> Rect? {
            _ = try? await fixture.send("list")
            return fixture.windows.first { $0.index == index }?.frame
        }
        let key = try #require(arrange.arranger.deskKey(of: windows[0]))
        let visible = try #require(Displays.current().first { $0.uuid == key.displayUUID }).visibleFrame
        let tiles = try Planner.plan(desk: try #require(arrange.arranger.world[key]), area: visible, gap: arrange.arranger.gap, mins: [:]).frames
        let wanted = [try #require(tiles[windows[0]]), try #require(tiles[windows[1]])]
        let thirdTile = try #require(tiles[third])
        let settled = await waitUntil(timeout: .seconds(3)) {
            let frames = [await current(first, 0), await current(first, 1), await current(keeper, 0)]
            return zip(frames, wanted + [thirdTile]).allSatisfy { frame, tile in frame.map { near($0, tile) } ?? false }
        }
        try #require(settled, "the three windows never reached their tiles")

        _ = try await first.send("quit")
        let held = await waitUntil(timeout: .seconds(2)) { windows.allSatisfy(arrange.arranger.isPlaceholder) }
        print("A1 event order on quit: \(order)")
        #expect(held, "the tiles are not reserved after the quit; events: \(order)")
        #expect(await current(keeper, 0).map { near($0, thirdTile) } == true, "the third tile changed")

        let second = try await FixtureProcess.launch(["standard", "standard"])
        defer { second.terminate() }
        var frames: [Rect?] = []
        let back = await waitUntil(timeout: .seconds(5)) {
            frames = [await current(second, 0), await current(second, 1)]
            return zip(frames, wanted).allSatisfy { frame, tile in frame.map { near($0, tile) } ?? false }
        }
        #expect(back, "Fixture 0 / Fixture 1 are at \(frames), not their tiles \(wanted)")
        #expect(arrange.arranger.placeholderCount == 0)
        #expect(await current(keeper, 0).map { near($0, thirdTile) } == true, "the third tile changed")
    }

    /// D-13 live (VM only: it posts a click): each tile of a quit app shows a click-through panel behind real windows. A
    /// fixture window opened over one tile stays above its panel. A click through the other panel reaches the fixture
    /// window sent behind it, then, with that window closed, Finder's desktop, and leaves this process inactive. By pid,
    /// so the second fixture stays untracked and fills nothing.
    @Test(.timeLimit(.minutes(1)), .enabled(if: IntegrationEnv.inVM, "VM only: posts a click"))
    func aPlaceholderIsClickThroughAndBehindRealWindows() async throws {
        _ = NSApplication.shared
        let directory = FileManager.default.temporaryDirectory.appending(path: "transom-panel-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: directory) }
        let first = try await FixtureProcess.launch(["standard", "standard"])
        defer { first.terminate() }
        let firstPID = first.pid
        let system = AXWindowSystem(appFilter: { pid, _ in pid == firstPID })
        await system.start()
        let windows = try await trackedWithTitles(system, first).map(\.window)
        let arrange = ArrangeController(system: system, store: LayoutStore(directory: directory))
        defer { withExtendedLifetime(arrange) {} }
        await arrange.start()
        for window in windows { await arrange.dispatch(.dock, focused: window) }
        let key = try #require(arrange.arranger.deskKey(of: windows[0]))
        let visible = try #require(Displays.current().first { $0.uuid == key.displayUUID }).visibleFrame
        let plan = try Planner.plan(desk: try #require(arrange.arranger.world[key]), area: visible, gap: arrange.arranger.gap, mins: [:]).frames
        let wanted = [try #require(plan[windows[0]]), try #require(plan[windows[1]])]

        _ = try await first.send("quit")
        #expect(await waitUntil(timeout: .seconds(2)) { windows.allSatisfy(arrange.arranger.isPlaceholder) }, "the tiles are not reserved after the quit")
        let primaryHeight = try #require(NSScreen.screens.first?.frame.height)
        var panels: [NSWindow] = []
        let drawn = await waitUntil(timeout: .seconds(2)) {
            let numbers = arrange.placeholderPanels.windowNumbers
            panels = wanted.compactMap { tile in
                let rect = Coordinates.appKit(fromTopLeft: tile, primaryHeight: primaryHeight)
                return NSApp.windows.first { window in
                    numbers.contains(window.windowNumber) && window.isVisible
                        && near(Rect(x: window.frame.minX, y: window.frame.minY, width: window.frame.width, height: window.frame.height), rect)
                }
            }
            return panels.count == 2
        }
        try #require(drawn, "no panel at each of \(wanted): \(NSApp.windows.map(\.frame))")
        for panel in panels {
            #expect(panel.ignoresMouseEvents)
            #expect(panel.level == .normal)
            #expect(!panel.canBecomeKey && !panel.canBecomeMain)
        }

        let over = try await FixtureProcess.launch(["standard", "standard"])
        defer { over.terminate() }
        _ = try await over.send("move 0 \(Int(wanted[1].x) + 40) \(Int(wanted[1].y) + 40)")
        _ = try await over.send("move 1 \(Int(wanted[0].x)) \(Int(wanted[0].y))")
        _ = try await over.send("resize 1 \(Int(wanted[0].width)) \(Int(wanted[0].height))")
        _ = try await over.send("order-back 1")
        _ = try await over.send("list")
        let above = try #require(over.windows.first { $0.index == 0 }?.id), below = try #require(over.windows.first { $0.index == 1 }?.id)
        var list: [CGWindowEntry] = []
        let ordered = await waitUntil(timeout: .seconds(2)) {
            list = CGWindowList.onScreenFrontToBack() ?? []
            let order = list.map(\.windowID)
            guard let top = order.firstIndex(of: above), let second = order.firstIndex(of: UInt32(panels[1].windowNumber)),
                let first = order.firstIndex(of: UInt32(panels[0].windowNumber)), let bottom = order.firstIndex(of: below)
            else { return false }
            return top < second && first < bottom
        }
        #expect(ordered, "want \(above) above panel \(panels[1].windowNumber) and \(below) below panel \(panels[0].windowNumber), got \(list.map(\.windowID))")

        // Where only the panel and the window below it are, clear of the guest's own windows and of their resize margins,
        // and below the title bar: on an empty guest the first clear point would be that window's close button.
        let waiting = arrange.placeholderPanels.windowNumbers
        let grid = stride(from: wanted[0].minY + 40, to: wanted[0].maxY - 16, by: 4).lazy.flatMap { y in
            stride(from: wanted[0].minX + 16, to: wanted[0].maxX - 16, by: 4).lazy.map { x in Point(x: x, y: y) }
        }
        let point = try #require(grid.first { point in
            !list.contains { entry in
                let near = Rect(x: entry.bounds.x - 16, y: entry.bounds.y - 16, width: entry.bounds.width + 32, height: entry.bounds.height + 32)
                return near.contains(point) && entry.windowID != below
                    && (entry.pid == getpid() ? !waiting.contains(Int(entry.windowID)) : entry.layer == 0)  // a gap handle takes clicks
            }
        }, "no point of \(wanted[0]) is clear of the guest's windows")
        func click() async throws {
            for type in [CGEventType.leftMouseDown, .leftMouseUp] {
                CGEvent(mouseEventSource: nil, mouseType: type, mouseCursorPosition: CGPoint(x: point.x, y: point.y), mouseButton: .left)?.post(tap: .cghidEventTap)
                try await Task.sleep(for: .milliseconds(50))
            }
        }
        try await click()
        var front: [String] = []
        let reached = await waitUntil(timeout: .seconds(2)) {
            front = (try? await over.send("frontmost")) ?? []
            return front.contains("frontmost index=1")
        }
        #expect(reached, "the click at \(point) did not reach the window behind the panel: \(front)")

        _ = try await over.send("close 1")
        // D-17: on macOS 27.2 the closed window is still on screen when the reply comes, and took the click (09-24).
        let closed = await waitUntil(timeout: .seconds(3)) { !(CGWindowList.onScreenFrontToBack() ?? []).contains { $0.windowID == below } }
        try #require(closed, "window \(below) stayed on screen after its close")
        try await click()
        let finder = await waitUntil(timeout: .seconds(2)) { NSWorkspace.shared.frontmostApplication?.bundleIdentifier == "com.apple.finder" }
        #expect(finder, "the click at \(point) did not reach Finder: \(String(describing: NSWorkspace.shared.frontmostApplication?.bundleIdentifier))")
        #expect(!NSRunningApplication.current.isActive, "the click activated this process")
    }
}

import ApplicationServices
import Foundation
import TransomEngine
@testable import TransomMac
import TransomModel
import TransomPrivate
import Testing

private func intersection(_ a: Rect, _ b: Rect) -> (width: Double, height: Double) {
    (max(0, min(a.maxX, b.maxX) - max(a.minX, b.minX)), max(0, min(a.maxY, b.maxY) - max(a.minY, b.minY)))
}

private func near(_ a: Rect, _ b: Rect, within tolerance: Double) -> Bool {
    abs(a.x - b.x) <= tolerance && abs(a.y - b.y) <= tolerance && abs(a.width - b.width) <= tolerance && abs(a.height - b.height) <= tolerance
}

/// A saved group [0, 1] with window 1 selected, re-formed by a fresh controller over two fixture windows. The store
/// is a temporary directory, never the user's real layout.json.
@MainActor struct SavedGroup {
    /// One fixture with both windows, or one per window (`separateApps`), window 0's first.
    let fixtures: [FixtureProcess]
    var fixture: FixtureProcess { fixtures[0] }
    let directory: URL
    let arrange: ArrangeController
    let key: DeskKey
    let leaf: NodeID
    let hidden: TransomModel.WindowRef
    let selected: TransomModel.WindowRef
    let visible: Rect

    static func start(separateApps: Bool = false) async throws -> SavedGroup {
        let directory = FileManager.default.temporaryDirectory.appending(path: "transom-tabs-\(UUID().uuidString)", directoryHint: .isDirectory)
        let fixtures = separateApps
            ? [try await FixtureProcess.launch(["standard"]), try await FixtureProcess.launch(["standard"])]
            : [try await FixtureProcess.launch(["standard", "standard"])]
        var started = false
        defer {
            if !started {  // a failed start leaves no fixture or store behind
                for fixture in fixtures { fixture.terminate() }
                try? FileManager.default.removeItem(at: directory)
            }
        }
        let pids = Set(fixtures.map(\.pid))
        let system = AXWindowSystem(appFilter: { pid, _ in pids.contains(pid) })
        await system.start()
        let ids = fixtures.flatMap { $0.windows.sorted { $0.index < $1.index }.map(\.id) }
        try #require(ids.count == 2)
        var found: [WindowInfo] = []
        _ = await waitUntil(timeout: .seconds(3)) {
            let inventory = await system.inventory()
            guard inventory.initialRefreshComplete else { return false }
            found = ids.compactMap { id in inventory.windows.first { $0.window.windowID == id && $0.state == .present } }
            return found.count == 2
        }
        try #require(found.count == 2, "the fixture windows were never tracked")
        let hidden = found[0].window, selected = found[1].window

        // Built headlessly: window 0 docked, then window 1 grouped into its leaf (selected, D-03).
        var builder = Arranger()
        _ = builder.handle(.inventory(await system.inventory()), now: .now)
        _ = builder.handle(.command(.dock, focused: hidden), now: .now)
        let key = try #require(builder.deskKey(of: hidden))
        let leaf = try #require(builder.world[key]?.tree.leaf(containing: hidden), "window 0 did not dock")
        var world = builder.world, history = UndoHistory()
        try world.edit(key, history: &history) { desk, _ throws(LayoutError) in
            if desk.desktop.contains(selected) { try desk.desktop.remove(selected) }
            try desk.tree.group(selected, into: leaf)
        }
        try #require(world[key]?.tree.node(leaf) == .tabs(windows: [hidden, selected], selected: 1))
        try LayoutStore(directory: directory).save(
            LayoutFile(world: world, homeFrames: [:], session: SessionRecord(cleanExit: true, launchedAt: Date())))

        let arrange = ArrangeController(system: system, store: LayoutStore(directory: directory))
        await arrange.start()
        let visible = try #require(Displays.current().first { $0.uuid == key.displayUUID }).visibleFrame
        started = true
        return SavedGroup(
            fixtures: fixtures, directory: directory, arrange: arrange, key: key, leaf: leaf, hidden: hidden, selected: selected, visible: visible)
    }

    func close() {
        for fixture in fixtures { fixture.terminate() }
        try? FileManager.default.removeItem(at: directory)
    }

    /// The group's content rect as the controller plans it now.
    func content() -> Rect? {
        guard let desk = arrange.arranger.world[key],
            let tile = try? Planner.plan(desk: desk, area: visible, gap: arrange.arranger.gap, mins: [:]).resolution.nodeRects[leaf]
        else { return nil }
        return TabBand.content(of: tile)
    }

    /// The fixtures' own report of the two window frames, window 0 first.
    func frames() async -> [Rect] {
        var frames: [Rect] = []
        for fixture in fixtures {
            _ = try? await fixture.send("list")
            frames += fixture.windows.sorted { $0.index < $1.index }.map(\.frame)
        }
        return frames
    }

    /// `shown` fills `content` and `parked` is a sliver at the content size.
    func isShown(_ shown: Rect, parked: Rect, content rect: Rect) -> Bool {
        let sliver = intersection(parked, visible)
        return near(shown, rect, within: 2) && sliver.width * sliver.height < 40 * 40
            && abs(parked.width - rect.width) <= 1 && abs(parked.height - rect.height) <= 1
    }

    /// Waits for window 1 shown and window 0 parked: the saved group re-formed.
    func formed() async -> (Bool, last: [Rect], content: Rect?) {
        var last: [Rect] = [], rect: Rect?
        let ok = await waitUntil(timeout: .seconds(3)) {
            rect = content()
            last = await frames()
            guard let rect, last.count == 2 else { return false }
            return isShown(last[1], parked: last[0], content: rect)
        }
        return (ok, last, rect)
    }
}

/// TABS-01, TABS-02, D-04, D-07, D-08 live: tab groups against fixture windows only (never another app).
@Suite(.serialized, .enabled(if: IntegrationEnv.trusted, "needs a process with the Accessibility grant"))
@MainActor struct TabGroupIntegrationTests {
    /// A fresh controller puts window 1 in the content rect (the tile minus the 32 pt band) and parks window 0 at the
    /// content size, a sliver on screen.
    @Test(.timeLimit(.minutes(1)))
    func aSavedGroupReformsWithTheHiddenMemberParkedAtTheContentSize() async throws {
        let group = try await SavedGroup.start()
        defer { group.close() }
        defer { withExtendedLifetime(group.arrange) {} }  // its events loop ends with it
        let (formed, last, content) = await group.formed()
        #expect(formed, "windows at \(last), content rect \(String(describing: content)), visible \(group.visible)")
        #expect(group.arrange.arranger.world[group.key]?.tree.node(group.leaf) == .tabs(windows: [group.hidden, group.selected], selected: 1), "the saved group did not come back")
        #expect(group.arrange.arranger.isParked(group.hidden))
    }

    /// Selecting window 0 brings it into the content rect before window 1 leaves it (no wallpaper flash, D-08), and
    /// window 1 ends as a sliver at the content size.
    @Test(.timeLimit(.minutes(1)))
    func selectingTheHiddenTabRevealsItBeforeTheOtherParks() async throws {
        let group = try await SavedGroup.start()
        defer { group.close() }
        defer { withExtendedLifetime(group.arrange) {} }
        let (formed, last, content) = await group.formed()
        try #require(formed, "the group never formed: windows at \(last)")
        let rect = try #require(content)

        await group.arrange.tabAction(.select(group.hidden, via: .click))
        var samples: [[Rect]] = [], gap: [Rect]?, done = false
        let deadline = ContinuousClock.now + .seconds(2)
        while ContinuousClock.now < deadline {
            let frames = await group.frames()
            if frames.count == 2 {
                samples.append(frames)
                // At no sample is the content rect left uncovered: window 1 gone while window 0 is not yet there.
                if !near(frames[1], rect, within: 2), !near(frames[0], rect, within: 2), gap == nil { gap = frames }
                if group.isShown(frames[0], parked: frames[1], content: rect) {
                    done = true
                    break
                }
            }
            try await Task.sleep(for: .milliseconds(50))
        }
        #expect(done, "window 0 never shown with window 1 parked; last samples \(samples.suffix(3)), content \(rect)")
        #expect(gap == nil, "the content rect was uncovered: \(String(describing: gap))")
        #expect(group.arrange.arranger.world[group.key]?.tree.node(group.leaf) == .tabs(windows: [group.hidden, group.selected], selected: 0))
        #expect(group.arrange.arranger.isParked(group.selected))
    }

    /// The AX commands Close Group and Minimize Group send: a minimise reads back absent, and a close press on the
    /// window's own button is confirmed closed by both sources within `Arranger.closeConfirmation` (A4).
    @Test(.timeLimit(.minutes(1)))
    func closeAndMinimizeCommandsActOnFixtureWindows() async throws {
        let fixture = try await FixtureProcess.launch(["standard", "standard"])
        defer { fixture.terminate() }
        let fixturePID = fixture.pid
        let system = AXWindowSystem(appFilter: { pid, _ in pid == fixturePID })
        await system.start()
        let ids = fixture.windows.sorted { $0.index < $1.index }.map(\.id)
        var refs: [TransomModel.WindowRef] = []
        _ = await waitUntil(timeout: .seconds(3)) {
            let inventory = await system.inventory()
            refs = ids.compactMap { id in inventory.windows.first { $0.window.windowID == id && $0.state == .present }?.window }
            return inventory.initialRefreshComplete && refs.count == 2
        }
        try #require(refs.count == 2, "the fixture windows were never tracked")

        await system.perform([.minimize(refs[1])])
        let minimized = await waitUntil(timeout: .seconds(2)) { await system.windowInfo(refs[1])?.state == .absent }
        let state = await system.windowInfo(refs[1])?.state
        #expect(minimized, "window 1 never read back minimised: \(String(describing: state))")

        // D-23: window 0's own element, so the facts after the close are the inputs of CloseRule's ordered-out row.
        var listed: CFTypeRef?
        _ = AXUIElementCopyAttributeValue(AXUIElementCreateApplication(fixturePID), kAXWindowsAttribute as CFString, &listed)
        let element = (listed as? [AXUIElement] ?? []).first { candidate in
            var id: CGWindowID = 0
            return AXWindowID.function?(candidate, &id) == .success && id == refs[0].windowID
        }

        let pressed = ContinuousClock.now
        await system.perform([.close(refs[0])])
        let closed = await waitUntil(timeout: .seconds(3)) { await system.windowInfo(refs[0]) == nil }
        var role: CFTypeRef?
        let axFact = element.map { String(AXUIElementCopyAttributeValue($0, kAXRoleAttribute as CFString, &role).rawValue) } ?? "no element"
        let entry = CGWindowList.snapshot()?.first { $0.windowID == refs[0].windowID }
        let spaces = SkyLightSpaces.spaces(of: [refs[0].windowID])?[refs[0].windowID]
        let shown = Set(Displays.current().compactMap(\.currentSpaceID))
        print("closed window 0 facts: AXRole error \(axFact), in CG list \(entry != nil), onScreen \(String(describing: entry?.onScreen)), spaces \(String(describing: spaces)), shown Spaces \(shown)")
        let latency = pressed.duration(to: .now)
        print("close-confirmation latency: \(latency)")
        #expect(closed, "window 0 was never confirmed closed")
        #expect(latency < Arranger.closeConfirmation, "the close took \(latency) to confirm")
    }

    /// Minimize Group on a group of two windows of one app (Pitfall 6, A1): macOS then focuses the other, hidden
    /// window, which must not bring the group back. After 2 s the selected window is still minimised, the hidden one
    /// still a sliver at the content size, and the model keeps the same selected member.
    @Test(.timeLimit(.minutes(1)))
    func minimizeGroupWithTwoWindowsOfOneAppStaysMinimized() async throws {
        let group = try await SavedGroup.start()
        defer { group.close() }
        defer { withExtendedLifetime(group.arrange) {} }
        let (formed, last, content) = await group.formed()
        try #require(formed, "the group never formed: windows at \(last)")
        let rect = try #require(content)

        // Logged, not asserted: macOS moves focus to the other window only when the fixture is the active app.
        print("before minimize: \(try await group.fixture.send("frontmost").first ?? "")")
        await group.arrange.tabAction(.minimizeGroup(GroupKey(desk: group.key, node: group.leaf)))
        try await Task.sleep(for: .seconds(2))
        print("after minimize: \(try await group.fixture.send("frontmost").first ?? "")")
        #expect(group.arrange.arranger.world[group.key]?.state(of: group.selected) == .absent, "the selected window is not minimised")
        let frames = await group.frames()
        try #require(frames.count == 2)
        let sliver = intersection(frames[0], group.visible)
        #expect(sliver.width * sliver.height < 40 * 40, "the hidden window came on screen at \(frames[0])")
        #expect(abs(frames[0].width - rect.width) <= 1 && abs(frames[0].height - rect.height) <= 1, "the hidden window was resized to \(frames[0])")
        #expect(group.arrange.arranger.world[group.key]?.tree.node(group.leaf) == .tabs(windows: [group.hidden, group.selected], selected: 1),
            "the group changed its selected tab")
    }

    /// 07 UAT Bug 1 (D-08): activating the app of a hidden member that is already that app's focused window (⌘Tab, the
    /// Dock, `open -a`) sends no focused-window change, only the activation; the member still becomes the selected tab
    /// and fills the content rect, the other member parking. Each window is its own fixture app.
    @Test(.timeLimit(.minutes(1)))
    func activatingTheAppOfAHiddenMemberSelectsIt() async throws {
        let group = try await SavedGroup.start(separateApps: true)
        defer { group.close() }
        defer { withExtendedLifetime(group.arrange) {} }
        let (formed, last, content) = await group.formed()
        try #require(formed, "the group never formed: windows at \(last)")
        let rect = try #require(content)

        /// Sets AXFrontmost, as the focus fallback does: the app activates and keeps its focused window, like ⌘Tab.
        func activate(_ index: Int) async throws -> String {
            let app = AXUIElementCreateApplication(group.fixtures[index].pid)
            #expect(AXUIElementSetAttributeValue(app, kAXFrontmostAttribute as CFString, kCFBooleanTrue) == .success)
            var reply = ""
            _ = await waitUntil(timeout: .seconds(2)) {
                reply = (try? await group.fixtures[index].send("frontmost"))?.first ?? ""
                return reply != "frontmost none"
            }
            return reply
        }
        // The selected member's app first, as after a click on its tab; then past the focus suppression.
        #expect(try await activate(1) == "frontmost index=0", "fixture 1 did not become frontmost with its window key")
        try await Task.sleep(for: Arranger.focusSuppression + .milliseconds(300))
        let before = try await group.fixture.send("frontmost").first
        try #require(before == "frontmost none", "fixture 0 is still active: \(before ?? "")")
        try #require(group.arrange.arranger.world[group.key]?.tree.node(group.leaf) == .tabs(windows: [group.hidden, group.selected], selected: 1),
            "activating the selected member's app changed the group")

        // Its only window is the parked member, so it is that app's key window, invisible until the group selects it.
        #expect(try await activate(0) == "frontmost index=0", "fixture 0 did not become frontmost with its parked window key")
        var frames: [Rect] = []
        let shown = await waitUntil(timeout: .seconds(3)) {
            frames = await group.frames()
            return frames.count == 2 && group.isShown(frames[0], parked: frames[1], content: rect)
        }
        #expect(shown, "window 0 was not shown in the content rect with window 1 parked: windows at \(frames), content \(rect)")
        #expect(group.arrange.arranger.world[group.key]?.tree.node(group.leaf) == .tabs(windows: [group.hidden, group.selected], selected: 0),
            "the activated member did not become the selected tab")
    }

    /// D-07: the quit restore puts both members of a re-formed group (the hidden one parked) at the content rect, the
    /// selected one raised last. Arranging is paused right after, standing in for Transom's exit.
    @Test(.timeLimit(.minutes(1)))
    func quitPlacesEveryGroupMemberAtTheContentRect() async throws {
        let group = try await SavedGroup.start()
        defer { group.close() }
        defer { withExtendedLifetime(group.arrange) {} }
        let (formed, last, content) = await group.formed()
        try #require(formed, "the group never formed: windows at \(last)")
        let rect = try #require(content)
        try #require(group.arrange.arranger.isParked(group.hidden), "the hidden member was not parked")

        let restored = group.arrange.restoreForTermination(limit: .seconds(2))
        await group.arrange.setPaused(.user, true)  // no await before this: nothing reacts to the restore's moves
        #expect(restored >= 1, "the hidden member was not written")
        var frames: [Rect] = []
        let placed = await waitUntil(timeout: .seconds(2)) {
            frames = await group.frames()
            return frames.count == 2 && frames.allSatisfy { near($0, rect, within: 2) }
        }
        #expect(placed, "windows at \(frames), content rect \(rect)")
    }

    /// D-10 on hardware-shaped events: a press on a tab with the window-under-pointer field left 0 (what macOS 27
    /// sends from a real trackpad) still starts the tear-off, found by the strip under the point.
    @Test(.timeLimit(.minutes(1)))
    func aTabDraggedOutWithNoWindowUnderPointerLeavesTheGroup() async throws {
        let group = try await SavedGroup.start()
        defer { group.close() }
        defer { withExtendedLifetime(group.arrange) {} }
        let (formed, last, _) = await group.formed()
        try #require(formed, "the group never formed: windows at \(last)")
        try #require(group.arrange.startTap(), "the event tap was refused")
        defer { group.arrange.stopTap() }

        var strip: CGRect?
        _ = await waitUntil(timeout: .seconds(2)) {
            let numbers = group.arrange.tabStripPanels.windowNumbers
            let list = CGWindowListCopyWindowInfo(.optionOnScreenOnly, kCGNullWindowID) as? [[String: Any]] ?? []
            strip = list.first { numbers.contains($0[kCGWindowNumber as String] as? Int ?? -1) }
                .flatMap { ($0[kCGWindowBounds as String] as? NSDictionary).flatMap { CGRect(dictionaryRepresentation: $0) } }
            return strip != nil
        }
        let bounds = try #require(strip, "no tab strip on screen")
        let grab = CGPoint(x: bounds.minX + bounds.width * 0.3, y: bounds.midY)  // window 0's tab, right of the group buttons
        let number = try #require(group.arrange.tabStripPanels.panelNumber(underPointer: 0, at: Point(x: grab.x, y: grab.y)))
        try #require(group.arrange.tabStripPanels.member(atWindowNumber: number, point: Point(x: grab.x, y: grab.y)) == group.hidden)

        let saved = CGEvent(source: nil)?.location ?? grab
        let end = CGPoint(x: group.visible.x + 4, y: group.visible.y + group.visible.height / 2)  // the left edge zone
        var released = false
        func post(_ type: CGEventType, _ point: CGPoint) {
            CGEvent(mouseEventSource: nil, mouseType: type, mouseCursorPosition: point, mouseButton: .left)?.post(tap: .cghidEventTap)
            if type == .leftMouseUp { released = true }
        }
        defer {
            if !released { post(.leftMouseUp, end) }
            CGWarpMouseCursorPosition(saved)
        }
        post(.leftMouseDown, grab)
        try await Task.sleep(for: .milliseconds(50))
        for i in 1...20 {
            let t = Double(i) / 20
            post(.leftMouseDragged, CGPoint(x: grab.x + (end.x - grab.x) * t, y: grab.y + (end.y - grab.y) * t))
            try await Task.sleep(for: .milliseconds(16))
        }
        post(.leftMouseUp, end)

        let left = await waitUntil(timeout: .seconds(3)) {
            guard let tree = group.arrange.arranger.world[group.key]?.tree else { return false }
            guard let leaf = tree.leaf(containing: group.hidden) else { return true }  // floating
            if case .tabs = tree.node(leaf) { return false }
            return true
        }
        #expect(left, "window 0 is still in the group: \(String(describing: group.arrange.arranger.world[group.key]?.tree))")
    }
}

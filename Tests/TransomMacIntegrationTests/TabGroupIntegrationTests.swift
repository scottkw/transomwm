import Foundation
import TransomEngine
@testable import TransomMac
import TransomModel
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
    let fixture: FixtureProcess
    let directory: URL
    let arrange: ArrangeController
    let key: DeskKey
    let leaf: NodeID
    let hidden: TransomModel.WindowRef
    let selected: TransomModel.WindowRef
    let visible: Rect

    static func start() async throws -> SavedGroup {
        let directory = FileManager.default.temporaryDirectory.appending(path: "transom-tabs-\(UUID().uuidString)", directoryHint: .isDirectory)
        let fixture = try await FixtureProcess.launch(["standard", "standard"])
        var started = false
        defer {
            if !started {  // a failed start leaves no fixture or store behind
                fixture.terminate()
                try? FileManager.default.removeItem(at: directory)
            }
        }
        let fixturePID = fixture.pid
        let system = AXWindowSystem(appFilter: { pid, _ in pid == fixturePID })
        await system.start()
        let ids = fixture.windows.sorted { $0.index < $1.index }.map(\.id)
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
            fixture: fixture, directory: directory, arrange: arrange, key: key, leaf: leaf, hidden: hidden, selected: selected, visible: visible)
    }

    func close() {
        fixture.terminate()
        try? FileManager.default.removeItem(at: directory)
    }

    /// The group's content rect as the controller plans it now.
    func content() -> Rect? {
        guard let desk = arrange.arranger.world[key],
            let tile = try? Planner.plan(desk: desk, area: visible, gap: arrange.arranger.gap, mins: [:]).resolution.nodeRects[leaf]
        else { return nil }
        return TabBand.content(of: tile)
    }

    /// The fixture's own report of its two window frames, window 0 first.
    func frames() async -> [Rect] {
        _ = try? await fixture.send("list")
        return fixture.windows.sorted { $0.index < $1.index }.map(\.frame)
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
}

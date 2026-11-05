import AppKit
import Foundation
@testable import TransomEngine
@testable import TransomMac
import TransomModel
import TransomPrivate
import Testing

/// The fixture's windows as the system tracks them, once all of `fixture.windows` are present.
@MainActor private func tracked(_ system: AXWindowSystem, _ fixture: FixtureProcess) async throws -> [TransomModel.WindowRef] {
    let ids = fixture.windows.sorted { $0.index < $1.index }.map(\.id)
    var found: [WindowInfo] = []
    _ = await waitUntil(timeout: .seconds(3)) {
        let inventory = await system.inventory()
        guard inventory.initialRefreshComplete else { return false }
        found = ids.compactMap { id in inventory.windows.first { $0.window.windowID == id && $0.state == .present } }
        return found.count == ids.count
    }
    try #require(found.count == ids.count, "the fixture windows were never tracked")
    return found.map(\.window)
}

/// That display's committed view, once it is `target`.
@MainActor private func settled(_ arrange: ArrangeController, _ key: DeskKey, on target: ViewTarget) async -> Bool {
    await waitUntil(timeout: .seconds(3)) { arrange.arranger.camera.views[key] ?? .home == target && arrange.arranger.camera.pending[key.displayUUID] == nil }
}

/// The smallest view holding `windows` in the controller's World now.
@MainActor private func lowestView(_ windows: [TransomModel.WindowRef], _ arrange: ArrangeController, _ key: DeskKey) throws -> ViewTarget {
    let tree = try #require(arrange.arranger.world[key]?.tree)
    let leaves = windows.compactMap { arrange.arranger.leafNode(of: $0) }
    return Navigator.target(try #require(Navigator.lowestCommonAncestor(leaves, in: tree)), in: tree)
}

/// Until the events queued since `system.start()` are read: a queued `windowCreated` outside a new view widens it home.
@MainActor private func drainEvents(_ arrange: ArrangeController) async {
    var last = ContinuousClock.now
    arrange.onInventory = { _ in last = .now }
    _ = await waitUntil(timeout: .seconds(3)) { ContinuousClock.now - last > .milliseconds(500) }
    arrange.onInventory = nil
}

/// VIEW-02, VIEW-01 D-03 live: saved views on real windows. Fixture windows only; the store is a temporary directory,
/// never the user's real layout.json.
@Suite(.serialized, .enabled(if: IntegrationEnv.trusted, "needs a process with the Accessibility grant"))
@MainActor struct ViewsIntegrationTests {
    /// Connects to the window server first (see ZoomSettleIntegrationTests).
    init() { _ = NSApplication.shared }

    /// Phase 3 docking alone never gives a node holding only two windows (a | b | Desktop), so the session starts from a
    /// saved [(A / B) | Desktop] with C floating. The view is saved on the (A / B) column; C then splits A's tile and B moves
    /// up under A, so A and B's lowest common node is a new one, then Transom relaunches.
    @Test(.timeLimit(.minutes(1)))
    func aViewSurvivesASplitAMoveAndARelaunch() async throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: "transom-views-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: directory) }
        let fixture = try await FixtureProcess.launch(["standard", "standard", "standard"])
        defer { fixture.terminate() }
        let fixturePID = fixture.pid

        let system = AXWindowSystem(appFilter: { pid, _ in pid == fixturePID })
        await system.start()
        let refs = try await tracked(system, fixture)
        let (a, b, c) = (refs[0], refs[1], refs[2])
        var builder = Arranger()
        _ = builder.handle(.inventory(await system.inventory()), now: .now)
        let key = try #require(builder.deskKey(of: a))
        var seed = builder.world, history = UndoHistory()
        try seed.edit(key, history: &history) { desk, ids throws(LayoutError) in
            for window in [a, b] where desk.desktop.contains(window) { try desk.desktop.remove(window) }
            try desk.tree.insert(a, at: .left, of: .desktop, ids: &ids)
            guard let leaf = desk.tree.leaf(containing: a) else { throw .windowNotFound(a) }
            try desk.tree.insert(b, at: .bottom, of: leaf, ids: &ids)
        }
        try LayoutStore(directory: directory).save(LayoutFile(world: seed, homeFrames: [:], session: SessionRecord(cleanExit: true, launchedAt: Date())))

        do {
            let arrange = ArrangeController(system: system, store: LayoutStore(directory: directory), zoomEnabled: true)
            await arrange.start()
            try #require(await waitUntil(timeout: .seconds(3)) { !arrange.arranger.awaitsRestore && arrange.arranger.isFloating(c) }, "the seed was never re-attached")
            await drainEvents(arrange)
            let column = try lowestView([a, b], arrange, key)
            try #require(column != .home, "A and B fill the whole desk: \(column)")

            await arrange.zoom(to: column, displayUUID: key.displayUUID)
            try #require(await settled(arrange, key, on: column), "the camera never settled on the column")
            await arrange.dispatch(.camera(.saveView(ViewSlot(3)!)))
            #expect(arrange.arranger.camera.savedViews[ViewSlot(3)!]?.windows == [a.identity, b.identity].sorted())
            await arrange.zoom(to: .home, displayUUID: key.displayUUID)
            try #require(await settled(arrange, key, on: .home), "the camera never came home")

            // C docks from the Desktop tile, then moves left across the column: on a tie the smaller NodeID, A, takes it.
            await arrange.dispatch(.dock, focused: c)
            await arrange.dispatch(.moveOrSnap(.left), focused: c)
            let tree = try #require(arrange.arranger.world[key]?.tree)
            let (leafA, leafC) = (try #require(tree.leaf(containing: a)), try #require(tree.leaf(containing: c), "C did not dock"))
            try #require(tree.parent(of: leafA) == tree.parent(of: leafC), "C did not split beside A: \(tree)")

            // B moves up across A and C: the tie goes to the most recently focused (D-11), so make that A.
            await arrange.dispatch(.focus(.left), focused: c)
            try #require(await waitUntil(timeout: .seconds(3)) { arrange.arranger.focusOrder.first == a.identity }, "A never took focus: \(arrange.arranger.focusOrder)")
            await arrange.dispatch(.moveOrSnap(.top), focused: b)
            let moved = try lowestView([a, b], arrange, key)
            #expect(moved != .home && moved != column, "A and B's lowest common node should be a new, smaller one, not \(moved)")
            arrange.writeCleanExit()
        }

        let freshSystem = AXWindowSystem(appFilter: { pid, _ in pid == fixturePID })
        await freshSystem.start()
        _ = try await tracked(freshSystem, fixture)
        let fresh = ArrangeController(system: freshSystem, store: LayoutStore(directory: directory), zoomEnabled: true)
        defer { withExtendedLifetime(fresh) {} }  // its events loop ends with it
        await fresh.start()
        try #require(await waitUntil(timeout: .seconds(3)) { !fresh.arranger.awaitsRestore }, "the saved layout was never re-attached")
        await drainEvents(fresh)
        try #require(fresh.arranger.camera.savedViews[ViewSlot(3)!] != nil, "the saved view did not come back from layout.json")
        let expected = try lowestView([a, b], fresh, key)
        try #require(expected != .home, "A and B fill the whole desk after the relaunch")

        await fresh.dispatch(.camera(.view(ViewSlot(3)!)))
        let framed = await settled(fresh, key, on: expected)
        #expect(framed, "the camera is at \(String(describing: fresh.arranger.camera.views[key])), not \(expected)")
    }

    /// The main display, its first desktop and the next one; the guest needs at least two desktops.
    private func desktops() throws -> (display: String, first: UInt64, second: UInt64) {
        let main = try #require(Displays.current().first?.uuid)
        let list = try #require(SpacesProvider.snapshot()?.displays.first { $0.displayUUID == main }, "Spaces lookup unavailable")
        let ids = list.spaces.filter { $0.kind == .desktop }.map(\.id)
        try #require(ids.count >= 2, "the guest needs two desktops, has \(ids)")
        return (main, ids[0], ids[1])
    }

    /// Switches the main display to `space`, waiting until it shows.
    private func show(_ space: UInt64, on display: String) async throws {
        _ = await SpaceSwitcher(spaces: { SpacesProvider.snapshot() }).switchTo(space: space, on: display)
        try #require(await waitUntil(timeout: .seconds(3)) { SkyLightSpaces.currentSpace(displayUUID: display) == space }, "the main display never showed Space \(space)")
    }

    /// D-03 and the joined announcement: a view saved on Desktop 2 is reached from Desktop 1 by switching first, then zooming.
    /// VM only: it posts Mission Control chords. It starts and ends on the first desktop.
    @Test(
        .timeLimit(.minutes(1)), .enabled(if: IntegrationEnv.inVM, "VM only: posts Mission Control chords and switches Spaces"))
    func aViewOnAnotherSpaceSwitchesFirst() async throws {
        let (display, first, second) = try desktops()
        try await show(first, on: display)
        do {
            try await show(second, on: display)
            let fixture = try await FixtureProcess.launch(["standard"])
            defer { fixture.terminate() }
            let fixturePID = fixture.pid
            let system = AXWindowSystem(appFilter: { pid, _ in pid == fixturePID })
            await system.start()
            let window = try #require(try await tracked(system, fixture).first)
            let arrange = ArrangeController(system: system, zoomEnabled: true)
            defer { withExtendedLifetime(arrange) {} }
            await arrange.start()
            await drainEvents(arrange)
            let slot = ViewSlot(4)!
            await arrange.dispatch(.dock, focused: window)
            let key = try #require(arrange.arranger.deskKey(of: window))
            try #require(key.spaceID == second, "the fixture window is on \(key), not Space \(second)")
            let leaf = try #require(arrange.arranger.leafNode(of: window))

            await arrange.zoom(to: .node(leaf), displayUUID: display)
            try #require(await settled(arrange, key, on: .node(leaf)), "the camera never settled on the window")
            await arrange.dispatch(.camera(.saveView(slot)))
            try #require(arrange.arranger.camera.savedViews[slot]?.desk == key, "the view was not saved on Desktop 2")
            await arrange.zoom(to: .home, displayUUID: display)
            try #require(await settled(arrange, key, on: .home), "the camera never came home")

            try await show(first, on: display)
            try #require(await waitUntil(timeout: .seconds(2)) { arrange.arranger.displays.first { $0.uuid == display }?.currentSpaceID == first }, "the Arranger never saw Desktop 1")
            var said: [String] = []
            arrange.zoomController?.announce = { said.append($0) }

            await arrange.dispatch(.camera(.view(slot)))

            #expect(SkyLightSpaces.currentSpace(displayUUID: display) == second, "the Space did not switch first")
            let framed = await settled(arrange, key, on: .node(leaf))
            #expect(framed, "the camera on Desktop 2 is at \(String(describing: arrange.arranger.camera.views[key])), not the saved window")
            #expect(await waitUntil(timeout: .seconds(2)) { !said.isEmpty }, "the reveal said nothing")
            #expect(said.count == 1 && said.first?.hasPrefix("View 4. Showing") == true, "VoiceOver heard \(said)")
            await arrange.zoom(to: .home, displayUUID: display)
            _ = await settled(arrange, key, on: .home)
        } catch {
            try? await show(first, on: display)
            throw error
        }
        try await show(first, on: display)
    }
}

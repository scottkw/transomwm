import Foundation
@testable import TransomEngine
import TransomModel
import TransomTestSupport
import Testing

private let pid: Int32 = 900
private let bundleID = "com.example.arranger"
private let visible = Rect(x: 0, y: 25, width: 1440, height: 875)
private let display = DisplayInfo(uuid: "main", frame: Rect(x: 0, y: 0, width: 1440, height: 900), visibleFrame: visible, currentSpaceID: nil)
private let key = DeskKey(displayUUID: "main", spaceID: nil)

private func ref(_ id: UInt32) -> WindowRef {
    WindowRef(identity: WindowIdentity(windowID: id, pid: pid, bundleID: bundleID))
}

private let w1 = ref(1), w2 = ref(2)
private let frame1 = Rect(x: 40, y: 80, width: 320, height: 232)
/// Well inside the right half, so docking w1 does not touch it.
private let frame2 = Rect(x: 900, y: 400, width: 150, height: 120)

private func pointer(_ kind: PointerEvent.Kind, _ point: Point, _ modifiers: Modifiers = [], press: WindowRef? = nil) -> ArrangerInput {
    .pointer(PointerEvent(kind: kind, location: point, modifiers: modifiers, pressWindow: press))
}

/// The green button of `frame` (12 pt in, 4 pt down), where an ⌥-click lands.
private func greenButton(of frame: Rect) -> Point { Point(x: frame.minX + 19, y: frame.minY + 12) }

/// TILE-06, D-12: a green-button click toggles docked and floating, exactly like Dock and Float.
@Suite struct ArrangerGreenButtonTests {
    @Test func onAFloatingWindowItDocksLikeDock() async throws {
        var clicked = await Harness.started()
        var docked = await Harness.started()
        let viaButton = await clicked.send(.greenButton(w1))
        let viaCommand = await docked.send(.command(.dock, focused: w1))
        #expect(setFrames(viaButton) == setFrames(viaCommand))
        #expect(setFrames(viaButton)[w1] != nil, "w1 was not docked: \(viaButton)")
        #expect(clicked.arranger.world == docked.arranger.world)
        #expect(clicked.arranger.history.depth(for: key) == 1)
    }

    @Test func onADockedWindowItFloatsLikeFloat() async throws {
        var clicked = await Harness.started()
        var floated = await Harness.started()
        await clicked.send(.command(.dock, focused: w1))
        await floated.send(.command(.dock, focused: w1))
        let viaButton = await clicked.send(.greenButton(w1))
        let viaCommand = await floated.send(.command(.float, focused: w1))
        #expect(viaButton == viaCommand)
        #expect(clicked.arranger.world == floated.arranger.world)
        #expect(clicked.arranger.world[key]?.desktop.contains(w1) == true)
        #expect(clicked.arranger.history.depth(for: key) == 2)
    }

    /// G-03-4: Float puts the window back at its pre-dock frame and Dock fills the tile, so each toggle moves it.
    @Test func onTheDesksOnlyDockedWindowTheButtonFloatsItToItsPreDockFrameAndDocksItBack() async throws {
        var harness = await Harness.started()
        await harness.send(.command(.dock, focused: w1))
        let tile = try #require(await harness.frame(w1))
        await harness.send(.greenButton(w1))
        let floated = try #require(await harness.frame(w1))
        #expect(floated == frame1)
        #expect(!Planner.near(floated, tile, within: 2))
        await harness.send(.greenButton(w1))
        let docked = await harness.frame(w1)
        #expect(docked == tile)
    }

    /// G-03-4: with no known pre-dock frame (a restored docked window), Float gives a centred frame 90% of the tile.
    @Test func aFloatWithNoKnownPreDockFrameGetsASlightlySmallerCentredFrame() async throws {
        var source = await Harness.started()
        await source.send(.command(.dock, focused: w1))
        let tile = try #require(await source.frame(w1))
        var restored = Arranger()
        _ = restored.handle(.restore(source.arranger.world, homeFrames: [:]), now: .now)
        _ = restored.handle(.inventory(await source.fake.inventory()), now: .now)
        let effects = restored.handle(.command(.float, focused: w1), now: .now)
        let frame = try #require(setFrames(effects)[w1])
        let desk = try #require(restored.world[key])
        let desktop = try #require(try Planner.plan(desk: desk, area: visible, gap: 8, mins: [:]).desktopRect)
        #expect(abs(frame.midX - desktop.midX) <= 0.5 && abs(frame.midY - desktop.midY) <= 0.5, "\(frame) not centred in \(desktop)")
        #expect(abs(frame.width - 0.9 * tile.width) <= 0.5 && abs(frame.height - 0.9 * tile.height) <= 0.5, "\(frame) vs tile \(tile)")
        #expect(!Planner.near(frame, tile, within: 2))
    }

    @Test func excludedNeverDockOrPausedWindowsAreLeftAlone() async throws {
        var arranger = Arranger()
        let panel = info(3, frame: frame1, kind: .neverDock(.subrole))
        let excluded = info(4, frame: frame1, excluded: true)
        _ = arranger.handle(.inventory(WindowInventory(displays: [display], windows: [info(1, frame: frame1), panel, excluded])), now: .now)
        let before = arranger.world
        #expect(arranger.handle(.greenButton(ref(3)), now: .now).isEmpty)
        #expect(arranger.handle(.greenButton(ref(4)), now: .now).isEmpty)
        #expect(arranger.handle(.greenButton(ref(9)), now: .now).isEmpty, "an untracked window")
        _ = arranger.handle(.setPaused(.user, true), now: .now)
        #expect(arranger.handle(.greenButton(w1), now: .now).isEmpty)
        #expect(arranger.world == before)
    }

    /// D-33 (A4): an ⌥-click is not swallowed, so macOS zooms. The zoom is the app's own frame change: a floating window
    /// keeps it, a docked one goes back into its tile. A press with no pointer travel is never a drag.
    @Test func afterAnOptionZoomAFloatingWindowKeepsItsNewFrame() async throws {
        var harness = await Harness.started()
        await harness.send(.command(.dock, focused: w1))
        let tile = try #require(await harness.frame(w1))
        let zoomed = Rect(x: 1000, y: 100, width: 400, height: 700)
        #expect(!zoomed.overlaps(tile))
        await harness.send(pointer(.down, greenButton(of: frame2), [.option], press: w2))
        await harness.send(pointer(.up, greenButton(of: frame2), [.option]))
        await harness.fake.update(2) { $0.frame = zoomed }
        let effects = await harness.refresh()
        #expect(setFrames(effects)[w2] == nil, "the zoom was answered: \(effects)")
        #expect(harness.arranger.world[key]?.desktop.frame(of: w2) == zoomed)
        #expect(await harness.frame(w2) == zoomed)
    }

    /// D-05: a floater zoomed across a docked tile keeps the app's frame; Transom never clamps it.
    @Test func afterAnOptionZoomAcrossATileAFloatingWindowKeepsItsFrame() async throws {
        var harness = await Harness.started()
        await harness.send(.command(.dock, focused: w1))
        await harness.send(pointer(.down, greenButton(of: frame2), [.option], press: w2))
        // The zoom lands while the button is still down; mouse-up decides.
        await harness.fake.update(2) { $0.frame = visible }
        _ = await harness.refresh()
        let effects = await harness.send(pointer(.up, greenButton(of: frame2), [.option]))
        #expect(setFrames(effects)[w2] == nil, "the zoom across a tile was answered: \(effects)")
        #expect(harness.arranger.world[key]?.desktop.frame(of: w2) == visible)
        #expect(await harness.frame(w2) == visible)
        #expect(harness.arranger.drag == nil)
    }

    /// Quick 261027-gqo: a floater on exactly the Desktop tile has its centre in the Desktop's centre zone.
    /// A plain click still docks it (no beep), and the exact-centre tie picks the Desktop's left edge.
    @Test func aPlainClickOnAFloaterOverTheWholeDesktopTileDocksIt() async throws {
        var harness = await Harness.started()
        await harness.send(.command(.dock, focused: w1))
        let before = try #require(harness.arranger.world[key])
        let desktop = try #require(try Planner.plan(desk: before, area: visible, gap: 8, mins: [:]).desktopRect)
        await harness.fake.userMove(2, to: desktop)  // D-05: Transom no longer clamps a zoom there, so the user puts it there
        _ = await harness.refresh()
        #expect(await harness.frame(w2) == desktop, "the setup does not fill the Desktop tile")
        let depth = harness.arranger.history.depth(for: key)
        let effects = await harness.send(.greenButton(w2))
        #expect(!effects.contains(.beep), "the green click beeped: \(effects)")
        let docked = try #require(setFrames(effects)[w2], "w2 was not docked: \(effects)")
        let after = try #require(harness.arranger.world[key])
        #expect(after.desktop.contains(w2) == false)
        #expect(harness.arranger.history.depth(for: key) == depth + 1)
        let newDesktop = try #require(try Planner.plan(desk: after, area: visible, gap: 8, mins: [:]).desktopRect)
        #expect(docked.maxX <= newDesktop.minX, "w2 did not dock left of the Desktop: \(docked) vs \(newDesktop)")
    }

    @Test func afterAnOptionZoomADockedWindowGoesBackIntoItsTile() async throws {
        var harness = await Harness.started()
        await harness.send(.command(.dock, focused: w1))
        let tile = try #require(await harness.frame(w1))
        await harness.send(pointer(.down, greenButton(of: tile), [.option], press: w1))
        await harness.send(pointer(.up, greenButton(of: tile), [.option]))
        await harness.fake.update(1) { $0.frame = visible }
        let effects = await harness.refresh()
        #expect(setFrames(effects)[w1] == tile, "not put back: \(effects)")
        #expect(harness.arranger.world[key]?.tree.state(of: w1) == .present)
        #expect(harness.arranger.history.depth(for: key) == 1)
    }

    @Test func aZoomDuringThePressOfADockedWindowIsCorrectedOnMouseUp() async throws {
        var harness = await Harness.started()
        await harness.send(.command(.dock, focused: w1))
        let tile = try #require(await harness.frame(w1))
        await harness.send(pointer(.down, greenButton(of: tile), [.option], press: w1))
        await harness.fake.update(1) { $0.frame = visible }
        let during = await harness.refresh()
        #expect(setFrames(during)[w1] == nil, "written before mouse-up")
        let effects = await harness.send(pointer(.up, greenButton(of: tile), [.option]))
        #expect(setFrames(effects)[w1] == tile, "not put back: \(effects)")
    }
}

/// RESEARCH Pattern 5: the tracker carries the green button's offset; corpus fixtures without it still decode.
@Suite struct GreenButtonTrackingTests {
    @Test func aSnapshotsGreenButtonReachesWindowInfo() throws {
        let offset = Rect(x: 12, y: 4, width: 14, height: 16)
        let snapshot = WindowSnapshot(
            role: "AXWindow", subrole: "AXStandardWindow", minimized: false, fullScreen: false,
            close: .enabled, minimize: .enabled, zoom: .enabled, fullScreenButton: .enabled, frame: frame1, greenButton: offset)
        var tracker = WindowTracker()
        let observation = WindowObservation(windowID: 7, idSource: .axPrivate, read: .success(snapshot), title: "")
        _ = tracker.ingest(AppObservation(pid: pid, bundleID: bundleID, windows: [observation]), context: ObservationContext(initialSweep: true, now: .now))
        let identity = WindowIdentity(windowID: 7, pid: pid, bundleID: bundleID)
        #expect(tracker.info(for: identity)?.greenButton == offset)

        // Under a point of drift is no change; a real move is one windowChanged.
        func moved(_ dx: Double) -> [WindowEvent] {
            var next = snapshot
            next.greenButton = Rect(x: offset.x + dx, y: offset.y, width: offset.width, height: offset.height)
            let o = WindowObservation(windowID: 7, idSource: .axPrivate, read: .success(next), title: "")
            return tracker.ingest(AppObservation(pid: pid, bundleID: bundleID, windows: [o]), context: ObservationContext(now: .now))
        }
        #expect(moved(0.5).isEmpty)
        let events = moved(20)
        #expect(events.count == 1)
        guard case .windowChanged(let info)? = events.first else {
            Issue.record("expected windowChanged, got \(events)")
            return
        }
        #expect(info.greenButton?.x == offset.x + 20)
    }

    @Test func aSnapshotWithoutTheFieldDecodesWithNil() throws {
        let json = #"{"schemaVersion":1,"role":"AXWindow","close":{"present":true,"enabled":true},"minimize":{"present":true,"enabled":true},"zoom":{"present":true,"enabled":true},"fullScreenButton":{"present":true,"enabled":true}}"#
        let snapshot = try JSONDecoder().decode(WindowSnapshot.self, from: Data(json.utf8))
        #expect(snapshot.greenButton == nil)
        #expect(snapshot.role == "AXWindow")
    }
}

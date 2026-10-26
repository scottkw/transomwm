import PaneEngine
import PaneModel
import PaneTestSupport
import Testing

/// Harness.refresh() refreshes this pid (ArrangerLifecycleTests).
private let pid: Int32 = 900
private let bundleID = "com.example.arranger"
private let visible = Rect(x: 0, y: 25, width: 1440, height: 875)
private func display(space: UInt64?) -> DisplayInfo {
    DisplayInfo(uuid: "D", frame: Rect(x: 0, y: 0, width: 1440, height: 900), visibleFrame: visible, currentSpaceID: space)
}
private func desk(_ space: UInt64?) -> DeskKey { DeskKey(displayUUID: "D", spaceID: space) }

private func ref(_ id: UInt32) -> WindowRef {
    WindowRef(identity: WindowIdentity(windowID: id, pid: pid, bundleID: bundleID))
}

private let a = ref(1), b = ref(2), c = ref(3)
private let frameA = Rect(x: 40, y: 80, width: 320, height: 232)
private let frameB = Rect(x: 730, y: 400, width: 150, height: 120)

extension Harness {
    /// Display D on Space 1 with Spaces data on; windows 1 and 2 on Space 1; a and b docked side by side.
    static func onSpaceOne(dock: Bool = true) async -> Harness {
        var harness = Harness()
        await harness.fake.setDisplays([display(space: 1)])
        await harness.fake.setSpacesAvailable(true)
        await harness.fake.addApp(FakeApp(pid: pid, bundleID: bundleID))
        await harness.fake.open(.standard(id: 1, pid: pid, frame: frameA, space: 1))
        await harness.fake.open(.standard(id: 2, pid: pid, frame: frameB, space: 1))
        await harness.fake.showSpace(1, notifies: false)
        await harness.fake.refreshAll()
        _ = await harness.inbox.take()
        await harness.send(.inventory(await harness.fake.inventory()))
        if dock {
            await harness.send(.command(.dock, focused: a))
            await harness.send(.command(.dock, focused: b))
        }
        return harness
    }

    /// A Space switch as the live shell sees it: the notification's events, then a refresh. Returns every effect.
    mutating func switchTo(_ space: UInt64) async -> (events: [WindowEvent], effects: [ArrangerEffect]) {
        await fake.showSpace(space)
        let events = await inbox.take()
        var effects: [ArrangerEffect] = []
        for event in events {
            let next = arranger.handle(.event(event), now: .now)
            effects += next
            for case .perform(let commands) in next { await fake.perform(commands) }
        }
        effects += await refresh()
        return (events, effects)
    }

    @discardableResult
    /// Opens a standard window and waits out the tracker's settle delay, so it is reported.
    mutating func openNew(_ id: UInt32, frame: Rect, space: UInt64) async -> [ArrangerEffect] {
        await fake.open(.standard(id: id, pid: pid, frame: frame, space: space))
        var effects = await refresh()
        await fake.advance(by: .milliseconds(300))
        effects += await refresh()
        return effects
    }
}

/// D-25: one layout per display and Space; only the visible Space is arranged.
@Suite struct ArrangerSpacesTests {
    @Test func aSpaceSwitchLeavesTheOtherSpacesLayoutAlone() async throws {
        var harness = await Harness.onSpaceOne()
        let tileA = try #require(await harness.frame(a)), tileB = try #require(await harness.frame(b))
        #expect(harness.arranger.world[desk(1)]?.tree.windows.count == 2)

        let away = await harness.switchTo(2)
        #expect(away.events.contains(.spaceChanged(displayUUID: "D", spaceID: 2)))
        #expect(setFrames(away.effects).isEmpty, "switching away moved \(setFrames(away.effects))")
        #expect(harness.arranger.displays.first?.currentSpaceID == 2)

        await harness.openNew(3, frame: Rect(x: 500, y: 300, width: 300, height: 200), space: 2)
        #expect(harness.arranger.deskKey(of: c) == desk(2))
        let docked = setFrames(await harness.send(.command(.dock, focused: c)))
        #expect(Set(docked.keys) == [c], "docking on Space 2 wrote \(docked.keys)")

        let back = await harness.switchTo(1)
        #expect(back.events.contains(.spaceChanged(displayUUID: "D", spaceID: 1)))
        #expect(setFrames(back.effects)[a] == nil && setFrames(back.effects)[b] == nil, "switching back re-sent \(setFrames(back.effects))")
        #expect(setFrames(back.effects)[c] == nil)
        #expect(await harness.frame(a) == tileA)
        #expect(await harness.frame(b) == tileB)
        #expect(harness.arranger.deskKey(of: a) == desk(1) && harness.arranger.deskKey(of: c) == desk(2))
    }

    @Test func aCloseOnAHiddenSpaceIsAppliedAndPlannedOnlyOnReturn() async throws {
        var harness = await Harness.onSpaceOne()
        let tileA = try #require(await harness.frame(a))
        _ = await harness.switchTo(2)
        await harness.fake.close(2)
        let closed = await harness.refresh()
        #expect(harness.arranger.world[desk(1)]?.contains(b) == false)
        #expect(setFrames(closed).isEmpty, "a hidden desk was planned: \(setFrames(closed))")

        let back = await harness.switchTo(1)
        let frames = setFrames(back.effects)
        #expect(Set(frames.keys) == [a], "on return: \(frames)")
        let grown = try #require(frames[a])
        #expect(grown.width * grown.height > tileA.width * tileA.height, "a did not take b's space: \(tileA) -> \(grown)")
        #expect(setFrames(await harness.refresh()).isEmpty)
    }

    @Test func theFakesSpaceSwitchMovesEveryDisplaysCurrentSpace() async {
        let harness = await Harness.onSpaceOne(dock: false)
        await harness.fake.showSpace(4, notifies: false)
        #expect(await harness.fake.inventory().displays.map(\.currentSpaceID) == [4])
        #expect(await harness.inbox.take().isEmpty, "a switch without the notification yielded events")
    }
}

private let spacesOff = ArrangerEffect.info("Spaces lookup off: one layout per display")

private func info(_ id: UInt32, frame: Rect, display: String = "D", spaces: Set<UInt64>?) -> WindowInfo {
    WindowInfo(window: ref(id), frame: frame, state: .present, displayUUID: display, spaces: spaces)
}

private func inventory(_ displays: [DisplayInfo], _ windows: [WindowInfo]) -> ArrangerInput {
    .inventory(WindowInventory(displays: displays, windows: windows))
}

/// D-25, WIN-07, TILE-03, A7: windows go to their own Space's desk, fullscreen Spaces get none, re-homes and re-plans.
extension ArrangerSpacesTests {
    @Test func windowsAtLaunchGoToTheirOwnSpacesDeskAndOnlyTheShownOneIsPlanned() {
        var arranger = Arranger()
        // Window 2 sits where window 1's tile lands: on window 1's desk it would be moved out of the tile.
        let under = Rect(x: 100, y: 300, width: 200, height: 150)
        _ = arranger.handle(inventory([display(space: 1)], [
            info(1, frame: frameA, spaces: [1]), info(2, frame: under, spaces: [2]), info(3, frame: frameB, spaces: nil),
        ]), now: .now)
        #expect(arranger.deskKey(of: a) == desk(1))
        #expect(arranger.deskKey(of: b) == desk(2))
        #expect(arranger.deskKey(of: c) == desk(1), "a window with no Space data goes to the shown Space")
        let frames = setFrames(arranger.handle(.command(.dock, focused: a), now: .now))
        #expect(frames[a] != nil)
        #expect(frames[b] == nil, "a window on a Space not shown was planned")
    }

    @Test func aFullscreenSpaceGetsNoDeskAndTheWindowReturnsToItsTile() async throws {
        var harness = await Harness.onSpaceOne()
        let tileA = try #require(await harness.frame(a)), tileB = try #require(await harness.frame(b))
        await harness.fake.update(1) {
            $0.space = 9
            $0.snapshot.fullScreen = true
        }
        let enter = await harness.switchTo(9)
        #expect(harness.arranger.world[desk(9)] == nil, "a fullscreen Space got a desk")
        #expect(harness.arranger.deskKey(of: a) == desk(1))
        #expect(harness.arranger.world[desk(1)]?.state(of: a) == .fullscreen)
        #expect(setFrames(enter.effects).isEmpty, "planned while the fullscreen Space is shown: \(setFrames(enter.effects))")

        await harness.fake.update(1) {
            $0.space = 1
            $0.snapshot.fullScreen = false
        }
        _ = await harness.switchTo(1)
        #expect(harness.arranger.world[desk(1)]?.state(of: a) == .present)
        #expect(await harness.frame(a) == tileA)
        #expect(await harness.frame(b) == tileB)
    }

    @Test func aFloatingWindowOnAnotherSpaceMovesToThatSpacesDeskWithNoUndoStep() throws {
        var arranger = Arranger()
        _ = arranger.handle(inventory([display(space: 1)], [info(1, frame: frameA, spaces: [1])]), now: .now)
        let history = arranger.history
        _ = arranger.handle(.event(.windowChanged(info(1, frame: frameA, spaces: [2]))), now: .now)
        #expect(arranger.deskKey(of: a) == desk(2))
        #expect(arranger.world[desk(2)]?.desktop.frame(of: a) == frameA)
        #expect(arranger.history == history)
    }

    @Test func aDockedWindowOnAnotherSpaceFloatsThereAndItsNeighbourReflows() throws {
        var arranger = Arranger()
        _ = arranger.handle(inventory([display(space: 1)], [info(1, frame: frameA, spaces: [1]), info(2, frame: frameB, spaces: [1])]), now: .now)
        _ = arranger.handle(.command(.dock, focused: a), now: .now)
        _ = arranger.handle(.command(.dock, focused: b), now: .now)
        let history = arranger.history
        let moved = Rect(x: 700, y: 100, width: 400, height: 300)
        let frames = setFrames(arranger.handle(.event(.windowChanged(info(2, frame: moved, spaces: [2]))), now: .now))
        #expect(arranger.deskKey(of: b) == desk(2))
        #expect(arranger.world[desk(2)]?.desktop.frame(of: b) == moved)
        #expect(arranger.world[desk(1)]?.tree.state(of: b) == nil)
        #expect(frames[a] != nil, "the neighbour did not reflow")
        #expect(frames[b] == nil)
        #expect(arranger.history == history)
    }

    @Test func anEmptySpaceSetNeverMovesAWindow() {
        var arranger = Arranger()
        _ = arranger.handle(inventory([display(space: 1)], [info(1, frame: frameA, spaces: [1])]), now: .now)
        _ = arranger.handle(.event(.windowChanged(info(1, frame: frameA, spaces: []))), now: .now)
        #expect(arranger.deskKey(of: a) == desk(1))
    }

    @Test func aWindowMovedToAnotherDisplayFloatsOnItsShownDesk() throws {
        var arranger = Arranger()
        let e = DisplayInfo(uuid: "E", frame: Rect(x: 1440, y: 0, width: 1920, height: 1080),
                            visibleFrame: Rect(x: 1440, y: 25, width: 1920, height: 1055), currentSpaceID: 5)
        _ = arranger.handle(inventory([display(space: 1), e], [info(1, frame: frameA, spaces: [1]), info(2, frame: frameB, spaces: [1])]), now: .now)
        _ = arranger.handle(.command(.dock, focused: a), now: .now)
        _ = arranger.handle(.command(.dock, focused: b), now: .now)
        let onE = Rect(x: 1600, y: 100, width: 400, height: 300)
        let frames = setFrames(arranger.handle(.event(.windowChanged(info(1, frame: onE, display: "E", spaces: [5]))), now: .now))
        #expect(arranger.deskKey(of: a) == DeskKey(displayUUID: "E", spaceID: 5))
        #expect(arranger.world[DeskKey(displayUUID: "E", spaceID: 5)]?.desktop.frame(of: a) == onE)
        #expect(frames[b] != nil, "the old display's desk was not re-planned")
        #expect(frames[a] == nil)
    }

    @Test func withSpacesOffEachDisplayHasOneDeskAndThatIsLoggedOnce() {
        var arranger = Arranger()
        let first = arranger.handle(inventory([display(space: nil)], [info(1, frame: frameA, spaces: nil)]), now: .now)
        #expect(arranger.deskKey(of: a) == desk(nil))
        #expect(first.filter { $0 == spacesOff }.count == 1)
        let again = arranger.handle(inventory([display(space: nil)], [info(1, frame: frameA, spaces: nil)]), now: .now)
        #expect(!again.contains(spacesOff))
        #expect(!arranger.handle(.command(.dock, focused: a), now: .now).contains(spacesOff))
    }

    @Test func aDisplayChangeReplansTheShownDeskAndAGoneDisplayGetsNothing() throws {
        var arranger = Arranger()
        let e = DisplayInfo(uuid: "E", frame: Rect(x: 1440, y: 0, width: 1920, height: 1080),
                            visibleFrame: Rect(x: 1440, y: 25, width: 1920, height: 1055), currentSpaceID: 5)
        let onE = Rect(x: 1600, y: 100, width: 400, height: 300)
        let windows = [info(1, frame: frameA, spaces: [1]), info(3, frame: onE, display: "E", spaces: [5])]
        _ = arranger.handle(inventory([display(space: 1), e], windows), now: .now)
        _ = arranger.handle(.command(.dock, focused: a), now: .now)
        _ = arranger.handle(.command(.dock, focused: c), now: .now)
        var smaller = display(space: 1)
        smaller.visibleFrame = Rect(x: 0, y: 25, width: 1000, height: 600)
        let frames = setFrames(arranger.handle(inventory([smaller], windows), now: .now))
        let tile = try #require(frames[a], "the shown desk was not re-planned")
        #expect(inside(tile, smaller.visibleFrame))
        #expect(frames[c] == nil, "a window on a display that went away got a frame")
    }
}


import Foundation
@testable import TransomEngine
import TransomModel
import TransomTestSupport
import Testing

/// Harness.refresh() refreshes this pid (ArrangerLifecycleTests).
private let pid: Int32 = 900
private let bundleID = "com.example.arranger"

private func ref(_ id: UInt32) -> WindowRef {
    WindowRef(identity: WindowIdentity(windowID: id, pid: pid, bundleID: bundleID))
}

/// The built-in display L and an external display D to its right; the Spaces lookup is off unless a test sets a Space.
private let visibleL = Rect(x: 0, y: 25, width: 1440, height: 875)
private let visibleD = Rect(x: 1440, y: 25, width: 1920, height: 1055)
private func displayL(space: UInt64? = nil) -> DisplayInfo {
    DisplayInfo(uuid: "L", frame: Rect(x: 0, y: 0, width: 1440, height: 900), visibleFrame: visibleL, currentSpaceID: space)
}
private func displayD(space: UInt64? = nil) -> DisplayInfo {
    DisplayInfo(uuid: "D", frame: Rect(x: 1440, y: 0, width: 1920, height: 1080), visibleFrame: visibleD, currentSpaceID: space)
}
private let names = ["D": "DELL U2720Q", "E": "LG UltraFine"]

/// The first window on the left of its display; the second small and inside the right half (ArrangerLifecycleTests).
private func startFrame(_ index: Int, on visible: Rect) -> Rect {
    index == 0
        ? Rect(x: visible.minX + 40, y: 80, width: 320, height: 232)
        : Rect(x: visible.minX + 730, y: 400, width: 150, height: 120)
}

private func near(_ a: Rect?, _ b: Rect?) -> Bool {
    guard let a, let b else { return false }
    return abs(a.x - b.x) <= 0.5 && abs(a.y - b.y) <= 0.5 && abs(a.width - b.width) <= 0.5 && abs(a.height - b.height) <= 0.5
}

/// L and D, each window opened on its display at `startFrame` and docked in order: `onL` on L, `onD` on D. Returns the
/// harness and every docked window's tile.
private func docked(
    onL: [UInt32], onD: [UInt32], space: UInt64? = nil, extra: [DisplayInfo] = [], onExtra: [UInt32] = [], floating: [UInt32: Rect] = [:]
) async throws -> (harness: Harness, tiles: [WindowRef: Rect]) {
    var harness = Harness()
    await harness.fake.setDisplays([displayL(space: space), displayD(space: space)] + extra)
    if let space {
        await harness.fake.setSpacesAvailable(true)
        await harness.fake.showSpace(space, notifies: false)
    }
    await harness.fake.addApp(FakeApp(pid: pid, bundleID: bundleID))
    let groups = [(onL, visibleL), (onD, visibleD)] + extra.map { (onExtra, $0.visibleFrame) }
    for (ids, visible) in groups {
        for (index, id) in ids.enumerated() { await harness.fake.open(.standard(id: id, pid: pid, frame: startFrame(index, on: visible), space: space)) }
    }
    for (id, frame) in floating.sorted(by: { $0.key < $1.key }) { await harness.fake.open(.standard(id: id, pid: pid, frame: frame, space: space)) }
    await harness.fake.refreshAll()
    _ = await harness.inbox.take()
    await harness.send(.inventory(await harness.fake.inventory()))
    for id in onL + onD + onExtra { await harness.send(.command(.dock, focused: ref(id))) }
    try #require((harness.arranger.world[DeskKey(displayUUID: "L", spaceID: space)]?.tree.windows ?? []) == onL.map(ref))
    try #require((harness.arranger.world[DeskKey(displayUUID: "D", spaceID: space)]?.tree.windows ?? []) == onD.map(ref))
    var tiles: [WindowRef: Rect] = [:]
    for id in onL + onD + onExtra { tiles[ref(id)] = try #require(await harness.frame(ref(id))) }
    return (harness, tiles)
}

/// The N12 notices in `effects`.
private func disconnected(_ effects: [ArrangerEffect]) -> [Notice] {
    effects.compactMap { if case .notice(let notice) = $0, case .displaysDisconnected = notice { notice } else { nil } }
}

private func floats(_ id: UInt32, on key: DeskKey, in arranger: Arranger) -> Bool {
    arranger.world[key]?.desktop.contains(ref(id)) == true
}

extension Harness {
    /// Feeds every pending fake event, as `settle()` does, and returns the effects.
    mutating func drain() async -> [ArrangerEffect] {
        var effects: [ArrangerEffect] = []
        for _ in 0..<5 {
            let events = await inbox.take()
            if events.isEmpty { break }
            for event in events {
                let next = arranger.handle(.event(event), now: now)
                effects += next
                for case .perform(let commands) in next { await fake.perform(commands) }
            }
        }
        return effects
    }

    /// A display change as the shell delivers it (06-05): `.displaysSettling`, then macOS's change and its events, then
    /// `.displaysSettled` with the arrangement and inventory read afterwards. Returns the effects while settling and on
    /// the settle separately.
    mutating func displayChange(_ change: (FakeWindowSystem) async -> Void) async -> (settling: [ArrangerEffect], settled: [ArrangerEffect]) {
        var during = await send(.displaysSettling)
        await change(fake)
        during += await drain()
        let inventory = await fake.inventory()
        let settled = await send(.displaysSettled(ArrangementID(inventory.displays.map(\.uuid)), names: names, inventory: inventory))
        return (during, settled)
    }
}

/// OVER-05, OVER-06, D-09..D-12: the display settling state and per-arrangement layout sets, on FakeWindowSystem.
@Suite struct ArrangerDisplaySettleTests {
    private let deskL = DeskKey(displayUUID: "L", spaceID: nil)
    private let deskD = DeskKey(displayUUID: "D", spaceID: nil)

    /// The tracer: unplug → settling keeps every tile → re-plug brings each window back to its tile on D.
    @Test func unplugThenReplugReturnsEveryWindowToItsTile() async throws {
        var (harness, tiles) = try await docked(onL: [1], onD: [2, 3])

        let unplug = await harness.displayChange { await $0.unplug("D", movingSpacesTo: "L") }
        #expect(setFrames(unplug.settling).isEmpty, "a frame was written while displays were settling")
        // macOS moved D's windows onto L meanwhile; the World kept them in D's tree until the settle.
        #expect(await harness.fake.windows[2].map { inside($0.frame, visibleL) } == true)
        // After the settle: D's desk stays, dormant; its windows float on L; L's window keeps its tile.
        #expect(harness.arranger.world[deskD] != nil)
        #expect(floats(2, on: deskL, in: harness.arranger) && floats(3, on: deskL, in: harness.arranger))
        #expect(harness.arranger.world[deskL]?.tree.windows == [ref(1)])
        #expect(near(await harness.frame(ref(1)), tiles[ref(1)]))

        let replug = await harness.displayChange { await $0.plug("D") }
        #expect(setFrames(replug.settling).isEmpty)
        #expect(harness.arranger.world[deskD]?.tree.windows == [ref(2), ref(3)])
        #expect(harness.arranger.world[deskL]?.tree.windows == [ref(1)])
        for id: UInt32 in [1, 2, 3] { #expect(near(await harness.frame(ref(id)), tiles[ref(id)]), "window \(id) is not back in its tile") }
        #expect(!replug.settled.contains { if case .notice = $0 { true } else { false } }, "a re-plug showed a notice")
    }

    /// D-09: each arrangement brings back its own layout; a weight change is not a placement, so it stays with its set.
    @Test func dockAndUndockCyclesBringEachArrangementsLayoutBack() async throws {
        var (harness, tiles) = try await docked(onL: [1, 4], onD: [2, 3])
        let unplug = await harness.displayChange { await $0.unplug("D", movingSpacesTo: "L") }
        #expect(disconnected(unplug.settled) == [.displaysDisconnected(names: ["DELL U2720Q"], windows: 2)])
        #expect(floats(2, on: deskL, in: harness.arranger) && floats(3, on: deskL, in: harness.arranger))

        await harness.send(.command(.growTile, focused: ref(1)))
        let hand = try #require(await harness.frame(ref(1)))
        try #require(!near(hand, tiles[ref(1)]), "growTile did not change L's layout")

        let replug = await harness.displayChange { await $0.plug("D") }
        #expect(disconnected(replug.settled).isEmpty)
        #expect(harness.arranger.world[deskD]?.tree.windows == [ref(2), ref(3)])
        for id: UInt32 in [1, 2, 3, 4] { #expect(near(await harness.frame(ref(id)), tiles[ref(id)]), "window \(id) is not in its {D, L} tile") }

        let again = await harness.displayChange { await $0.unplug("D", movingSpacesTo: "L") }
        #expect(disconnected(again.settled).isEmpty, "a known arrangement floated windows")
        #expect(near(await harness.frame(ref(1)), hand), "L's hand arrangement did not come back")
        #expect(harness.arranger.layoutSets[ArrangementID(["D", "L"])] != nil && harness.arranger.layoutSets[ArrangementID(["L"])] == nil)
    }

    /// User action wins (OVER-06): a floated window the user docked on L stays there on re-plug; the other goes home.
    @Test func aWindowTheUserDockedWhileAwayStaysWhereTheUserPutIt() async throws {
        var (harness, _) = try await docked(onL: [1], onD: [2, 3])
        _ = await harness.displayChange { await $0.unplug("D", movingSpacesTo: "L") }
        await harness.send(.command(.dock, focused: ref(2)))
        try #require(harness.arranger.world[deskL]?.tree.windows.contains(ref(2)) == true)
        let userTile = try #require(await harness.frame(ref(2)))

        _ = await harness.displayChange { await $0.plug("D") }
        #expect(harness.arranger.world[deskL]?.tree.windows.contains(ref(2)) == true, "the user's dock was undone")
        #expect(harness.arranger.world[deskL]?.tree.windows.contains(ref(1)) == true)
        #expect(harness.arranger.world[deskD]?.tree.windows == [ref(3)])
        #expect(near(await harness.frame(ref(2)), userTile))
        #expect(await harness.frame(ref(3)).map { inside($0, visibleD) } == true)
    }

    /// D-10: floated windows cascade from the visible frame's top-left, 24 pt apart, at their own sizes, on screen.
    @Test func floatedWindowsCascadeFromTheVisibleFramesTopLeftOnScreen() async throws {
        let sizes: [UInt32: Size] = [5: Size(width: 400, height: 300), 6: Size(width: 500, height: 350), 7: Size(width: 300, height: 200)]
        let floating = Dictionary(uniqueKeysWithValues: sizes.map { id, size in
            (id, Rect(x: visibleD.minX + 100 + 200 * Double(id - 5), y: 300, width: size.width, height: size.height))
        })
        var (harness, _) = try await docked(onL: [1], onD: [], floating: floating)
        let unplug = await harness.displayChange { await $0.unplug("D", movingSpacesTo: "L") }
        #expect(disconnected(unplug.settled) == [.displaysDisconnected(names: ["DELL U2720Q"], windows: 3)])
        let desk = try #require(harness.arranger.world[deskL])
        for (index, id) in [UInt32(5), 6, 7].enumerated() {
            let offset = 24 * Double(index)
            let expected = Rect(x: visibleL.minX + offset, y: visibleL.minY + offset, width: sizes[id]!.width, height: sizes[id]!.height)
            #expect(near(desk.desktop.frame(of: ref(id)), expected), "window \(id) is not at its cascade frame")
            #expect(near(await harness.frame(ref(id)), expected))
            #expect(inside(expected, visibleL))
        }
    }

    @Test func theCascadeIsClampedInsideTheReceivingDisplay() {
        let frames = ArrangementSwitch.cascade(
            frames: [Rect(x: 0, y: 0, width: 600, height: 400), Rect(x: 0, y: 0, width: 600, height: 400)], from: Point(x: 1000, y: 700), in: visibleL)
        #expect(frames.allSatisfy { inside($0, visibleL) && $0.width == 600 && $0.height == 400 })
    }

    /// D-09: the same displays rearranged or re-scaled are one arrangement: no set is swapped, tiles re-plan.
    @Test func aRescaledDisplayIsTheSameArrangementAndItsTilesReplan() async throws {
        var (harness, tiles) = try await docked(onL: [1], onD: [2, 3])
        let bigger = Rect(x: 1440, y: 25, width: 2560, height: 1415)
        let rescaled = DisplayInfo(uuid: "D", frame: Rect(x: 1440, y: 0, width: 2560, height: 1440), visibleFrame: bigger, currentSpaceID: nil)
        let change = await harness.displayChange { await $0.setDisplays([displayL(), rescaled]) }
        #expect(harness.arranger.layoutSets.all.isEmpty)
        #expect(harness.arranger.arrangement == ArrangementID(["D", "L"]))
        #expect(harness.arranger.world[deskD]?.tree.windows == [ref(2), ref(3)])
        let three = try #require(await harness.frame(ref(3)))
        #expect(inside(three, bigger) && three.height > visibleD.height, "D's tiles did not re-plan to its new frame")
        #expect(near(await harness.frame(ref(1)), tiles[ref(1)]))
        #expect(disconnected(change.settled).isEmpty)
    }

    /// Pitfall 13: duplicate display UUIDs are logged and treated as a new arrangement; no stored set is applied.
    @Test func duplicateDisplayUUIDsNeverApplyAStoredSet() async throws {
        var (harness, _) = try await docked(onL: [1], onD: [2, 3])
        _ = await harness.displayChange { await $0.unplug("D", movingSpacesTo: "L") }
        let twin = DisplayInfo(uuid: "D", frame: Rect(x: 3360, y: 0, width: 1920, height: 1080), visibleFrame: Rect(x: 3360, y: 25, width: 1920, height: 1055), currentSpaceID: nil)
        let change = await harness.displayChange { fake in
            await fake.plug("D")
            await fake.setDisplays([displayL(), displayD(), twin])
        }
        #expect(change.settled.contains { if case .info(let line) = $0 { line.contains("duplicate display UUID") } else { false } })
        #expect(!change.settled.contains { if case .fault = $0 { true } else { false } })
        #expect(harness.arranger.layoutSets[ArrangementID(["D", "L"])] != nil, "the stored set was applied")
        #expect((harness.arranger.world[deskD]?.tree.windows ?? []).isEmpty)
        #expect(floats(2, on: deskL, in: harness.arranger) && floats(3, on: deskL, in: harness.arranger))
    }

    /// D-12: with Spaces shared across displays, desks stay keyed per display UUID through an unplug and re-plug.
    @Test func sharedSpacesKeepDesksKeyedPerDisplay() async throws {
        var (harness, tiles) = try await docked(onL: [1], onD: [2, 3], space: 5)
        let sharedL = DeskKey(displayUUID: "L", spaceID: 5), sharedD = DeskKey(displayUUID: "D", spaceID: 5)
        _ = await harness.displayChange { await $0.unplug("D", movingSpacesTo: "L") }
        #expect(harness.arranger.world[sharedD] != nil)
        #expect(floats(2, on: sharedL, in: harness.arranger) && floats(3, on: sharedL, in: harness.arranger))
        _ = await harness.displayChange { await $0.plug("D") }
        #expect(harness.arranger.world[sharedD]?.tree.windows == [ref(2), ref(3)])
        #expect(harness.arranger.world[sharedL]?.tree.windows == [ref(1)])
        for id: UInt32 in [2, 3] { #expect(near(await harness.frame(ref(id)), tiles[ref(id)])) }
    }

    /// Two displays unplugged in one change: one N12 naming both, with the total count.
    @Test func twoDisplaysUnpluggedAtOnceGiveOneNotice() async throws {
        let visibleE = Rect(x: 3360, y: 25, width: 1920, height: 1055)
        let displayE = DisplayInfo(uuid: "E", frame: Rect(x: 3360, y: 0, width: 1920, height: 1080), visibleFrame: visibleE, currentSpaceID: nil)
        var (harness, _) = try await docked(onL: [1], onD: [2], extra: [displayE], onExtra: [3])
        let change = await harness.displayChange { fake in
            await fake.unplug("D", movingSpacesTo: "L")
            await fake.unplug("E", movingSpacesTo: "L")
        }
        #expect(disconnected(change.settled) == [.displaysDisconnected(names: ["DELL U2720Q", "LG UltraFine"], windows: 2)])
        #expect(harness.arranger.dormantDeskCount == 2 && harness.arranger.awayDisplayCount == 2)
    }

    @Test func unpluggingADisplayWithNoWindowsShowsNoNotice() async throws {
        var (harness, _) = try await docked(onL: [1], onD: [])
        let change = await harness.displayChange { await $0.unplug("D", movingSpacesTo: "L") }
        #expect(disconnected(change.settled).isEmpty)
    }

    /// CR-01: after a failed launch re-attach, layout.json keeps the saved layout, its arrangement and its sets through
    /// any display settle: no empty World is stored as a set, no stored set is taken, nothing is relabelled.
    @Test func aSettleAfterAFailedReattachKeepsTheSavedLayoutAndItsSets() async throws {
        var (harness, _) = try await docked(onL: [1], onD: [2, 3])
        _ = await harness.displayChange { await $0.unplug("D", movingSpacesTo: "L") }
        let saved = harness.arranger.snapshot
        try #require(saved.arrangement == ArrangementID(["L"]) && saved.layoutSets.map(\.arrangement) == [ArrangementID(["D", "L"])])

        harness.arranger = Arranger()
        harness.arranger.reattachFault = .invariantViolated("test: the saved layout cannot be re-attached")
        _ = harness.arranger.handle(
            .restore(saved.world, homeFrames: saved.homeFrames, wantedFrames: saved.wantedFrames, arrangement: saved.arrangement, layoutSets: saved.layoutSets),
            now: harness.now)
        let launch = await harness.send(.inventory(await harness.fake.inventory()))
        try #require(launch.contains { if case .fault(let line) = $0 { line.contains("could not re-attach") } else { false } })

        _ = await harness.displayChange { await $0.plug("D") }
        let after = harness.arranger.snapshot
        #expect(after.world == saved.world, "the saved layout was replaced")
        #expect(after.arrangement == saved.arrangement, "the saved layout was relabelled")
        #expect(after.layoutSets == saved.layoutSets, "the stored layout sets changed")
    }

    /// WR-09: a settle that arrives while the launch restore still waits re-attaches the saved layout under its own
    /// arrangement, stores it as that arrangement's set, then applies the live arrangement's stored set.
    @Test func aSettleDuringThePendingRestoreStoresTheSavedLayoutAndAppliesTheLiveSet() async throws {
        var (harness, _) = try await docked(onL: [1], onD: [2, 3])
        _ = await harness.displayChange { await $0.unplug("D", movingSpacesTo: "L") }
        let saved = harness.arranger.snapshot
        try #require(saved.arrangement == ArrangementID(["L"]) && saved.layoutSets.map(\.arrangement) == [ArrangementID(["D", "L"])])

        harness.arranger = Arranger()
        _ = harness.arranger.handle(
            .restore(saved.world, homeFrames: saved.homeFrames, wantedFrames: saved.wantedFrames, arrangement: saved.arrangement, layoutSets: saved.layoutSets),
            now: harness.now)
        _ = await harness.displayChange { await $0.plug("D") }

        #expect(!harness.arranger.awaitsRestore)
        #expect(harness.arranger.arrangement == ArrangementID(["D", "L"]))
        // Floating windows are re-homed to the displays they are on now (as in the launch settle), so the set is compared
        // by L's docked layout.
        let stored = try #require(harness.arranger.layoutSets[ArrangementID(["L"])]?.world, "the saved layout was not stored under its own arrangement")
        #expect(stored[deskL]?.tree == saved.world[deskL]?.tree)
        #expect(harness.arranger.layoutSets[ArrangementID(["D", "L"])] == nil, "the live arrangement's set was not applied")
        #expect(harness.arranger.world[deskD]?.tree.windows == [ref(2), ref(3)])
    }

    /// Debug S4: desks whose display is away, and how many displays those are.
    @Test func dormantDesksAreCountedWhileTheirDisplayIsAway() async throws {
        var (harness, _) = try await docked(onL: [1], onD: [2, 3])
        #expect(harness.arranger.dormantDeskCount == 0 && harness.arranger.awayDisplayCount == 0)
        _ = await harness.displayChange { await $0.unplug("D", movingSpacesTo: "L") }
        #expect(harness.arranger.dormantDeskCount == 1 && harness.arranger.awayDisplayCount == 1)
        _ = await harness.displayChange { await $0.plug("D") }
        #expect(harness.arranger.dormantDeskCount == 0 && harness.arranger.awayDisplayCount == 0)
    }
}

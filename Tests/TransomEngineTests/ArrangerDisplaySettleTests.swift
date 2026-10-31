import Foundation
import TransomEngine
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
    onL: [UInt32], onD: [UInt32], space: UInt64? = nil, extra: [DisplayInfo] = [], onExtra: [UInt32] = []
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
    await harness.fake.refreshAll()
    _ = await harness.inbox.take()
    await harness.send(.inventory(await harness.fake.inventory()))
    for id in onL + onD + onExtra { await harness.send(.command(.dock, focused: ref(id))) }
    try #require(harness.arranger.world[DeskKey(displayUUID: "L", spaceID: space)]?.tree.windows == onL.map(ref))
    try #require(harness.arranger.world[DeskKey(displayUUID: "D", spaceID: space)]?.tree.windows == onD.map(ref))
    var tiles: [WindowRef: Rect] = [:]
    for id in onL + onD + onExtra { tiles[ref(id)] = try #require(await harness.frame(ref(id))) }
    return (harness, tiles)
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
}

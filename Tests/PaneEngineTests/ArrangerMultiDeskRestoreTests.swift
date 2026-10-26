import Foundation
import PaneEngine
import PaneModel
import PaneTestSupport
import Testing

/// Harness.refresh() refreshes this pid (ArrangerLifecycleTests).
private let pid: Int32 = 900
private let bundleID = "com.example.arranger"

private func ref(_ id: UInt32) -> WindowRef {
    WindowRef(identity: WindowIdentity(windowID: id, pid: pid, bundleID: bundleID))
}

/// Display A (Spaces 1, 2) and display B to its right (Spaces 3, 4), each with its own current Space.
private let visibleA = Rect(x: 0, y: 25, width: 1440, height: 875)
private let visibleB = Rect(x: 1440, y: 25, width: 1920, height: 1055)
private let displayA = DisplayInfo(uuid: "A", frame: Rect(x: 0, y: 0, width: 1440, height: 900), visibleFrame: visibleA, currentSpaceID: 1)
private let displayB = DisplayInfo(uuid: "B", frame: Rect(x: 1440, y: 0, width: 1920, height: 1080), visibleFrame: visibleB, currentSpaceID: 3)

/// Two windows per desk, both docked: [first | second | Desktop].
private struct DeskPlan {
    let key: DeskKey
    let ids: [UInt32]
    let visible: Rect
}

private let plans = [
    DeskPlan(key: DeskKey(displayUUID: "A", spaceID: 1), ids: [1, 2], visible: visibleA),
    DeskPlan(key: DeskKey(displayUUID: "A", spaceID: 2), ids: [3, 4], visible: visibleA),
    DeskPlan(key: DeskKey(displayUUID: "B", spaceID: 3), ids: [5, 6], visible: visibleB),
    DeskPlan(key: DeskKey(displayUUID: "B", spaceID: 4), ids: [7, 8], visible: visibleB),
]

/// The first window on the left of its display; the second small and inside the right half, as in ArrangerLifecycleTests.
private func startFrame(_ index: Int, on visible: Rect) -> Rect {
    index == 0
        ? Rect(x: visible.minX + 40, y: 80, width: 320, height: 232)
        : Rect(x: visible.minX + 730, y: 400, width: 150, height: 120)
}

extension Harness {
    /// A Space switch on one display as the live shell sees it: the notification's events, then a refresh, then the
    /// settle delay, so windows first seen on that Space are reported.
    mutating func switchDisplay(_ uuid: String, to space: UInt64) async -> [ArrangerEffect] {
        await fake.showSpace(space, onDisplay: uuid)
        var effects: [ArrangerEffect] = []
        for event in await inbox.take() {
            let next = arranger.handle(.event(event), now: now)
            effects += next
            for case .perform(let commands) in next { await fake.perform(commands) }
        }
        effects += await refresh()
        await fake.advance(by: .milliseconds(300))
        effects += await refresh()
        return effects
    }
}

/// D-16, D-25, SAFE-06: every (display, Space) desk survives layout.json and a relaunch, and each window comes back
/// on its own display and Space, in its own tile.
@Suite struct ArrangerMultiDeskRestoreTests {
    @Test func twoDisplaysWithTwoSpacesEachRestoreEveryDeskToItsOwnDisplayAndSpace() async throws {
        var harness = Harness()
        await harness.fake.setDisplays([displayA, displayB])
        await harness.fake.setSpacesAvailable(true)
        await harness.fake.addApp(FakeApp(pid: pid, bundleID: bundleID))
        for plan in plans {
            for (index, id) in plan.ids.enumerated() {
                await harness.fake.open(.standard(id: id, pid: pid, frame: startFrame(index, on: plan.visible), space: plan.key.spaceID))
            }
        }
        await harness.fake.showSpace(1, onDisplay: "A", notifies: false)
        await harness.fake.showSpace(3, onDisplay: "B", notifies: false)
        await harness.fake.refreshAll()
        _ = await harness.inbox.take()
        await harness.send(.inventory(await harness.fake.inventory()))

        // Dock the shown desks, then show each display's second Space and dock that one: A on 2, B on 4 at the end.
        for plan in plans {
            if let space = plan.key.spaceID, space == 2 || space == 4 {
                _ = await harness.switchDisplay(plan.key.displayUUID, to: space)
            }
            for id in plan.ids {
                try #require(harness.arranger.deskKey(of: ref(id)) == plan.key, "window \(id) is not on \(plan.key)")
                await harness.send(.command(.dock, focused: ref(id)))
            }
        }
        try #require(harness.arranger.displays.map(\.currentSpaceID) == [2, 4])

        let saved = harness.arranger.world
        #expect(Set(saved.desks.keys) == Set(plans.map(\.key)))
        var tiles: [WindowRef: Rect] = [:]
        for plan in plans {
            let desk = try #require(saved[plan.key])
            #expect(desk.tree.windows == plan.ids.map(ref), "desk \(plan.key): \(desk.tree.windows)")
            for id in plan.ids {
                let tile = try #require(await harness.frame(ref(id)))
                #expect(inside(tile, plan.visible), "window \(id) tile \(tile) is not on display \(plan.key.displayUUID)")
                tiles[ref(id)] = tile
            }
        }

        // Saved as LayoutStore saves it (no titles, sorted keys), read back as it loads.
        let snapshot = harness.arranger.snapshot
        let file = LayoutFile(world: snapshot.world.withoutTitleHints(), homeFrames: snapshot.homeFrames,
                              session: SessionRecord(cleanExit: true, launchedAt: Date()))
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .prettyPrinted]
        let decoded = try JSONDecoder().decode(LayoutFile.self, from: try encoder.encode(file))
        #expect(decoded == file)
        #expect(Set(decoded.world.desks.keys) == Set(plans.map(\.key)))

        // While Pane is not running, one window on each shown desk is moved out of its tile.
        let movedA = ref(3), movedB = ref(7)
        await harness.fake.userMove(movedA.windowID, to: Rect(x: 200, y: 200, width: 400, height: 300))
        await harness.fake.userMove(movedB.windowID, to: Rect(x: 1700, y: 200, width: 400, height: 300))
        _ = await harness.inbox.take()

        // Relaunch: a fresh Arranger restores the decoded layout at the first complete inventory.
        harness.arranger = Arranger()
        await harness.send(.restore(decoded.world, homeFrames: decoded.homeFrameMap))
        let restoredEffects = await harness.send(.inventory(await harness.fake.inventory()))
        #expect(harness.arranger.world == saved)
        #expect(setFrames(restoredEffects) == [movedA: tiles[movedA], movedB: tiles[movedB]],
                "only the two moved windows on shown desks are put back: \(setFrames(restoredEffects))")
        for plan in plans {
            #expect(harness.arranger.world[plan.key]?.tree.windows == plan.ids.map(ref))
            for id in plan.ids { #expect(harness.arranger.deskKey(of: ref(id)) == plan.key, "window \(id) restored off \(plan.key)") }
        }

        // The hidden desks were restored too: showing them moves nothing, and every window sits in its tile.
        let shownA = await harness.switchDisplay("A", to: 1)
        let shownB = await harness.switchDisplay("B", to: 3)
        #expect(setFrames(shownA + shownB).isEmpty, "showing a restored desk moved \(setFrames(shownA + shownB))")
        for plan in plans {
            for id in plan.ids {
                #expect(await harness.frame(ref(id)) == tiles[ref(id)], "window \(id) is not in its tile")
                #expect(harness.arranger.windows[ref(id).identity]?.displayUUID == plan.key.displayUUID)
            }
        }
        #expect(harness.arranger.world == saved)
    }
}

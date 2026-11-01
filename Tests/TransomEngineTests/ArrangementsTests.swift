import Foundation
import TransomEngine
import TransomModel
import Testing

private func world(_ display: String) throws -> World {
    var world = World()
    try world.addDesk(DeskKey(displayUUID: display, spaceID: nil))
    return world
}

private func encoded(_ file: LayoutFile) throws -> Data {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys, .prettyPrinted]
    return try encoder.encode(file)
}

/// D-09, OVER-06: arrangement identity, layout sets and layout.json byte stability.
@Suite struct ArrangementsTests {
    @Test func anArrangementIsTheSortedUniqueSetOfDisplays() {
        #expect(ArrangementID(["B", "A", "A"]).displayUUIDs == ["A", "B"])
        #expect(ArrangementID(["B", "A"]) == ArrangementID(["A", "B"]))
        #expect(ArrangementID([]).isUnknown)
        #expect(!ArrangementID(["A"]).isUnknown)
        #expect(ArrangementID(["A"]) < ArrangementID(["A", "B"]) && ArrangementID(["A", "B"]) < ArrangementID(["B"]))
    }

    @Test func theShortHashIsFourStableHexDigits() {
        #expect(ArrangementID(["B", "A"]).shortHash == "fa6c")  // FNV-1a 64 of "A,B" is fa6c9119a0a76766
        #expect(ArrangementID([]).shortHash == "cbf2")  // the FNV offset basis
    }

    @Test func aLayoutSetRoundTrips() throws {
        let set = LayoutSet(arrangement: ArrangementID(["B", "A"]), world: try world("A"), lastUsed: Date(timeIntervalSinceReferenceDate: 800_000_000.5))
        #expect(try JSONDecoder().decode(LayoutSet.self, from: JSONEncoder().encode(set)) == set)
    }

    @Test func layoutSetsAndSpacesAreStoredSortedAndEqualContentsGiveEqualBytes() throws {
        let session = SessionRecord(cleanExit: true, launchedAt: Date(timeIntervalSinceReferenceDate: 0))
        let sets = [
            LayoutSet(arrangement: ArrangementID(["C"]), world: try world("C"), lastUsed: Date(timeIntervalSinceReferenceDate: 1)),
            LayoutSet(arrangement: ArrangementID(["A", "B"]), world: try world("A"), lastUsed: Date(timeIntervalSinceReferenceDate: 2)),
        ]
        let spaces = [SavedSpace(id: 9, uuid: "U9"), SavedSpace(id: 3, uuid: "U3")]
        let file = LayoutFile(world: try world("A"), homeFrames: [:], session: session, arrangement: ArrangementID(["A"]), layoutSets: sets, spaces: spaces)
        let reversed = LayoutFile(
            world: try world("A"), homeFrames: [:], session: session, arrangement: ArrangementID(["A"]), layoutSets: sets.reversed(),
            spaces: spaces.reversed())
        #expect(file.layoutSets.map(\.arrangement) == [ArrangementID(["A", "B"]), ArrangementID(["C"])])
        #expect(file.spaces.map(\.id) == [3, 9])
        #expect(try encoded(file) == encoded(reversed))
        let decoded = try JSONDecoder().decode(LayoutFile.self, from: encoded(file))
        #expect(decoded == file)
        #expect(throws: Never.self) { try decoded.validate() }
    }

    @Test func layoutSetsKeepSixteenDroppingTheLeastRecentlyUsed() throws {
        var sets = LayoutSets()
        let empty = World()
        for n in 0..<17 { sets.store(empty, for: ArrangementID(["D\(n)"]), at: Date(timeIntervalSinceReferenceDate: Double((n * 7) % 17))) }
        #expect(sets.all.count == 16)
        // n = 0 was used at t = 0, the earliest.
        #expect(sets[ArrangementID(["D0"])] == nil)
        #expect(sets.all.map(\.arrangement) == sets.all.map(\.arrangement).sorted())
        sets.store(empty, for: ArrangementID(["D5"]), at: Date(timeIntervalSinceReferenceDate: 100))
        #expect(sets.all.count == 16 && sets[ArrangementID(["D5"])]?.lastUsed == Date(timeIntervalSinceReferenceDate: 100))
        #expect(sets.take(ArrangementID(["D5"])) != nil && sets[ArrangementID(["D5"])] == nil && sets.all.count == 15)
    }

    @Test func aSwitchIsSameKnownOrNew() throws {
        var sets = LayoutSets()
        let stored = try world("L")
        sets.store(stored, for: ArrangementID(["L"]), at: Date(timeIntervalSinceReferenceDate: 0))
        #expect(ArrangementSwitch.decide(from: ArrangementID(["L", "D"]), to: ArrangementID(["D", "L"]), sets: sets) == .same)
        #expect(ArrangementSwitch.decide(from: ArrangementID(["D", "L"]), to: ArrangementID(["L"]), sets: sets) == .known(try #require(sets[ArrangementID(["L"])])))
        #expect(ArrangementSwitch.decide(from: ArrangementID(["L"]), to: ArrangementID(["E", "L"]), sets: sets) == .new)
    }

    @Test func theCascadeStepsTwentyFourPointsFromTheStart() {
        let start = Point(x: 4, y: 29)
        let frames = ArrangementSwitch.cascade(
            frames: [Rect(x: 900, y: 500, width: 400, height: 300), Rect(x: 0, y: 0, width: 200, height: 100)], from: start,
            in: Rect(x: 0, y: 25, width: 1440, height: 875))
        #expect(frames == [Rect(x: 4, y: 29, width: 400, height: 300), Rect(x: 28, y: 53, width: 200, height: 100)])
    }

    /// The invariant: a World stored under arrangement X and re-applied by switching back to X, with the same tracked
    /// windows, is the stored World: every window in its tile, every desk present.
    @Test func switchingBackToAnArrangementAppliesItsStoredWorldUnchanged() throws {
        let visibleL = Rect(x: 0, y: 25, width: 1440, height: 875), visibleD = Rect(x: 1440, y: 25, width: 1920, height: 1055)
        let displayL = DisplayInfo(uuid: "L", frame: Rect(x: 0, y: 0, width: 1440, height: 900), visibleFrame: visibleL, currentSpaceID: nil)
        let displayD = DisplayInfo(uuid: "D", frame: Rect(x: 1440, y: 0, width: 1920, height: 1080), visibleFrame: visibleD, currentSpaceID: nil)
        func window(_ id: UInt32) -> WindowRef { WindowRef(identity: WindowIdentity(windowID: id, pid: 7, bundleID: "com.example.invariant")) }
        func info(_ id: UInt32, _ frame: Rect, on uuid: String) -> WindowInfo { WindowInfo(window: window(id), frame: frame, state: .present, displayUUID: uuid) }
        let start = [
            info(1, Rect(x: 40, y: 80, width: 320, height: 232), on: "L"), info(4, Rect(x: 730, y: 400, width: 150, height: 120), on: "L"),
            info(2, Rect(x: 1480, y: 80, width: 320, height: 232), on: "D"), info(3, Rect(x: 2170, y: 400, width: 150, height: 120), on: "D"),
        ]
        func inventory(_ displays: [DisplayInfo], _ windows: [WindowInfo]) -> WindowInventory {
            WindowInventory(displays: displays, windows: windows, initialRefreshComplete: true)
        }
        var arranger = Arranger()
        let now = ContinuousClock.now
        _ = arranger.handle(.inventory(inventory([displayL, displayD], start)), now: now)
        for id: UInt32 in [1, 4, 2, 3] { _ = arranger.handle(.command(.dock, focused: window(id)), now: now) }
        let stored = arranger.world
        try #require(stored.desks.values.map(\.tree.windows.count).sorted() == [2, 2])

        // macOS moved D's windows onto L.
        let moved = start.map { $0.displayUUID == "D" ? info($0.window.windowID, Rect(x: $0.frame.minX - 1440, y: $0.frame.minY, width: $0.frame.width, height: $0.frame.height), on: "L") : $0 }
        _ = arranger.handle(.displaysSettling, now: now)
        _ = arranger.handle(.displaysSettled(ArrangementID(["L"]), names: [:], inventory: inventory([displayL], moved)), now: now)
        #expect(arranger.layoutSets[ArrangementID(["D", "L"])]?.world == stored)
        _ = arranger.handle(.displaysSettling, now: now)
        _ = arranger.handle(.displaysSettled(ArrangementID(["D", "L"]), names: [:], inventory: inventory([displayL, displayD], start)), now: now)
        #expect(arranger.world == stored)
        #expect(arranger.layoutSets[ArrangementID(["D", "L"])] == nil && arranger.layoutSets[ArrangementID(["L"])] != nil)
    }
}

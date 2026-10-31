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
}

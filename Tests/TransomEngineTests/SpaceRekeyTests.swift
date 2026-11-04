import Foundation
import TransomEngine
import TransomModel
import Testing

private let display = "A"

private func key(_ space: UInt64?) -> DeskKey { DeskKey(displayUUID: display, spaceID: space) }

private func ref(_ id: UInt32) -> WindowRef {
    WindowRef(identity: WindowIdentity(windowID: id, pid: 300, bundleID: "com.example.editor"), titleHint: "")
}

/// One desk per Space ID, desk n holding window n docked.
private func world(_ spaces: [UInt64]) throws -> World {
    var world = World()
    var history = UndoHistory()
    for space in spaces {
        try world.addDesk(key(space))
        try world.edit(key(space), history: &history) { desk, ids throws(LayoutError) in
            try desk.tree.insert(ref(UInt32(space)), at: .left, of: .desktop, ids: &ids)
        }
    }
    return world
}

/// D-13: saved desks re-key to the current runtime ID of their Space's UUID.
@Suite struct SpaceRekeyTests {
    @Test func desksMoveToTheCurrentIDOfTheirUUIDWithTreesIntact() throws {
        let saved = try world([3, 4])
        let result = try SpaceRekey.rekey(saved, saved: [3: "U3", 4: "U4"], current: ["U3": 7, "U4": 9])
        #expect(result.world.desks.keys.sorted() == [key(7), key(9)])
        #expect(result.world[key(7)] == saved[key(3)])
        #expect(result.world[key(9)] == saved[key(4)])
        #expect(result.rekeyed == 2)
        #expect(result.unmatched.isEmpty && result.quarantined.isEmpty)
    }

    @Test func aDeskWithoutASpaceIsUntouched() throws {
        var saved = World()
        try saved.addDesk(key(nil))
        let result = try SpaceRekey.rekey(saved, saved: [:], current: ["U3": 3])
        #expect(result.world == saved)
        #expect(result.rekeyed == 0)
    }

    @Test func theTableListsEachReferencedSpaceSortedOnce() throws {
        let table = SpaceRekey.table(for: try world([4, 3]), uuids: [3: "U3", 4: "U4", 8: "U8"])
        #expect(table == [SavedSpace(id: 3, uuid: "U3"), SavedSpace(id: 4, uuid: "U4")])
    }

    /// CR-02: a Space only a layout set uses still gets its UUID on disk.
    @Test func theTableListsTheSpacesOfEveryLayoutSet() throws {
        let set = LayoutSet(arrangement: ArrangementID([display, "B"]), world: try world([4, 6]), lastUsed: Date(timeIntervalSinceReferenceDate: 0))
        let table = SpaceRekey.table(for: try world([3]), layoutSets: [set], uuids: [3: "U3", 4: "U4", 6: "U6", 8: "U8"])
        #expect(table == [SavedSpace(id: 3, uuid: "U3"), SavedSpace(id: 4, uuid: "U4"), SavedSpace(id: 6, uuid: "U6")])
    }

    private func view(_ slot: Int, _ space: UInt64?) -> SavedView {
        SavedView(slot: ViewSlot(slot)!, desk: key(space), home: true, windows: [])
    }

    /// A view's desk can be a Space no desk uses any more: its UUID is listed all the same.
    @Test func theTableListsTheSpacesOfSavedViews() throws {
        let table = SpaceRekey.table(for: try world([3]), views: [view(1, 4), view(2, nil)], uuids: [3: "U3", 4: "U4", 8: "U8"])
        #expect(table == [SavedSpace(id: 3, uuid: "U3"), SavedSpace(id: 4, uuid: "U4")])
    }

    /// A view's desk follows its Space like a desk, and one whose Space is gone keeps its saved key (D-05's N17 path).
    @Test func aViewsDeskIsRekeyedWithTheSameMapping() throws {
        let raw: [[String: Any]] = [["Display Identifier": display, "Spaces": [["ManagedSpaceID": 7, "type": 0, "uuid": "U3"], ["ManagedSpaceID": 9, "type": 0, "uuid": "U4"]]]]
        let live = SpacesSnapshot.parse(raw, mainDisplayUUID: display, separateSpaces: true)
        let file = LayoutFile(
            world: try world([3]), homeFrames: [:], session: SessionRecord(cleanExit: true, launchedAt: Date(timeIntervalSinceReferenceDate: 0)),
            arrangement: ArrangementID([display]), spaces: [SavedSpace(id: 3, uuid: "U3"), SavedSpace(id: 4, uuid: "U4"), SavedSpace(id: 5, uuid: "GONE")],
            views: [view(1, 3), view(2, 4), view(3, 5), view(4, nil)])
        let loaded = try SpaceRekey.rekey(file, live: live)
        #expect(loaded.result.world.desks.keys.sorted() == [key(7)])
        #expect(loaded.views.map(\.desk) == [key(7), key(9), key(5), key(nil)])
        #expect(loaded.views.map(\.slot.number) == [1, 2, 3, 4])
    }

    /// CR-02: after a reboot renumbers the Spaces, every layout set's desks move to their Space's new ID, like the World's.
    @Test func everyLayoutSetIsRekeyedWithTheWorld() throws {
        let raw: [[String: Any]] = [["Display Identifier": display, "Spaces": [["ManagedSpaceID": 7, "type": 0, "uuid": "U3"], ["ManagedSpaceID": 9, "type": 0, "uuid": "U4"]]]]
        let live = SpacesSnapshot.parse(raw, mainDisplayUUID: display, separateSpaces: true)
        let set = LayoutSet(arrangement: ArrangementID([display, "B"]), world: try world([4]), lastUsed: Date(timeIntervalSinceReferenceDate: 0))
        let file = LayoutFile(
            world: try world([3]), homeFrames: [:], session: SessionRecord(cleanExit: true, launchedAt: Date(timeIntervalSinceReferenceDate: 0)),
            arrangement: ArrangementID([display]), layoutSets: [set], spaces: [SavedSpace(id: 3, uuid: "U3"), SavedSpace(id: 4, uuid: "U4")])
        let loaded = try SpaceRekey.rekey(file, live: live)
        #expect(loaded.result.world.desks.keys.sorted() == [key(7)])
        #expect(loaded.layoutSets.map(\.arrangement) == [set.arrangement])
        #expect(loaded.layoutSets.first?.world.desks.keys.sorted() == [key(9)], "the layout set kept its previous-boot Space ID")
        #expect(loaded.layoutSets.first?.world[key(9)] == set.world[key(4)])
        #expect(loaded.setsQuarantined.isEmpty)
    }

    @Test func aDeskWhoseSpaceIsGoneKeepsItsKeyDormant() throws {
        let saved = try world([5])
        let result = try SpaceRekey.rekey(saved, saved: [5: "GONE"], current: ["U3": 3])
        #expect(result.world == saved)
        #expect(result.unmatched == [key(5)])
        #expect(result.quarantined.isEmpty)
        #expect(result.rekeyed == 0)
    }

    @Test func aGoneSpacesIDReusedByANewSpaceIsQuarantined() throws {
        let saved = try world([5])
        let result = try SpaceRekey.rekey(saved, saved: [5: "GONE"], current: ["NEW": 5])
        #expect(result.world.desks.isEmpty)
        #expect(result.quarantined == [key(5)])
        #expect(result.unmatched.isEmpty)
    }

    @Test func aQuarantinedDeskIsNeverMergedIntoTheLiveSpacesDesk() throws {
        // Space NEW moved from 3 to 5; the desk saved under 5 belonged to a deleted Space.
        let saved = try world([3, 5])
        let result = try SpaceRekey.rekey(saved, saved: [3: "NEW", 5: "GONE"], current: ["NEW": 5])
        #expect(result.world.desks.keys.sorted() == [key(5)])
        #expect(result.world[key(5)] == saved[key(3)])
        #expect(result.quarantined == [key(5)])
        #expect(result.rekeyed == 1)
    }

    @Test func twoDesksSwappingIDsNeverCollide() throws {
        let saved = try world([3, 4])
        let result = try SpaceRekey.rekey(saved, saved: [3: "U3", 4: "U4"], current: ["U3": 4, "U4": 3])
        #expect(result.world[key(4)] == saved[key(3)])
        #expect(result.world[key(3)] == saved[key(4)])
        #expect(result.rekeyed == 2)
        #expect(result.unmatched.isEmpty && result.quarantined.isEmpty)
    }

    @Test func aDefaultUUIDMatchesTheLiveDesktop1() throws {
        let raw: [[String: Any]] = [["Display Identifier": display, "Spaces": [["ManagedSpaceID": 2, "type": 0, "uuid": ""]]]]
        let live = SpacesSnapshot.parse(raw, mainDisplayUUID: display, separateSpaces: true)
        let file = LayoutFile(
            world: try world([1]), homeFrames: [:], session: SessionRecord(cleanExit: true, launchedAt: Date(timeIntervalSinceReferenceDate: 0)),
            spaces: [SavedSpace(id: 1, uuid: "default:\(display)")])
        let decoded = try JSONDecoder().decode(LayoutFile.self, from: JSONEncoder().encode(file))
        #expect(decoded == file)
        let result = try SpaceRekey.rekey(decoded.world, saved: decoded.spaceMap, current: live.idByUUID)
        #expect(result.world.desks.keys.sorted() == [key(2)])
    }
}

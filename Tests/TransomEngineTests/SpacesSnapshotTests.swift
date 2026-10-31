import Foundation
import Testing
import TransomEngine

/// Tests/TransomEngineTests/SpacesSnapshotTests.swift -> Tests/TransomEngineTests/Fixtures/Spaces.
private let fixtureDirectory = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent().appendingPathComponent("Fixtures/Spaces")

private func fixture(_ name: String) throws -> [[String: Any]] {
    let data = try Data(contentsOf: fixtureDirectory.appendingPathComponent(name))
    return try #require(try JSONSerialization.jsonObject(with: data) as? [[String: Any]])
}

private let builtIn = "37D8832A-2D66-02CA-B9F7-8F30A301B230"

@Suite struct SpacesSnapshotTests {
    @Test func separateSpacesKeepTheirOrderAndDesktopNumbers() throws {
        let snapshot = SpacesSnapshot.parse(try fixture("separate-one-display.json"), mainDisplayUUID: builtIn, separateSpaces: true)
        let display = try #require(snapshot.displays.first)
        #expect(snapshot.displays.count == 1)
        #expect(display.displayUUID == builtIn)
        #expect(display.current == 3)
        #expect(display.spaces.map(\.id) == [3, 4, 149])
        #expect(display.spaces.map(\.index) == [1, 2, 3])
        #expect(display.spaces.allSatisfy { $0.kind == .desktop && $0.displayUUID == builtIn })
        #expect(display.spaces.map(\.uuid).first == "7A041E06-6227-4718-86AD-2EF8A8D6E7DA")
        #expect(snapshot.spaceCount == 3)
        #expect(snapshot.uuidByID[149] == "6C5CB59E-91B2-4E0F-8C3D-5A7B9E1F2D40")
        #expect(snapshot.idByUUID["EF244C48-0D4C-4A55-9A0A-3C1B2A5E6F71"] == 4)
        #expect(snapshot.skipped == 0)
    }

    @Test func spansModeMapsMainToTheMainDisplay() throws {
        let snapshot = SpacesSnapshot.parse(try fixture("spans-main.json"), mainDisplayUUID: builtIn, separateSpaces: false)
        let display = try #require(snapshot.displays.first)
        #expect(!snapshot.separateSpaces)
        #expect(display.displayUUID == builtIn)
        #expect(display.current == 2)
        #expect(display.spaces.map(\.id) == [1, 2])
        #expect(display.spaces.allSatisfy { $0.displayUUID == builtIn })
    }

    @Test func anEmptyUUIDBecomesTheDisplaysDefaultKey() throws {
        let display = "5E0B7C1A-3F2D-4B6E-9A8C-1D2E3F4A5B6C"
        let snapshot = SpacesSnapshot.parse(try fixture("empty-uuid.json"), mainDisplayUUID: builtIn, separateSpaces: true)
        let spaces = try #require(snapshot.displays.first).spaces
        #expect(spaces.map(\.uuid) == ["default:\(display)", "C2A1D3E4-2222-4333-8444-A55566667777"])
        #expect(spaces.map(\.displayUUID) == [display, display])
        #expect(snapshot.idByUUID["default:\(display)"] == 1)
    }

    @Test func fullScreenIsKeptWithIndexZeroAndSystemSpacesAreSkipped() throws {
        let snapshot = SpacesSnapshot.parse(try fixture("fullscreen.json"), mainDisplayUUID: builtIn, separateSpaces: true)
        let display = try #require(snapshot.displays.first)
        #expect(display.current == 12)
        #expect(display.spaces.map(\.id) == [3, 12, 4])
        #expect(display.spaces.map(\.kind) == [.desktop, .fullScreen, .desktop])
        #expect(display.spaces.map(\.index) == [1, 0, 2])
        #expect(snapshot.skipped == 0, "type 2 is skipped silently, not counted as malformed")
    }

    /// A Space's own "Display Identifier" names where it wants to return, not where it is (06-RESEARCH F1).
    @Test func aSpaceLandsUnderTheDisplayThatListsItNotItsOwnDisplayKey() {
        let raw: [[String: Any]] = [
            ["Display Identifier": "A", "Spaces": [["ManagedSpaceID": 1, "type": 0, "uuid": "u1"]]],
            ["Display Identifier": "B", "Spaces": [["Display Identifier": "A", "ManagedSpaceID": 2, "type": 0, "uuid": "u2"]]],
        ]
        let snapshot = SpacesSnapshot.parse(raw, mainDisplayUUID: "A", separateSpaces: true)
        #expect(snapshot.displays.map(\.displayUUID) == ["A", "B"])
        #expect(snapshot.displays[1].spaces.map(\.id) == [2])
        #expect(snapshot.displays[1].spaces.first?.displayUUID == "B")
        #expect(snapshot.displays[1].spaces.first?.index == 1)
    }

    @Test func malformedAndUnknownEntriesAreSkippedAndCounted() {
        let raw: [[String: Any]] = [[
            "Display Identifier": "A",
            "Current Space": ["ManagedSpaceID": 0],
            "Spaces": [
                ["ManagedSpaceID": "3", "type": 0, "uuid": "string-id"],
                ["ManagedSpaceID": 0, "type": 0, "uuid": "zero-id"],
                ["id64": 5, "type": 0, "uuid": "id64-only"],
                ["ManagedSpaceID": 6, "type": 9, "uuid": "unknown-type"],
                ["ManagedSpaceID": 7, "type": 0],
            ],
        ]]
        let snapshot = SpacesSnapshot.parse(raw, mainDisplayUUID: "A", separateSpaces: true)
        #expect(snapshot.displays.first?.spaces.map(\.uuid) == ["id64-only"])
        #expect(snapshot.displays.first?.current == nil)
        #expect(snapshot.skipped == 4)
    }

    @Test func spacesPerDisplayAreCapped() {
        let spaces: [[String: Any]] = (1...40).map { ["ManagedSpaceID": $0, "type": 0, "uuid": "u\($0)"] }
        let snapshot = SpacesSnapshot.parse([["Display Identifier": "A", "Spaces": spaces]], mainDisplayUUID: "A", separateSpaces: true)
        #expect(snapshot.spaceCount == SpacesSnapshot.maxSpacesPerDisplay)
    }
}

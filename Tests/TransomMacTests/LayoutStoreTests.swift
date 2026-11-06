import Foundation
import TransomEngine
import TransomMac
import TransomModel
import Testing

private let key = DeskKey(displayUUID: "main", spaceID: nil)

private func ref(_ id: UInt32, title: String = "") -> WindowRef {
    WindowRef(identity: WindowIdentity(windowID: id, pid: 300, bundleID: "com.example.editor"), titleHint: title)
}

/// 1 docked, filling the desk, with 2 floating; both windows carry a title.
private func sampleFile() throws -> LayoutFile {
    var world = World()
    try world.addDesk(key)
    var history = UndoHistory()
    try world.edit(key, history: &history) { desk, ids throws(LayoutError) in
        try desk.tree.applyDrop(.layoutEdge(.right), window: ref(1, title: "Secret plan.txt"), ids: &ids)
        try desk.desktop.add(ref(2, title: "Bank statement"), frame: Rect(x: 900, y: 300, width: 400, height: 300))
    }
    return LayoutFile(
        world: world, homeFrames: [ref(2).identity: Rect(x: 50, y: 60, width: 400, height: 300)],
        session: SessionRecord(cleanExit: false, launchedAt: Date(timeIntervalSinceReferenceDate: 800_000_000.25)))
}

/// 8.1.1 D-16: the main desk holds [window 1 .5 | empty area .5]; NodeIDs 1 (the split), 2 and 3.
private func emptyAreaFile() throws -> LayoutFile {
    let tree = try LayoutTree(
        root: NodeID(raw: 1),
        nodes: [
            NodeID(raw: 1): .split(axis: .horizontal, children: [NodeID(raw: 2), NodeID(raw: 3)], weights: [0.5, 0.5]),
            NodeID(raw: 2): .panel(ref(1, title: "Notes")), NodeID(raw: 3): .spacer,
        ],
        states: [ref(1).identity: .present])
    let world = try World(ids: IDSource(next: 10), desks: [key: Desk(tree: tree)])
    return LayoutFile(world: world, homeFrames: [:], session: SessionRecord(cleanExit: false, launchedAt: Date(timeIntervalSinceReferenceDate: 800_000_000)))
}

/// D-16, T-03-15..18, D-10: layout.json is validated whole on load, written atomically and owner-only with titles,
/// and a newer Transom's file is never overwritten.
@MainActor @Suite struct LayoutStoreTests {
    /// A fresh temporary directory per test, removed afterwards. Never the user's real Application Support.
    final class Directory {
        let url = FileManager.default.temporaryDirectory.appending(path: "transom-layout-\(UUID().uuidString)", directoryHint: .isDirectory)
        var file: URL { url.appending(path: LayoutStore.fileName) }
        /// The rejected files set aside.
        var corrupted: [URL] {
            ((try? FileManager.default.contentsOfDirectory(atPath: url.path)) ?? []).filter { $0.hasPrefix(LayoutStore.fileName + ".corrupt-") }.sorted().map { url.appending(path: $0) }
        }
        init() { try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true) }
        deinit { try? FileManager.default.removeItem(at: url) }
        func write(_ text: String) throws { try Data(text.utf8).write(to: file) }
        func text() throws -> String { try String(contentsOf: file, encoding: .utf8) }
    }

    /// `sampleFile()`'s JSON with `target` replaced, so each bad file differs from a good one in one place.
    static func edited(_ target: String, _ replacement: String) throws -> String {
        let dir = Directory()
        try LayoutStore(directory: dir.url).save(try sampleFile())
        let text = try dir.text()
        precondition(text.contains(target), "sample no longer contains \(target)")
        return text.replacingOccurrences(of: target, with: replacement)
    }

    @Test func savedContentsLoadInAFreshStoreSortedAndOwnerOnly() throws {
        let dir = Directory()
        let file = try sampleFile()
        #expect(try LayoutStore(directory: dir.url).save(file))
        let text = try dir.text()
        #expect(text.contains("\"schemaVersion\" : \(LayoutFile.schemaVersion)"))
        let homeFrames = try #require(text.range(of: "\"homeFrames\"")), session = try #require(text.range(of: "\"session\""))
        let world = try #require(text.range(of: "\"world\""))
        #expect(homeFrames.lowerBound < session.lowerBound && session.lowerBound < world.lowerBound)
        let permissions = try FileManager.default.attributesOfItem(atPath: dir.file.path)[.posixPermissions] as? Int
        #expect(permissions == 0o600)

        let fresh = LayoutStore(directory: dir.url)
        fresh.load()
        #expect(fresh.loadError == nil)
        #expect(fresh.contents == file)
    }

    /// WR-04: a backup is a byte-for-byte, owner-only copy beside the file, and a later one never replaces it.
    @Test func aBackupCopiesTheFileAndKeepsEarlierBackups() throws {
        let dir = Directory()
        let store = LayoutStore(directory: dir.url)
        #expect(!store.backUp("pre-rekey"), "no file, no backup")
        try store.save(try sampleFile())
        let original = try Data(contentsOf: dir.file)
        #expect(store.backUp("pre-rekey", at: Date(timeIntervalSince1970: 100)))
        #expect(store.backUp("pre-rekey", at: Date(timeIntervalSince1970: 200)))
        for seconds in [100, 200] {
            let copy = dir.url.appending(path: "\(LayoutStore.fileName).pre-rekey-\(seconds)")
            #expect(try Data(contentsOf: copy) == original)
            #expect(try FileManager.default.attributesOfItem(atPath: copy.path)[.posixPermissions] as? Int == 0o600)
        }
    }

    /// WR-09: `load` rejects a file over the cap whole, so `save` never writes one: the last good file stays.
    @Test func aSaveOverTheSizeCapKeepsTheLastGoodFile() throws {
        let dir = Directory()
        let store = LayoutStore(directory: dir.url, saveLimit: 8192)
        try store.save(try sampleFile())
        let good = try dir.text()
        var world = World()
        try world.addDesk(key)
        try world.reflow(key) { desk, ids throws(LayoutError) in
            try desk.tree.applyDrop(.layoutEdge(.right), window: ref(1, title: String(repeating: "x", count: 8192)), ids: &ids)
        }
        let huge = LayoutFile(world: world, homeFrames: [:], session: SessionRecord(cleanExit: false, launchedAt: .now))
        #expect(throws: LayoutStoreError.self) { try store.save(huge) }
        #expect(try dir.text() == good)
    }

    /// D-10 (supersedes T-03-17): titles are written, so windows can be re-matched after a relaunch, and the file
    /// stays owner-only.
    @Test func titlesAreWrittenAndTheFileIsOwnerOnly() throws {
        let dir = Directory()
        try LayoutStore(directory: dir.url).save(try sampleFile())
        let text = try dir.text()
        #expect(text.contains("Secret plan.txt") && text.contains("Bank statement"))
        #expect(try FileManager.default.attributesOfItem(atPath: dir.file.path)[.posixPermissions] as? Int == 0o600)
    }

    @Test func noFileStartsEmptyWithoutAnError() {
        let dir = Directory()
        let store = LayoutStore(directory: dir.url)
        store.load()
        #expect(store.contents == nil)
        #expect(store.loadError == nil)
        #expect(!store.savingDisabled)
        #expect(dir.corrupted.isEmpty)
    }

    /// `sampleFile()`'s JSON with top-level keys changed, for schema 2's keys, which `edited` cannot reach cleanly.
    static func mutated(_ change: ([String: Any]) -> [String: Any]) throws -> String {
        let dir = Directory()
        try LayoutStore(directory: dir.url).save(try sampleFile())
        let json = try #require(try JSONSerialization.jsonObject(with: Data(contentsOf: dir.file)) as? [String: Any])
        return String(decoding: try JSONSerialization.data(withJSONObject: change(json), options: [.sortedKeys]), as: UTF8.self)
    }

    /// A layout set holding `json`'s own World.
    static func layoutSet(_ displays: [String], _ json: [String: Any]) -> [String: Any] {
        ["arrangement": ["displayUUIDs": displays], "world": json["world"]!, "lastUsed": 800_000_000]
    }

    static func setting(_ key: String, _ value: @escaping ([String: Any]) -> Any) -> () throws -> String {
        { try mutated { json in json.merging([key: value(json)]) { $1 } } }
    }

    /// One saved view as layout.json holds it.
    static func view(_ slot: Int, windows: [UInt32] = []) -> [String: Any] {
        [
            "slot": slot, "desk": ["displayUUID": "main"], "home": windows.isEmpty,
            "windows": windows.map { ["windowID": $0, "pid": 300, "bundleID": "com.example.editor"] as [String: Any] },
        ]
    }

    nonisolated static let badFiles: [(String, @MainActor @Sendable () throws -> String)] = [
        ("too large", { try edited("\"schemaVersion\" : 5", "\"schemaVersion\" : 5" + String(repeating: " ", count: World.maxEncodedBytes)) }),
        ("malformed", { #"{"schemaVersion":1,"world":"# }),
        ("duplicate window", { try edited("\"windowID\" : 2", "\"windowID\" : 1") }),
        // JSON has no NaN; an overflowing literal is the nearest a file gets to a non-finite frame.
        ("non-finite home frame", { try edited("\"x\" : 50", "\"x\" : 1e400") }),
        ("huge home frame", { try edited("\"width\" : 400,\n        \"x\" : 50", "\"width\" : 2e6,\n        \"x\" : 50") }),
        ("duplicate home frame", { try edited("\"homeFrames\" : [", "\"homeFrames\" : [{\"frame\":{\"x\":1,\"y\":1,\"width\":10,\"height\":10},\"window\":{\"bundleID\":\"com.example.editor\",\"pid\":300,\"windowID\":2}},") }),
        ("session missing a field", { try edited("\"cleanExit\" : false,", "") }),
        ("non-finite wanted frame", { try edited("\"wantedFrames\" : [", "\"wantedFrames\" : [{\"frame\":{\"x\":1e400,\"y\":1,\"width\":10,\"height\":10},\"window\":{\"bundleID\":\"com.example.editor\",\"pid\":300,\"windowID\":2}}") }),
        ("huge wanted frame", { try edited("\"wantedFrames\" : [", "\"wantedFrames\" : [{\"frame\":{\"x\":1,\"y\":1,\"width\":2e6,\"height\":10},\"window\":{\"bundleID\":\"com.example.editor\",\"pid\":300,\"windowID\":2}}") }),
        ("unsorted arrangement", { try setting("arrangement") { _ in ["displayUUIDs": ["B", "A"]] }() }),
        ("duplicate layout-set arrangement", { try setting("layoutSets") { [layoutSet(["A"], $0), layoutSet(["A"], $0)] }() }),
        ("unsorted layout-set arrangement", { try setting("layoutSets") { [layoutSet(["B", "A"], $0)] }() }),
        ("17 layout sets", { try setting("layoutSets") { json in (0..<17).map { layoutSet([String(format: "D%02d", $0)], json) } }() }),
        ("invalid layout-set world", {
            try setting("layoutSets") { json in
                var world = json["world"] as! [String: Any]
                world["ids"] = ["next": 0]
                return [["arrangement": ["displayUUIDs": ["A"]], "world": world, "lastUsed": 0]]
            }()
        }),
        ("duplicate space ID", { try setting("spaces") { _ in [["id": 3, "uuid": "U3"], ["id": 3, "uuid": "U4"]] }() }),
        ("empty space uuid", { try setting("spaces") { _ in [["id": 3, "uuid": ""]] }() }),
        ("duplicate view slot", { try setting("views") { _ in [view(3), view(3)] }() }),
        ("unsorted view slots", { try setting("views") { _ in [view(4), view(3)] }() }),
        ("ten views", { try setting("views") { _ in (1...9).map { view($0) } + [view(9)] }() }),
        ("view slot out of range", { try setting("views") { _ in [view(10)] }() }),
        ("unsorted view windows", { try setting("views") { _ in [view(3, windows: [2, 1])] }() }),
        ("duplicate view window", { try setting("views") { _ in [view(3, windows: [1, 1])] }() }),
        ("duplicate wanted frame", { try edited("\"wantedFrames\" : [", "\"wantedFrames\" : [{\"frame\":{\"x\":1,\"y\":1,\"width\":10,\"height\":10},\"window\":{\"bundleID\":\"com.example.editor\",\"pid\":300,\"windowID\":2}},{\"frame\":{\"x\":5,\"y\":5,\"width\":10,\"height\":10},\"window\":{\"bundleID\":\"com.example.editor\",\"pid\":300,\"windowID\":2}}") }),
        // 8.1.1 D-16, T-08.1.1-25: empty-area shapes no edit makes are set aside, never repaired.
        ("empty-area root", { try forgedTree { tree in tree = ["root": 3, "nodes": ["3": ["spacer": [:]]], "states": []] } }),
        ("two adjacent empty areas", {
            try forgedTree { tree in
                var nodes = tree["nodes"] as! [String: Any]
                nodes["1"] = ["split": ["axis": "horizontal", "children": [2, 3, 4], "weights": [0.5, 0.25, 0.25]]]
                nodes["4"] = ["spacer": [:]]
                tree["nodes"] = nodes
            }
        }),
        ("split with no window", {
            try forgedTree { tree in
                var nodes = tree["nodes"] as! [String: Any]
                nodes["1"] = ["split": ["axis": "horizontal", "children": [2, 4], "weights": [0.5, 0.5]]]
                nodes["4"] = ["split": ["axis": "vertical", "children": [3, 5], "weights": [0.5, 0.5]]]
                nodes["5"] = ["spacer": [:]]
                tree["nodes"] = nodes
            }
        }),
    ]

    /// `emptyAreaFile()`'s JSON with its main desk's tree changed.
    static func forgedTree(_ change: (inout [String: Any]) -> Void) throws -> String {
        let dir = Directory()
        try LayoutStore(directory: dir.url).save(try emptyAreaFile())
        var json = try #require(try JSONSerialization.jsonObject(with: Data(contentsOf: dir.file)) as? [String: Any])
        var world = json["world"] as! [String: Any]
        var desks = world["desks"] as! [[String: Any]]
        var desk = desks[0]["desk"] as! [String: Any]
        var tree = desk["tree"] as! [String: Any]
        change(&tree)
        desk["tree"] = tree
        desks[0]["desk"] = desk
        world["desks"] = desks
        json["world"] = world
        return String(decoding: try JSONSerialization.data(withJSONObject: json, options: [.sortedKeys]), as: UTF8.self)
    }

    @Test(arguments: badFiles)
    func aBadFileIsRejectedWholeAndMovedAside(name: String, text: @MainActor @Sendable () throws -> String) throws {
        let text = try text()
        let dir = Directory()
        let older = dir.url.appending(path: LayoutStore.fileName + ".corrupt-100")
        try Data("older".utf8).write(to: older)
        try dir.write(text)
        let store = LayoutStore(directory: dir.url)
        store.load()
        #expect(store.contents == nil, "\(name) was loaded")
        #expect(store.loadError != nil, "\(name) was accepted")
        #expect(!store.savingDisabled, "\(name) disabled saving")
        #expect(!FileManager.default.fileExists(atPath: dir.file.path), "\(name) left in place")
        #expect(try String(contentsOf: older, encoding: .utf8) == "older", "\(name) replaced an earlier copy")
        let moved = try #require(dir.corrupted.first { $0.lastPathComponent != older.lastPathComponent })
        #expect(try String(contentsOf: moved, encoding: .utf8) == text, "\(name) not moved aside")
    }

    /// WR-08: a rejected file that can't be moved aside is still the only copy, so nothing is saved over it.
    @Test func aRejectedFileThatCannotMoveTurnsSavingOff() throws {
        let dir = Directory()
        try dir.write("not json")
        try FileManager.default.setAttributes([.posixPermissions: 0o500], ofItemAtPath: dir.url.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: dir.url.path) }
        let store = LayoutStore(directory: dir.url)
        store.load()
        #expect(store.contents == nil)
        #expect(store.savingDisabled)
        #expect(try store.save(try sampleFile()) == false)
        #expect(try dir.text() == "not json")
    }

    @Test func rejectionsNameTheirReason() throws {
        let dir = Directory()
        let store = LayoutStore(directory: dir.url)
        let large = try Self.badFiles[0].1()
        try dir.write(large)
        store.load()
        #expect(store.loadError == .tooLarge(large.utf8.count))
        try dir.write(try Self.badFiles[4].1())
        store.load()
        guard case .invalidEntry? = store.loadError else {
            Issue.record("a huge home frame gave \(String(describing: store.loadError))")
            return
        }
    }

    @Test func aNewerFileIsKeptUntouchedAndNeverOverwritten() throws {
        let dir = Directory()
        let newer = try Self.edited("\"schemaVersion\" : 5", "\"schemaVersion\" : 6")
        try dir.write(newer)
        let store = LayoutStore(directory: dir.url)
        store.load()
        #expect(store.contents == nil)
        #expect(store.loadError == .newerVersion(6))
        #expect(store.savingDisabled)
        #expect(try dir.text() == newer)
        #expect(dir.corrupted.isEmpty)
        #expect(try store.save(try sampleFile()) == false)
        #expect(try dir.text() == newer, "a save overwrote a newer Transom's layout")
    }
}

/// G-03-11, SAFE-06: wanted frames in layout.json. A file from before them loads with none.
extension LayoutStoreTests {
    /// The sample's World as a legacy file loads: a floater with a home frame was parked by a hidden Desktop, so the
    /// home frame becomes its stored frame (8.1.1 D-02, WR-01).
    static func withHomeFrameFloating(_ world: World) throws -> World {
        var world = world
        try world.recordFloatingFrame(Rect(x: 50, y: 60, width: 400, height: 300), for: ref(2))
        return world
    }

    @Test func aFileFromBeforeWantedFramesLoadsWithNone() throws {
        let dir = Directory()
        let sample = try sampleFile()
        try LayoutStore(directory: dir.url).save(sample)
        var json = try #require(try JSONSerialization.jsonObject(with: Data(contentsOf: dir.file)) as? [String: Any])
        // A schema-1 file from before 03-26: no wantedFrames and none of schema 2's keys.
        for key in ["wantedFrames", "arrangement", "layoutSets", "spaces"] { try #require(json.removeValue(forKey: key) != nil) }
        json["schemaVersion"] = 1
        try JSONSerialization.data(withJSONObject: json).write(to: dir.file)

        let fresh = LayoutStore(directory: dir.url)
        fresh.load()
        #expect(fresh.loadError == nil)
        let contents = try #require(fresh.contents)
        #expect(contents.wantedFrames.isEmpty)
        #expect(contents.world == (try Self.withHomeFrameFloating(sample.world)))
        #expect(contents.homeFrames == sample.homeFrames)
    }

    @Test func wantedFramesRoundTripSortedThroughTheStore() throws {
        let dir = Directory()
        let sample = try sampleFile()
        let file = LayoutFile(
            world: sample.world, homeFrames: sample.homeFrameMap,
            wantedFrames: [ref(2).identity: Rect(x: 700, y: 300, width: 400, height: 300), ref(1).identity: Rect(x: 40, y: 80, width: 320, height: 232)],
            session: sample.session)
        try LayoutStore(directory: dir.url).save(file)

        let fresh = LayoutStore(directory: dir.url)
        fresh.load()
        #expect(fresh.loadError == nil)
        #expect(fresh.contents == file)
        #expect(fresh.contents?.wantedFrames.map(\.window) == [ref(1).identity, ref(2).identity])
    }
}

/// D-13: docked and floating tab groups, and their selected tabs, round-trip through layout.json unchanged.
extension LayoutStoreTests {
    @Test func dockedAndFloatingTabGroupsRoundTripWithTheirSelections() throws {
        var world = World()
        try world.addDesk(key)
        var history = UndoHistory()
        try world.edit(key, history: &history) { desk, ids throws(LayoutError) in
            try desk.tree.applyDrop(.layoutEdge(.right), window: ref(1), ids: &ids)
            guard let leaf = desk.tree.leaf(containing: ref(1)) else { throw .windowNotFound(ref(1)) }
            try desk.tree.group(ref(2), into: leaf)
            try desk.tree.group(ref(3), into: leaf)
            try desk.tree.selectTab(ref(2))
            try desk.desktop.add(ref(4), frame: Rect(x: 900, y: 300, width: 400, height: 300))
            try desk.desktop.add(ref(5), frame: Rect(x: 950, y: 350, width: 300, height: 200))
            try desk.desktop.group(id: try ids.make(), target: ref(4), adding: ref(5))
            try desk.desktop.selectTab(ref(4))
        }
        let file = LayoutFile(world: world, homeFrames: [:], session: SessionRecord(cleanExit: true, launchedAt: Date(timeIntervalSinceReferenceDate: 800_000_000)))
        let dir = Directory()
        try LayoutStore(directory: dir.url).save(file)

        let fresh = LayoutStore(directory: dir.url)
        fresh.load()
        #expect(fresh.loadError == nil)
        #expect(fresh.contents == file)
        let desk = try #require(fresh.contents?.world[key])
        let leaf = try #require(desk.tree.leaf(containing: ref(1)))
        #expect(desk.tree.node(leaf) == .tabs(windows: [ref(1), ref(2), ref(3)], selected: 1))
        #expect(desk.desktop.groups.first.map { ($0.members, $0.selected) } ?? ([], -1) == ([ref(4), ref(5)], 0))
    }
}

/// RESEARCH Pitfall 1, T-06-08: a schema-1 layout.json (every user's file at upgrade) loads and migrates, never set aside.
extension LayoutStoreTests {
    @Test func aSchema1FileLoadsMigratedAndIsNotSetAside() throws {
        let dir = Directory()
        try dir.write(LayoutFileV1Fixture.json)
        let store = LayoutStore(directory: dir.url)
        store.load()
        #expect(store.loadError == nil)
        #expect(!store.savingDisabled)
        #expect(dir.corrupted.isEmpty)
        let contents = try #require(store.contents)
        #expect(contents.schemaVersion == LayoutFile.schemaVersion)
        #expect(contents.arrangement.isUnknown)
        #expect(contents.layoutSets.isEmpty)
        #expect(contents.spaces.isEmpty)
        let display = LayoutFileV1Fixture.display
        #expect(contents.world.desks.keys.sorted() == [DeskKey(displayUUID: display, spaceID: 3), DeskKey(displayUUID: display, spaceID: 4)])
        #expect(contents.homeFrames.map(\.window.windowID) == [2])
        #expect(contents.wantedFrames.map(\.window.windowID) == [1])
    }

    @Test func aMigratedFileSavesAsSchema4WithItsSpaceTableAndRoundTrips() throws {
        let dir = Directory()
        try dir.write(LayoutFileV1Fixture.json)
        let store = LayoutStore(directory: dir.url)
        store.load()
        var contents = try #require(store.contents)
        contents.spaces = [SavedSpace(id: 3, uuid: "U3"), SavedSpace(id: 4, uuid: "U4")]
        #expect(try store.save(contents))
        let text = try dir.text()
        #expect(text.contains("\"schemaVersion\" : \(LayoutFile.schemaVersion)"))
        #expect(text.contains("\"spaces\" : ["))

        let fresh = LayoutStore(directory: dir.url)
        fresh.load()
        #expect(fresh.loadError == nil)
        #expect(fresh.contents == contents)
        #expect(fresh.contents?.spaceMap == [3: "U3", 4: "U4"])
    }
}

/// T-06-07: schema 2's caps. 16 layout sets is the limit, not over it.
extension LayoutStoreTests {
    @Test func sixteenLayoutSetsLoadAndSeventeenAreAnInvalidEntry() throws {
        let dir = Directory()
        try dir.write(try Self.setting("layoutSets") { json in (0..<16).map { Self.layoutSet([String(format: "D%02d", $0)], json) } }())
        let store = LayoutStore(directory: dir.url)
        store.load()
        #expect(store.loadError == nil)
        #expect(store.contents?.layoutSets.count == 16)

        try dir.write(try Self.badFiles.first { $0.0 == "17 layout sets" }!.1())
        store.load()
        guard case .invalidEntry? = store.loadError else {
            Issue.record("17 layout sets gave \(String(describing: store.loadError))")
            return
        }
    }
}

/// D-10, D-14, RESEARCH Pitfall 5: schema 3 keeps titles and the boot session; schema 2 loads and saves as schema 4.
extension LayoutStoreTests {
    @Test func aSchema3FileRoundTripsItsTitlesAndBootSession() throws {
        let dir = Directory()
        var file = try sampleFile()
        file.session.bootSession = "BOOT-A"
        try LayoutStore(directory: dir.url).save(file)

        let fresh = LayoutStore(directory: dir.url)
        fresh.load()
        #expect(fresh.loadError == nil)
        #expect(fresh.contents == file)
        #expect(fresh.contents?.session.bootSession == "BOOT-A")
        let desk = try #require(fresh.contents?.world[key])
        #expect(desk.tree.windows.map(\.titleHint) == ["Secret plan.txt"])
        #expect(desk.desktop.windows.map(\.window.titleHint) == ["Bank statement"])
    }

    /// D-14: views come back sorted by slot, as written.
    @Test func savedViewsRoundTripSortedBySlot() throws {
        let dir = Directory()
        var file = try sampleFile()
        file = LayoutFile(
            world: file.world, homeFrames: file.homeFrameMap, session: file.session,
            views: [
                SavedView(slot: ViewSlot(5)!, desk: key, home: true, windows: []),
                SavedView(slot: ViewSlot(3)!, desk: key, home: false, windows: [ref(2).identity, ref(1).identity]),
            ])
        try LayoutStore(directory: dir.url).save(file)

        let fresh = LayoutStore(directory: dir.url)
        fresh.load()
        #expect(fresh.loadError == nil)
        #expect(fresh.contents == file)
        #expect(fresh.contents?.views.map(\.slot.number) == [3, 5])
        #expect(fresh.contents?.views.first?.windows == [ref(1).identity, ref(2).identity])
    }

    @Test func aSchema2FileLoadsWithEmptyTitlesAndSavesAsSchema4() throws {
        let dir = Directory()
        // Schema 2 as its Transom wrote it: titles redacted (T-03-17) and no boot session.
        let schema2 = try Self.mutated { json in
            var json = json
            json["schemaVersion"] = 2
            var session = json["session"] as? [String: Any] ?? [:]
            session["bootSession"] = nil
            json["session"] = session
            json["views"] = nil
            return json
        }
        .replacingOccurrences(of: "Secret plan.txt", with: "").replacingOccurrences(of: "Bank statement", with: "")
        try #require(!schema2.contains("bootSession") && schema2.contains(#""schemaVersion":2"#))
        try dir.write(schema2)

        let store = LayoutStore(directory: dir.url)
        store.load()
        #expect(store.loadError == nil)
        #expect(!store.savingDisabled)
        let contents = try #require(store.contents)
        #expect(contents.session.bootSession == nil)
        #expect(contents.views.isEmpty, "a schema-2 file has no saved views")
        #expect(contents.world == (try Self.withHomeFrameFloating(sampleFile().world)))
        #expect(contents.world.desks.values.allSatisfy { desk in
            (desk.tree.windows + desk.desktop.windows.map(\.window)).allSatisfy { $0.titleHint.isEmpty }
        })
        #expect(try store.save(contents))
        #expect(try dir.text().contains("\"schemaVersion\" : \(LayoutFile.schemaVersion)"))
    }
}

/// RESEARCH Pitfall 5: only a known boot session that differs from the current one counts as a reboot.
@Suite struct BootSessionTests {
    @Test(arguments: [("A", "B", true), ("A", "A", false), (nil, "A", false), ("A", nil, false), (nil, nil, false)] as [(String?, String?, Bool)])
    func changedOnlyWhenBothAreKnownAndDiffer(saved: String?, current: String?, changed: Bool) {
        #expect(BootSession.changed(saved: saved, current: current) == changed)
    }

    @Test func theCurrentBootSessionIsReadable() {
        #expect(BootSession.current()?.isEmpty == false)
    }
}

/// 8.1.1 D-02, RESEARCH Pitfall 1: a schema-3 file (every 08.1 user's) loads without its Desktop tiles, never set aside;
/// its docked windows share the whole visible frame, floaters keep their frames, and it saves as schema 4 / World 2.
extension LayoutStoreTests {
    @Test func aSchema3FileWithADesktopTileLoadsWithoutItAndSavesAsSchema4() throws {
        let dir = Directory()
        try dir.write(LayoutFileV3Fixture.json)
        let store = LayoutStore(directory: dir.url)
        store.load()
        #expect(store.loadError == nil)
        #expect(!store.savingDisabled)
        #expect(dir.corrupted.isEmpty)
        // The one-way migration keeps the pre-upgrade file for a downgrade (WR-04).
        let backups = try FileManager.default.contentsOfDirectory(atPath: dir.url.path).filter { $0.hasPrefix(LayoutStore.fileName + ".schema-3-") }
        #expect(backups.count == 1)
        #expect(try backups.first.map { try String(contentsOf: dir.url.appending(path: $0), encoding: .utf8) } == LayoutFileV3Fixture.json)
        let contents = try #require(store.contents)
        #expect(contents.schemaVersion == LayoutFile.schemaVersion)

        func window(_ id: UInt32, _ title: String) -> WindowRef {
            WindowRef(identity: WindowIdentity(windowID: id, pid: 300, bundleID: "com.example.editor"), titleHint: title)
        }
        let a = window(1, "Notes"), b = window(2, "Terminal")
        let desk = try #require(contents.world[DeskKey(displayUUID: LayoutFileV3Fixture.display, spaceID: 3)])
        let root = try #require(desk.tree.root)
        #expect(desk.tree.node(root) == .split(axis: .horizontal, children: [NodeID(raw: 1), NodeID(raw: 2)], weights: [0.5, 0.5]))
        #expect(desk.tree.nodes[NodeID(raw: 0)] == nil)
        #expect(desk.tree.windows == [a, b])
        #expect(desk.desktop.frame(of: window(3, "Calendar")) == Rect(x: 900, y: 300, width: 400, height: 300))
        // Parked by the hidden Desktop: its stored frame is its home frame, so it comes back even if it shows up after launch (WR-01).
        #expect(desk.desktop.frame(of: window(4, "FileZilla")) == Rect(x: 200, y: 150, width: 600, height: 400))

        let set = try #require(contents.layoutSets.first?.world.desks.values.first)
        #expect(set.tree.root == nil)
        #expect(set.tree.nodes.isEmpty)
        #expect(set.desktop.windows.map(\.window.windowID) == [5])
        #expect(contents.views.first?.windows.map(\.windowID) == [1, 2])

        // No Desktop share: the two docked windows span the visible frame's width less the gaps.
        let visible = Rect(x: 0, y: 25, width: 1440, height: 875)
        let frames = try Planner.plan(desk: desk, area: visible, gap: 8, mins: [:]).frames
        let left = try #require(frames[a]), right = try #require(frames[b])
        #expect(left.minX - visible.minX <= 8 && visible.maxX - right.maxX <= 8)
        #expect(abs(left.width - right.width) < 1)

        #expect(try store.save(contents))
        let text = try dir.text()
        #expect(text.contains("\"schemaVersion\" : \(LayoutFile.schemaVersion)"))
        #expect(text.contains("\"schemaVersion\" : 2"))
        #expect(!text.contains("\"hidden\""), "a Desktop node was written back")
        let fresh = LayoutStore(directory: dir.url)
        fresh.load()
        #expect(fresh.loadError == nil)
        #expect(fresh.contents == contents)
    }
}

/// 8.1.1 WR-01 (iteration 2): a home frame belongs to the World that parked the window, so a layout set where the same
/// window floats elsewhere keeps its own frame there.
extension LayoutStoreTests {
    @Test func aHomeFrameFromTheCurrentWorldLeavesAStoredLayoutSetsFrameAlone() throws {
        let dir = Directory()
        // FileZilla (window 4) also floats in the stored layout set, at 100,100 500×400.
        try dir.write(LayoutFileV3Fixture.json.replacingOccurrences(of: #""windowID" : 5"#, with: #""windowID" : 4"#))
        let store = LayoutStore(directory: dir.url)
        store.load()
        #expect(store.loadError == nil)
        let contents = try #require(store.contents)
        let fileZilla = WindowRef(identity: WindowIdentity(windowID: 4, pid: 300, bundleID: "com.example.editor"))
        let desk = try #require(contents.world[DeskKey(displayUUID: LayoutFileV3Fixture.display, spaceID: 3)])
        #expect(desk.desktop.frame(of: fileZilla) == Rect(x: 200, y: 150, width: 600, height: 400))
        let set = try #require(contents.layoutSets.first?.world.desks.values.first)
        #expect(set.desktop.frame(of: fileZilla) == Rect(x: 100, y: 100, width: 500, height: 400))
    }
}

/// 8.1.1 D-15: the migration's one log line holds counts only, and none for a current file.
extension LayoutStoreTests {
    @Test func theMigrationLineCountsDesktopTilesAndParkedWindows() throws {
        let dir = Directory()
        try dir.write(LayoutFileV3Fixture.json)
        let store = LayoutStore(directory: dir.url)
        store.load()
        let contents = try #require(store.contents)
        #expect(
            LayoutStore.migrationLine(fromSchema: 3, contents: contents)
                == "migrated layout.json schema 3 to 5: dropped 2 Desktop tiles, brought back 1 parked windows")
        // Schema 4 had no Desktop tiles to count (8.1.1 D-20), and a current file needs no line.
        #expect(LayoutStore.migrationLine(fromSchema: 4, contents: contents) == nil)
        #expect(LayoutStore.migrationLine(fromSchema: LayoutFile.schemaVersion, contents: contents) == nil)

        try dir.write(LayoutFileV1Fixture.json)
        store.load()
        let v1 = try #require(store.contents)
        #expect(LayoutStore.migrationLine(fromSchema: 1, contents: v1)?.hasPrefix("migrated layout.json schema 1 to 5: ") == true)
    }
}

/// 8.1.1 D-02, T-08.1.1-14: the schema-3 fixture relabelled schema 4 (World schema 2) still names its Desktop tiles. No
/// current Transom writes that, so the file is forged or broken: it is set aside whole, never migrated.
extension LayoutStoreTests {
    @Test func aSchema4FileWithADesktopNodeIsSetAside() throws {
        let forged = LayoutFileV3Fixture.json
            .replacingOccurrences(of: "\"schemaVersion\" : 3", with: "\"schemaVersion\" : 4")
            .replacingOccurrences(of: "\"schemaVersion\" : 1", with: "\"schemaVersion\" : 2")
        try #require(forged.contains("\"hidden\" : false") && !forged.contains("\"schemaVersion\" : 1"))
        let dir = Directory()
        try dir.write(forged)
        let store = LayoutStore(directory: dir.url)
        store.load()
        #expect(store.contents == nil)
        #expect(store.loadError != nil)
        #expect(!store.savingDisabled)
        #expect(!FileManager.default.fileExists(atPath: dir.file.path))
        let moved = try #require(dir.corrupted.first)
        #expect(try String(contentsOf: moved, encoding: .utf8) == forged)
    }
}

/// 8.1.1 D-16, D-20: schema 5 stores empty areas; a schema-4 file has the same shape without them and saves as schema 5,
/// with a backup of the schema-4 file first.
extension LayoutStoreTests {
    @Test func aSchema5FileWithAnEmptyAreaRoundTrips() throws {
        let dir = Directory()
        let file = try emptyAreaFile()
        try LayoutStore(directory: dir.url).save(file)
        let saved = try Data(contentsOf: dir.file)
        #expect(String(decoding: saved, as: UTF8.self).contains("\"spacer\""))

        let fresh = LayoutStore(directory: dir.url)
        fresh.load()
        #expect(fresh.loadError == nil)
        #expect(fresh.contents == file)
        #expect(try fresh.save(try #require(fresh.contents)))
        #expect(try Data(contentsOf: dir.file) == saved)
    }

    @Test func aSchema4FileLoadsUnchangedAndSavesAsSchema5() throws {
        let schema4 = try Self.edited("\"schemaVersion\" : 5", "\"schemaVersion\" : 4")
        let dir = Directory()
        try dir.write(schema4)
        let store = LayoutStore(directory: dir.url)
        store.load()
        #expect(store.loadError == nil)
        #expect(!store.savingDisabled)
        let contents = try #require(store.contents)
        // No Desktop in schema 4, so the floater keeps its stored frame rather than its home frame.
        #expect(contents.world == (try sampleFile().world))
        #expect(LayoutStore.migrationLine(fromSchema: 4, contents: contents) == nil)
        let backups = try FileManager.default.contentsOfDirectory(atPath: dir.url.path).filter { $0.hasPrefix(LayoutStore.fileName + ".schema-4-") }
        #expect(backups.count == 1)
        #expect(try backups.first.map { try String(contentsOf: dir.url.appending(path: $0), encoding: .utf8) } == schema4)

        #expect(try store.save(contents))
        #expect(try dir.text().contains("\"schemaVersion\" : 5"))
    }
}

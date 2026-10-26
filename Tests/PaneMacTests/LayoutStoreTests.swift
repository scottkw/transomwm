import Foundation
import PaneEngine
import PaneMac
import PaneModel
import Testing

private let key = DeskKey(displayUUID: "main", spaceID: nil)

private func ref(_ id: UInt32, title: String = "") -> WindowRef {
    WindowRef(identity: WindowIdentity(windowID: id, pid: 300, bundleID: "com.example.editor"), titleHint: title)
}

/// [1 | Desktop] with 2 floating; both windows carry a title.
private func sampleFile() throws -> LayoutFile {
    var world = World()
    try world.addDesk(key)
    var history = UndoHistory()
    try world.edit(key, history: &history) { desk, ids throws(LayoutError) in
        try desk.tree.insert(ref(1, title: "Secret plan.txt"), at: .left, of: .desktop, ids: &ids)
        try desk.desktop.add(ref(2, title: "Bank statement"), frame: Rect(x: 900, y: 300, width: 400, height: 300))
    }
    return LayoutFile(
        world: world, homeFrames: [ref(2).identity: Rect(x: 50, y: 60, width: 400, height: 300)],
        session: SessionRecord(cleanExit: false, launchedAt: Date(timeIntervalSinceReferenceDate: 800_000_000.25)))
}

/// D-16, T-03-15..18: layout.json is validated whole on load, written atomically and owner-only, never holds titles,
/// and a newer Pane's file is never overwritten.
@MainActor @Suite struct LayoutStoreTests {
    /// A fresh temporary directory per test, removed afterwards. Never the user's real Application Support.
    final class Directory {
        let url = FileManager.default.temporaryDirectory.appending(path: "pane-layout-\(UUID().uuidString)", directoryHint: .isDirectory)
        var file: URL { url.appending(path: LayoutStore.fileName) }
        var corrupt: URL { url.appending(path: LayoutStore.fileName + ".corrupt") }
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
        #expect(text.contains("\"schemaVersion\" : 1"))
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

    @Test func titlesAreNeverWritten() throws {
        let dir = Directory()
        try LayoutStore(directory: dir.url).save(try sampleFile())
        let text = try dir.text()
        #expect(!text.contains("Secret plan") && !text.contains("Bank statement"))
    }

    @Test func noFileStartsEmptyWithoutAnError() {
        let dir = Directory()
        let store = LayoutStore(directory: dir.url)
        store.load()
        #expect(store.contents == nil)
        #expect(store.loadError == nil)
        #expect(!store.savingDisabled)
        #expect(!FileManager.default.fileExists(atPath: dir.corrupt.path))
    }

    nonisolated static let badFiles: [(String, @MainActor @Sendable () throws -> String)] = [
        ("too large", { try edited("\"schemaVersion\" : 1", "\"schemaVersion\" : 1" + String(repeating: " ", count: World.maxEncodedBytes)) }),
        ("malformed", { #"{"schemaVersion":1,"world":"# }),
        ("duplicate window", { try edited("\"windowID\" : 2", "\"windowID\" : 1") }),
        // JSON has no NaN; an overflowing literal is the nearest a file gets to a non-finite frame.
        ("non-finite home frame", { try edited("\"x\" : 50", "\"x\" : 1e400") }),
        ("huge home frame", { try edited("\"width\" : 400,\n        \"x\" : 50", "\"width\" : 2e6,\n        \"x\" : 50") }),
        ("duplicate home frame", { try edited("\"homeFrames\" : [", "\"homeFrames\" : [{\"frame\":{\"x\":1,\"y\":1,\"width\":10,\"height\":10},\"window\":{\"bundleID\":\"com.example.editor\",\"pid\":300,\"windowID\":2}},") }),
        ("session missing a field", { try edited("\"cleanExit\" : false,", "") }),
    ]

    @Test(arguments: badFiles)
    func aBadFileIsRejectedWholeAndMovedAside(name: String, text: @MainActor @Sendable () throws -> String) throws {
        let text = try text()
        let dir = Directory()
        try dir.write("older")
        try FileManager.default.moveItem(at: dir.file, to: dir.corrupt)  // an older .corrupt is replaced
        try dir.write(text)
        let store = LayoutStore(directory: dir.url)
        store.load()
        #expect(store.contents == nil, "\(name) was loaded")
        #expect(store.loadError != nil, "\(name) was accepted")
        #expect(!store.savingDisabled, "\(name) disabled saving")
        #expect(!FileManager.default.fileExists(atPath: dir.file.path), "\(name) left in place")
        #expect(try String(contentsOf: dir.corrupt, encoding: .utf8) == text, "\(name) not moved aside")
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
        let newer = try Self.edited("\"schemaVersion\" : 1", "\"schemaVersion\" : 2")
        try dir.write(newer)
        let store = LayoutStore(directory: dir.url)
        store.load()
        #expect(store.contents == nil)
        #expect(store.loadError == .newerVersion(2))
        #expect(store.savingDisabled)
        #expect(try dir.text() == newer)
        #expect(!FileManager.default.fileExists(atPath: dir.corrupt.path))
        #expect(try store.save(try sampleFile()) == false)
        #expect(try dir.text() == newer, "a save overwrote a newer Pane's layout")
    }
}

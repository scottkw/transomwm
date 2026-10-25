import Foundation
import PaneEngine
import PaneMac
import PaneModel
import Testing

/// D-13: learned minimums persist per bundle as validated, atomic JSON; a bad file is rejected whole and set aside.
@MainActor @Suite struct MinimumHintsStoreTests {
    /// A fresh temporary directory per test, removed afterwards.
    final class Directory {
        let url = FileManager.default.temporaryDirectory.appending(path: "pane-hints-\(UUID().uuidString)", directoryHint: .isDirectory)
        var file: URL { url.appending(path: MinimumHintsStore.fileName) }
        var corrupt: URL { url.appending(path: MinimumHintsStore.fileName + ".corrupt") }
        init() { try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true) }
        deinit { try? FileManager.default.removeItem(at: url) }
        func write(_ text: String) throws { try Data(text.utf8).write(to: file) }
    }

    @Test func recordingKeepsThePerAxisMaximum() {
        let dir = Directory()
        let store = MinimumHintsStore(directory: dir.url)
        #expect(store.record(bundleID: "com.apple.Safari", minimum: Size(width: 250, height: 150)))
        #expect(store.record(bundleID: "com.apple.Safari", minimum: Size(width: 200, height: 300)))
        #expect(store.hints["com.apple.Safari"] == Size(width: 250, height: 300))
        #expect(!store.record(bundleID: "com.apple.Safari", minimum: Size(width: 100, height: 100)))
        #expect(store.hints["com.apple.Safari"] == Size(width: 250, height: 300))
    }

    @Test func savedHintsLoadInAFreshStoreAndTheFileIsSorted() throws {
        let dir = Directory()
        let store = MinimumHintsStore(directory: dir.url)
        _ = store.record(bundleID: "com.zeta.app", minimum: Size(width: 400, height: 300))
        _ = store.record(bundleID: "com.alpha.app", minimum: Size(width: 250, height: 150))
        try store.save()
        let text = try String(contentsOf: dir.file, encoding: .utf8)
        #expect(text.contains("\"schemaVersion\" : 1"))
        let alpha = try #require(text.range(of: "com.alpha.app"))
        let zeta = try #require(text.range(of: "com.zeta.app"))
        #expect(alpha.lowerBound < zeta.lowerBound)

        let fresh = MinimumHintsStore(directory: dir.url)
        fresh.load()
        #expect(fresh.loadError == nil)
        #expect(fresh.hints == store.hints)
    }

    @Test func saveCreatesTheDirectory() throws {
        let dir = Directory()
        let nested = dir.url.appending(path: "Pane", directoryHint: .isDirectory)
        let store = MinimumHintsStore(directory: nested)
        _ = store.record(bundleID: "com.example.app", minimum: Size(width: 300, height: 200))
        try store.save()
        #expect(FileManager.default.fileExists(atPath: nested.appending(path: MinimumHintsStore.fileName).path))
    }

    @Test func noFileStartsEmptyWithoutAnError() {
        let dir = Directory()
        let store = MinimumHintsStore(directory: dir.url)
        store.load()
        #expect(store.hints.isEmpty)
        #expect(store.loadError == nil)
        #expect(!FileManager.default.fileExists(atPath: dir.corrupt.path))
    }

    nonisolated static let entry = #"{"bundleID":"com.example.app","width":300,"height":200}"#
    nonisolated static let badFiles: [(String, String)] = [
        ("too large", #"{"schemaVersion":1,"hints":[]}"# + String(repeating: " ", count: 70 * 1024)),
        ("newer schema", #"{"schemaVersion":2,"hints":[]}"#),
        ("malformed", #"{"schemaVersion":1,"hints":["#),
        ("duplicate", #"{"schemaVersion":1,"hints":[\#(entry),\#(entry)]}"#),
        ("negative width", #"{"schemaVersion":1,"hints":[{"bundleID":"com.example.app","width":-1,"height":200}]}"#),
        ("huge height", #"{"schemaVersion":1,"hints":[{"bundleID":"com.example.app","width":300,"height":2e6}]}"#),
        ("bundle ID with a space", #"{"schemaVersion":1,"hints":[{"bundleID":"com.example app","width":300,"height":200}]}"#),
    ]

    @Test(arguments: badFiles)
    func aBadFileIsRejectedWholeAndMovedAside(name: String, text: String) throws {
        let dir = Directory()
        try dir.write(#"{"schemaVersion":1,"hints":[]}"#)
        try FileManager.default.moveItem(at: dir.file, to: dir.corrupt)  // an older .corrupt is replaced
        try dir.write(text)
        let store = MinimumHintsStore(directory: dir.url)
        store.load()
        #expect(store.hints.isEmpty, "\(name)")
        #expect(store.loadError != nil, "\(name) was accepted")
        #expect(!FileManager.default.fileExists(atPath: dir.file.path), "\(name) left in place")
        #expect(try String(contentsOf: dir.corrupt, encoding: .utf8) == text, "\(name) not moved aside")
    }

    @Test func rejectionsNameTheirReason() throws {
        let dir = Directory()
        let store = MinimumHintsStore(directory: dir.url)
        try dir.write(#"{"schemaVersion":2,"hints":[]}"#)
        store.load()
        #expect(store.loadError == .newerVersion(2))
        try dir.write(Self.badFiles[0].1)
        store.load()
        #expect(store.loadError == .tooLarge(Self.badFiles[0].1.utf8.count))
    }

    @Test func aRejectedFileReplacesLoadedHints() throws {
        let dir = Directory()
        try dir.write(#"{"schemaVersion":1,"hints":[\#(Self.entry)]}"#)
        let store = MinimumHintsStore(directory: dir.url)
        store.load()
        #expect(store.hints == ["com.example.app": Size(width: 300, height: 200)])
        try dir.write(#"{"schemaVersion":1,"hints":["#)
        store.load()
        #expect(store.hints.isEmpty)
    }

    @Test func unbundledAndInvalidKeysAreNeverStored() {
        let dir = Directory()
        let store = MinimumHintsStore(directory: dir.url)
        #expect(!store.record(bundleID: "unbundled:PaneFixtureApp", minimum: Size(width: 300, height: 200)))
        #expect(!store.record(bundleID: "", minimum: Size(width: 300, height: 200)))
        #expect(!store.record(bundleID: "com.example.app", minimum: Size(width: .infinity, height: 200)))
        #expect(!store.record(bundleID: "com.example.app", minimum: Size(width: 300, height: 2e6)))
        #expect(store.hints.isEmpty)
    }
}

/// D-13 in the tracker: a stored hint is a new window's starting minimum, and learning only raises it.
@Suite struct BundleHintTrackerTests {
    static let ref = WindowRef(identity: WindowIdentity(windowID: 7, pid: 700, bundleID: "com.example.app"))

    static func observe(_ tracker: inout WindowTracker) {
        let snapshot = WindowSnapshot(
            role: "AXWindow", subrole: "AXStandardWindow", minimized: false, fullScreen: false,
            close: .enabled, minimize: .enabled, zoom: .enabled, fullScreenButton: .enabled, frame: Rect(x: 40, y: 80, width: 400, height: 300)
        )
        let app = AppObservation(pid: 700, bundleID: "com.example.app", windows: [WindowObservation(windowID: 7, idSource: .axPrivate, read: .success(snapshot), title: "")])
        _ = tracker.ingest(app, context: ObservationContext(initialSweep: true, now: .now))
    }

    @Test func aNewWindowStartsFromItsBundlesHintAndLearningOnlyRaisesIt() throws {
        var tracker = WindowTracker()
        tracker.setBundleHints(["com.example.app": Size(width: 300, height: 200)])
        Self.observe(&tracker)
        #expect(tracker.info(for: Self.ref.identity)?.learnedMinimum == Size(width: 300, height: 200))
        let requested = Rect(x: 40, y: 80, width: 100, height: 100)
        let actual = Rect(x: 40, y: 80, width: 350, height: 180)
        _ = tracker.applyFrameResult(FrameWriteResult(window: Self.ref, requested: requested, actual: actual, failure: nil))
        #expect(tracker.info(for: Self.ref.identity)?.learnedMinimum == Size(width: 350, height: 200))
    }

    @Test func anotherBundleGetsNoHint() {
        var tracker = WindowTracker()
        tracker.setBundleHints(["com.other.app": Size(width: 300, height: 200)])
        Self.observe(&tracker)
        #expect(tracker.info(for: Self.ref.identity)?.learnedMinimum == nil)
    }
}

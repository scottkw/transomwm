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

/// D-13 in the tracker: a stored hint, or a minimum learned this session, is a new window's starting minimum, and
/// learning only raises it.
@Suite struct BundleHintTrackerTests {
    static let ref = WindowRef(identity: WindowIdentity(windowID: 7, pid: 700, bundleID: "com.example.app"))

    static let t0 = ContinuousClock.now
    static let start = Rect(x: 40, y: 80, width: 400, height: 300)

    static func observe(_ tracker: inout WindowTracker, frame: Rect = start, at time: ContinuousClock.Instant = t0) {
        observe(&tracker, [7: frame], at: time)
    }

    /// One refresh of the app listing `frames` (window ID to frame); first reports are seeded at once (initial sweep).
    static func observe(
        _ tracker: inout WindowTracker, _ frames: [UInt32: Rect], pid: Int32 = 700, bundleID: String = "com.example.app",
        at time: ContinuousClock.Instant = t0
    ) {
        let windows = frames.sorted { $0.key < $1.key }.map { id, frame in
            let snapshot = WindowSnapshot(
                role: "AXWindow", subrole: "AXStandardWindow", minimized: false, fullScreen: false,
                close: .enabled, minimize: .enabled, zoom: .enabled, fullScreenButton: .enabled, frame: frame
            )
            return WindowObservation(windowID: id, idSource: .axPrivate, read: .success(snapshot), title: "")
        }
        _ = tracker.ingest(AppObservation(pid: pid, bundleID: bundleID, windows: windows), context: ObservationContext(initialSweep: true, now: time))
    }

    static func minimum(_ tracker: WindowTracker, _ id: UInt32, pid: Int32 = 700, bundleID: String = "com.example.app") -> Size? {
        tracker.info(for: WindowIdentity(windowID: id, pid: pid, bundleID: bundleID))?.learnedMinimum
    }

    /// Window 7 refuses `requested` with `actual` at t0, and a refresh a second later (listing `others` too) confirms it.
    static func refuse(_ tracker: inout WindowTracker, _ requested: Rect, readsBack actual: Rect, others: [UInt32: Rect] = [:]) {
        _ = tracker.applyFrameResult(FrameWriteResult(window: ref, requested: requested, actual: actual, failure: nil), at: t0)
        observe(&tracker, others.merging([7: actual]) { $1 }, at: t0 + MinimumSizeLearner.confirmDelay)
    }

    @Test func aNewWindowStartsFromItsBundlesHintAndLearningOnlyRaisesIt() throws {
        var tracker = WindowTracker()
        tracker.setBundleHints(["com.example.app": Size(width: 300, height: 200)])
        Self.observe(&tracker)
        #expect(tracker.info(for: Self.ref.identity)?.learnedMinimum == Size(width: 300, height: 200))
        let requested = Rect(x: 40, y: 80, width: 100, height: 100)
        let actual = Rect(x: 40, y: 80, width: 350, height: 180)
        _ = tracker.applyFrameResult(FrameWriteResult(window: Self.ref, requested: requested, actual: actual, failure: nil), at: Self.t0)
        #expect(tracker.info(for: Self.ref.identity)?.learnedMinimum == Size(width: 300, height: 200), "nothing is learned at write time")
        // One refused write, confirmed by a refresh a second later that still sees the window there.
        Self.observe(&tracker, frame: actual, at: Self.t0 + MinimumSizeLearner.confirmDelay)
        #expect(tracker.info(for: Self.ref.identity)?.learnedMinimum == Size(width: 350, height: 200))
    }

    /// REVIEW IN-04: what one window of an app teaches helps the next window of that app in the same session.
    @Test func aMinimumLearnedThisSessionSeedsTheNextWindowOfThatBundle() {
        var tracker = WindowTracker()
        Self.observe(&tracker)
        Self.refuse(&tracker, Rect(x: 40, y: 80, width: 100, height: 300), readsBack: Rect(x: 40, y: 80, width: 350, height: 300))
        #expect(Self.minimum(tracker, 7) == Size(width: 350, height: 0))
        Self.observe(&tracker, [7: Rect(x: 40, y: 80, width: 350, height: 300), 8: Self.start], at: Self.t0 + .seconds(2))
        #expect(Self.minimum(tracker, 8) == Size(width: 350, height: 0))
    }

    /// CR-02 (Reminders' fixed-size Welcome window, G-03-6): a minimum learned from unmoved refusals holds for that
    /// window, but is neither shared with the next window of the bundle nor reported for saving.
    @Test func aMinimumLearnedFromUnmovedRefusalsStaysWithItsWindow() throws {
        var tracker = WindowTracker()
        let fixed = Rect(x: 40, y: 80, width: 768, height: 300)
        Self.observe(&tracker, frame: fixed)
        let requested = Rect(x: 40, y: 80, width: 500, height: 300)
        for k in 0..<2 {
            let at = Self.t0 + MinimumSizeLearner.confirmDelay * k
            _ = tracker.applyFrameResult(FrameWriteResult(window: Self.ref, requested: requested, actual: fixed, failure: nil), at: at)
        }
        Self.observe(&tracker, frame: fixed, at: Self.t0 + MinimumSizeLearner.confirmDelay * 2)
        let info = try #require(tracker.info(for: Self.ref.identity))
        #expect(info.learnedMinimum == Size(width: 768, height: 0))
        #expect(info.persistableMinimum == nil)
        Self.observe(&tracker, [7: fixed, 8: Self.start], at: Self.t0 + .seconds(3))
        #expect(Self.minimum(tracker, 8) == nil)
    }

    @Test func aLearnedMinimumRaisesAStoredHintPerAxisAndOnlyForItsBundle() {
        var tracker = WindowTracker()
        tracker.setBundleHints(["com.example.app": Size(width: 300, height: 200)])
        Self.observe(&tracker)
        Self.refuse(&tracker, Rect(x: 40, y: 80, width: 100, height: 100), readsBack: Rect(x: 40, y: 80, width: 350, height: 180))
        Self.observe(&tracker, [7: Rect(x: 40, y: 80, width: 350, height: 180), 9: Self.start], at: Self.t0 + .seconds(2))
        #expect(Self.minimum(tracker, 9) == Size(width: 350, height: 200))
        Self.observe(&tracker, [5: Self.start], pid: 701, bundleID: "com.other.app", at: Self.t0 + .seconds(2))
        #expect(Self.minimum(tracker, 5, pid: 701, bundleID: "com.other.app") == nil)
    }

    @Test func aRefusalWithinTheMarginRaisesNoHint() {
        var tracker = WindowTracker()
        Self.observe(&tracker)
        Self.refuse(&tracker, Rect(x: 40, y: 80, width: 300, height: 300), readsBack: Rect(x: 40, y: 80, width: 320, height: 300))
        Self.observe(&tracker, [7: Rect(x: 40, y: 80, width: 320, height: 300), 8: Self.start], at: Self.t0 + .seconds(2))
        #expect(Self.minimum(tracker, 8) == nil)
    }

    @Test func aWindowAlreadyTrackedKeepsItsOwnValue() {
        var tracker = WindowTracker()
        Self.observe(&tracker, [7: Self.start, 8: Self.start])
        Self.refuse(&tracker, Rect(x: 40, y: 80, width: 100, height: 300), readsBack: Rect(x: 40, y: 80, width: 350, height: 300), others: [8: Self.start])
        #expect(Self.minimum(tracker, 7) == Size(width: 350, height: 0))
        #expect(Self.minimum(tracker, 8) == nil, "hints seed only first reports")
    }

    @Test func setBundleHintsReplacesTheSessionsHints() {
        var tracker = WindowTracker()
        Self.observe(&tracker)
        Self.refuse(&tracker, Rect(x: 40, y: 80, width: 100, height: 300), readsBack: Rect(x: 40, y: 80, width: 350, height: 300))
        tracker.setBundleHints([:])
        Self.observe(&tracker, [7: Rect(x: 40, y: 80, width: 350, height: 300), 8: Self.start], at: Self.t0 + .seconds(2))
        #expect(Self.minimum(tracker, 8) == nil)
    }

    @Test func anotherBundleGetsNoHint() {
        var tracker = WindowTracker()
        tracker.setBundleHints(["com.other.app": Size(width: 300, height: 200)])
        Self.observe(&tracker)
        #expect(tracker.info(for: Self.ref.identity)?.learnedMinimum == nil)
    }
}

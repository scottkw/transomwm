import CoreGraphics
import ScreenCaptureKit
import os

/// The only file that touches ScreenCaptureKit or the Screen Recording permission (D-B, TILE-10; NoScreenCaptureTests
/// allows exactly this file). One-shot window captures, no SCStream, so the system sharing indicator never shows.
/// Images stay in memory and go only to the caller: nothing is written to disk and no image or title is logged (T-04-01).
@MainActor public final class SnapshotCapture {
    public static let maxConcurrency = 4
    /// How long a move waits for its captures before it starts (UI-SPEC step 3).
    public static let moveBudget: Duration = .milliseconds(120)
    /// A capture whose completion handler never fires must not hang its caller (RESEARCH Pattern 5, T-04-03).
    static let captureTimeout: Duration = .seconds(1)
    /// Consecutive failures while granted that make the Debug state "capture failing" (UI-SPEC Surface 2).
    public static let failingAfter = 3
    private static let logger = Logger(subsystem: "com.eightabyte.transom", category: "capture")
    private var scWindows: [CGWindowID: SCWindow] = [:]
    /// Windows a re-read still did not list, so asking for them again does not re-read on every move (WR-03).
    private var unlisted: Set<CGWindowID> = []
    /// Every successful capture, late ones included (04-SPIKE verdict condition 2: mandatory, not optional).
    private(set) var cache = SnapshotCache()
    /// Failed captures since the last success.
    public private(set) var consecutiveFailures = 0
    /// Zoom turned off: no ScreenCaptureKit call from here on, even from a refresh or capture already in flight (WR-04, D-D).
    private var closed = false

    /// Every call that reaches ScreenCaptureKit or the Screen Recording permission; it exists for the zoom-off guard test
    /// (ZoomOffTests, success criterion 5), which expects 0.
    public static private(set) var touches = 0

    public init() {}

    public static func isGranted() -> Bool {
        touches += 1
        return CGPreflightScreenCaptureAccess()
    }

    public static func request() -> Bool {
        touches += 1
        return CGRequestScreenCaptureAccess()
    }

    /// Re-reads the shareable windows. Slow: never call it on a move's critical path.
    public func refreshShareable() async throws {
        guard !closed else { return }
        Self.touches += 1
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)
        scWindows = Dictionary(content.windows.map { ($0.windowID, $0) }, uniquingKeysWith: { first, _ in first })
    }

    /// One window at `pixelSize`, or nil when the window is unknown, the capture failed or it took over 1 s.
    public func capture(_ id: CGWindowID, pixelSize: CGSize) async -> CGImage? {
        guard !closed else { return nil }
        Self.touches += 1
        guard let window = scWindows[id] else { return nil }
        let config = SCStreamConfiguration()
        config.width = max(1, Int(pixelSize.width))
        config.height = max(1, Int(pixelSize.height))
        config.scalesToFit = true
        config.ignoreShadowsSingleWindow = true
        config.ignoreGlobalClipSingleWindow = true
        config.showsCursor = false
        let filter = SCContentFilter(desktopIndependentWindow: window)
        // A task group would wait for a hung child at scope exit, so the timeout races through a resume-once continuation.
        let result = await withCheckedContinuation { (continuation: CheckedContinuation<Result<CGImage, CaptureFailure>, Never>) in
            let once = ResumeOnce(continuation)
            SCScreenshotManager.captureImage(contentFilter: filter, configuration: config) { image, error in
                once.resume(image.map { .success($0) } ?? .failure(CaptureFailure(description: error.map { "\($0)" } ?? "no image")))
            }
            Task {
                try? await Task.sleep(for: Self.captureTimeout)
                once.resume(.failure(CaptureFailure(description: "timed out")))
            }
        }
        guard !closed else { return nil }  // closed while it ran: nothing goes back into the cache
        switch result {
        case .success(let image):
            consecutiveFailures = 0
            cache.insert(image, for: id)
            return image
        case .failure(let failure):
            consecutiveFailures += 1
            Self.logger.notice("capture failed window \(id, privacy: .public): \(failure.description, privacy: .public)")
            return nil
        }
    }

    public func cached(_ id: CGWindowID) -> CGImage? { cache.image(for: id) }
    public func remove(_ id: CGWindowID) { cache.remove(id) }
    /// Zoom off: every snapshot goes and nothing is captured again; the owner makes a new one for the next Turn On.
    public func close() {
        closed = true
        cache.purge()
    }

    /// UI-SPEC step 8: after a reveal, re-reads the shareable windows (off the move's critical path) and re-captures the
    /// windows now visible at their new size, into the cache only. Windows that closed leave the cache.
    public func refresh(_ requests: [(CGWindowID, CGSize)]) async {
        do {
            try await refreshShareable()
        } catch {
            Self.logger.notice("shareable content failed: \(String(describing: error), privacy: .public)")
            return
        }
        guard !closed else { return }
        for id in cache.ids where scWindows[id] == nil { cache.remove(id) }
        _ = await captureAll(requests, deadline: .seconds(2))
    }

    /// Captures at most `concurrency` windows at a time and returns those finished by `deadline`. Late results go only to
    /// the cache; captures not yet started by then are not started.
    public func captureAll(
        _ requests: [(CGWindowID, CGSize)], deadline: Duration = moveBudget, concurrency: Int = maxConcurrency
    ) async -> [CGWindowID: CGImage] {
        guard !requests.isEmpty else { return [:] }
        let batch = Batch(requests)
        // A window the list has never had (a fresh controller's first move, a window opened since the last reveal) is
        // re-read first, inside the same deadline, so it gets a snapshot instead of always falling back (WR-03).
        let unknown = requests.contains { scWindows[$0.0] == nil && !unlisted.contains($0.0) }
        return await withCheckedContinuation { continuation in
            batch.done = continuation
            Task {
                if unknown {
                    do { try await refreshShareable() } catch {
                        Self.logger.notice("shareable content failed: \(String(describing: error), privacy: .public)")
                    }
                    unlisted.formUnion(requests.map(\.0).filter { scWindows[$0] == nil })
                }
                for _ in 0..<max(1, concurrency) { startNext(batch) }
            }
            Task {
                try? await Task.sleep(for: deadline)
                batch.finish()
            }
        }
    }

    private func startNext(_ batch: Batch) {
        guard !batch.finished, let (id, size) = batch.pending.popFirst() else { return }
        batch.inFlight += 1
        Task {
            let image = await capture(id, pixelSize: size)
            guard !batch.finished else { return }
            batch.inFlight -= 1
            if let image { batch.results[id] = image }
            if batch.pending.isEmpty && batch.inFlight == 0 { batch.finish() } else { startNext(batch) }
        }
    }

    private final class Batch {
        var pending: ArraySlice<(CGWindowID, CGSize)>
        var inFlight = 0
        var results: [CGWindowID: CGImage] = [:]
        var finished = false
        var done: CheckedContinuation<[CGWindowID: CGImage], Never>?

        init(_ requests: [(CGWindowID, CGSize)]) { pending = requests[...] }

        func finish() {
            guard !finished else { return }
            finished = true
            done?.resume(returning: results)
            done = nil
        }
    }
}

/// Snapshots by CG window ID, least recently used evicted first once their decoded size (`width * height * 4`) passes
/// `capacity`. Memory only: never written to disk or logged (T-04-13).
nonisolated struct SnapshotCache {
    static let capacity = 128 * 1024 * 1024
    let capacityBytes: Int
    private(set) var bytes = 0
    private var entries: [CGWindowID: (image: CGImage, cost: Int, used: UInt64)] = [:]
    private var tick: UInt64 = 0

    init(capacity: Int = SnapshotCache.capacity) { capacityBytes = capacity }

    var count: Int { entries.count }
    var ids: [CGWindowID] { Array(entries.keys) }

    /// Reading an entry makes it the most recently used.
    mutating func image(for id: CGWindowID) -> CGImage? {
        guard let entry = entries[id] else { return nil }
        tick += 1
        entries[id]?.used = tick
        return entry.image
    }

    mutating func insert(_ image: CGImage, for id: CGWindowID) {
        remove(id)
        let cost = image.width * image.height * 4
        guard cost <= capacityBytes else { return }
        // shortcut: eviction scans every entry (O(n)); fine for a few hundred windows, use a linked list past that.
        while bytes + cost > capacityBytes, let oldest = entries.min(by: { $0.value.used < $1.value.used })?.key { remove(oldest) }
        tick += 1
        entries[id] = (image, cost, tick)
        bytes += cost
    }

    mutating func remove(_ id: CGWindowID) {
        if let entry = entries.removeValue(forKey: id) { bytes -= entry.cost }
    }

    mutating func purge() {
        entries = [:]
        bytes = 0
    }
}

nonisolated struct CaptureFailure: Error {
    let description: String
}

/// Resumes its continuation exactly once, from whichever thread gets there first.
private nonisolated final class ResumeOnce<T: Sendable>: Sendable {
    private let continuation: OSAllocatedUnfairLock<CheckedContinuation<T, Never>?>

    init(_ continuation: CheckedContinuation<T, Never>) { self.continuation = OSAllocatedUnfairLock(initialState: continuation) }

    func resume(_ value: T) {
        continuation.withLock { stored -> CheckedContinuation<T, Never>? in
            defer { stored = nil }
            return stored
        }?.resume(returning: value)
    }
}

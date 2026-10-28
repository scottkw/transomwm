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
    private static let logger = Logger(subsystem: "com.eightabyte.transom", category: "capture")
    private var scWindows: [CGWindowID: SCWindow] = [:]

    public init() {}

    public static func isGranted() -> Bool { CGPreflightScreenCaptureAccess() }
    public static func request() -> Bool { CGRequestScreenCaptureAccess() }

    /// Re-reads the shareable windows. Slow: never call it on a move's critical path.
    public func refreshShareable() async throws {
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)
        scWindows = Dictionary(content.windows.map { ($0.windowID, $0) }, uniquingKeysWith: { first, _ in first })
    }

    /// One window at `pixelSize`, or nil when the window is unknown, the capture failed or it took over 1 s.
    public func capture(_ id: CGWindowID, pixelSize: CGSize) async -> CGImage? {
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
        switch result {
        case .success(let image):
            return image
        case .failure(let failure):
            Self.logger.notice("capture failed window \(id, privacy: .public): \(failure.description, privacy: .public)")
            return nil
        }
    }

    /// Captures at most `concurrency` windows at a time and returns those finished by `deadline`. Late results are dropped.
    public func captureAll(
        _ requests: [(CGWindowID, CGSize)], deadline: Duration = moveBudget, concurrency: Int = maxConcurrency
    ) async -> [CGWindowID: CGImage] {
        guard !requests.isEmpty else { return [:] }
        let batch = Batch(requests)
        return await withCheckedContinuation { continuation in
            batch.done = continuation
            for _ in 0..<max(1, concurrency) { startNext(batch) }
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

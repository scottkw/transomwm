import AppKit
import ApplicationServices
import PaneEngine
import PaneModel
import PanePrivate
import os

/// The live `WindowSystem`: one `AXAppThread` per regular app, a `WindowTracker` on MainActor.
///
/// MainActor only enqueues jobs and awaits Sendable results; every AX call runs on the app's own
/// thread (D-16, T-02-03). `inventory()` serves the cache and never waits for an app.
@MainActor public final class AXWindowSystem: WindowSystem {
    public nonisolated let events: AsyncStream<WindowEvent>
    private let continuation: AsyncStream<WindowEvent>.Continuation
    /// AX notification hints; consumed by the refresh scheduler (Plan 06).
    let hints: AsyncStream<AXEventHint>
    private let hintContinuation: AsyncStream<AXEventHint>.Continuation
    private let appFilter: @MainActor (Int32, String) -> Bool
    private let logger = Logger(subsystem: "com.eightabyte.pane", category: "ax")
    private var tracker = WindowTracker()
    private var threads: [Int32: AXAppThread] = [:]
    private var started = false
    private var initialRefreshComplete = false

    /// `appFilter(pid, bundleKey)` limits which apps get a thread (tests track only the fixture).
    public init(appFilter: @escaping @MainActor (Int32, String) -> Bool = { _, _ in true }) {
        (events, continuation) = AsyncStream.makeStream(bufferingPolicy: .bufferingNewest(1024))
        (hints, hintContinuation) = AsyncStream.makeStream(bufferingPolicy: .bufferingNewest(256))
        self.appFilter = appFilter
    }

    isolated deinit {
        for thread in threads.values { thread.stop() }
    }

    public var capabilityReport: [Capability: Bool] { Capabilities.report() }

    /// Sets the global AX timeout, creates a thread per regular app and runs the initial sweep.
    public func start() async {
        guard !started else { return }
        started = true
        // Per-element timeouts do not reach equal or child elements (Pitfall 1), so set the global one.
        AXUIElementSetMessagingTimeout(AXUIElementCreateSystemWide(), 1.0)
        let ownPID = ProcessInfo.processInfo.processIdentifier
        for app in NSWorkspace.shared.runningApplications
        where app.activationPolicy == .regular && app.isFinishedLaunching
            && app.processIdentifier != ownPID && app.bundleIdentifier != "com.apple.loginwindow"
        {
            guard let key = bundleKey(app), appFilter(app.processIdentifier, key) else { continue }
            threads[app.processIdentifier] = AXAppThread(pid: app.processIdentifier, bundleID: key, hints: hintContinuation)
        }
        await sweep(initial: true)
        initialRefreshComplete = true
    }

    /// Re-reads every tracked app concurrently.
    public func refreshAll() async {
        await sweep(initial: false)
    }

    public func inventory() async -> WindowInventory {
        WindowInventory(displays: [], windows: tracker.sortedWindows(), initialRefreshComplete: initialRefreshComplete)
    }

    public func perform(_ commands: [WindowCommand]) async {
        // shortcut: commands are dropped until the frame write pipeline lands (Plan 12).
        logger.info("dropping \(commands.count, privacy: .public) commands: no write pipeline yet")
    }

    public func windowInfo(_ window: PaneModel.WindowRef) async -> WindowInfo? {
        tracker.info(for: window.identity)
    }

    private func sweep(initial: Bool) async {
        let threads = Array(threads.values)
        await withTaskGroup(of: AppObservation?.self) { group in
            for thread in threads {
                group.addTask { await thread.observe() }
            }
            for await observation in group {
                guard let observation else { continue }
                if let failure = observation.listFailure {
                    logger.info("pid \(observation.pid, privacy: .public) AXWindows failed: \(String(describing: failure), privacy: .public)")
                }
                let context = ObservationContext(initialSweep: initial, now: .now)
                for event in tracker.ingest(observation, context: context) {
                    continuation.yield(event)
                }
            }
        }
    }

    /// The app's bundle ID, or `unbundled:<executable name>` for a bare executable; nil (logged) when neither exists.
    private func bundleKey(_ app: NSRunningApplication) -> String? {
        if let bundleID = app.bundleIdentifier { return bundleID }
        guard let name = app.executableURL?.lastPathComponent else {
            logger.error("pid \(app.processIdentifier, privacy: .public) has no bundle ID or executable; not tracked")
            return nil
        }
        logger.info("pid \(app.processIdentifier, privacy: .public) has no bundle ID; keyed unbundled:\(name, privacy: .public)")
        return "unbundled:" + name
    }
}

import ApplicationServices
import Foundation
import PaneEngine
import PaneModel
import os

/// An AX notification from one app. A hint only: it triggers a refresh, it never decides anything.
nonisolated struct AXEventHint: Sendable {
    let pid: Int32
    /// The window the notification is about, when it is one already in the thread's element cache.
    let windowID: UInt32?
    let notification: String
}

/// One thread per app with its own CFRunLoop (D-16). The app's AX elements and observer are created,
/// used and destroyed only on this thread, so a hung app blocks only its own thread, never main.
/// Only Sendable values (IDs, snapshots, rects) leave it.
nonisolated final class AXAppThread: @unchecked Sendable {
    let pid: Int32
    let bundleID: String
    private let hints: AsyncStream<AXEventHint>.Continuation
    private let ready = DispatchSemaphore(value: 0)
    private let stopped = OSAllocatedUnfairLock(initialState: false)
    // Written on the thread before `ready` signals, then only read.
    private var runLoop: CFRunLoop?
    // Thread-confined.
    private var app: AXUIElement?
    private var observer: AXObserver?
    /// Window elements seen by `observe()` with their assigned IDs, each registered for the per-window notifications.
    private var windows: [UInt32: CachedWindow] = [:]
    /// Test seam: identify windows by frame even when `_AXUIElementGetWindow` works.
    private let forceWindowIDFallback: Bool
    /// Latest-wins frame slots, one per window ID (D-16, T-02-34): a newer `enqueueFrame` overwrites a waiting one,
    /// and at most one drain is scheduled at a time.
    private let frames = OSAllocatedUnfairLock(initialState: FrameQueue())
    /// Every finished frame write, read back (D-17). Finishes when the thread stops.
    let frameResults: AsyncStream<FrameWriteResult>
    private let frameContinuation: AsyncStream<FrameWriteResult>.Continuation
    /// Bundles whose `AXEnhancedUserInterface` is left off after a write, because turning it back on is costly
    /// (Rectangle stopped doing it for Chrome). Empty until a bundle needs it; every other bundle gets it back.
    static let reenableEnhancedUIOverrides: [String: Bool] = [:]

    private struct FrameQueue {
        var slots: [UInt32: (rect: Rect, ref: PaneModel.WindowRef)] = [:]
        var drainScheduled = false
        var drainEnabled = true

        /// True when the caller must schedule a drain: enabled, frames waiting, none scheduled yet.
        mutating func claimDrain() -> Bool {
            guard drainEnabled, !drainScheduled, !slots.isEmpty else { return false }
            drainScheduled = true
            return true
        }
    }

    private static let appNotifications = [
        kAXWindowCreatedNotification, kAXFocusedWindowChangedNotification, kAXMainWindowChangedNotification,
        kAXApplicationHiddenNotification, kAXApplicationShownNotification,
    ]
    private static let windowNotifications = [
        kAXUIElementDestroyedNotification, kAXWindowMovedNotification, kAXWindowResizedNotification,
        kAXWindowMiniaturizedNotification, kAXWindowDeminiaturizedNotification, kAXTitleChangedNotification,
    ]

    init(pid: Int32, bundleID: String, hints: AsyncStream<AXEventHint>.Continuation, forceWindowIDFallback: Bool = false) {
        self.pid = pid
        self.bundleID = bundleID
        self.hints = hints
        self.forceWindowIDFallback = forceWindowIDFallback
        (frameResults, frameContinuation) = AsyncStream.makeStream(bufferingPolicy: .unbounded)
        let thread = Thread { [self] in
            runLoop = CFRunLoopGetCurrent()
            ready.signal()
            // Observer registration is AX IPC and can block on a hung app, so it happens after `ready`.
            app = AXUIElementCreateApplication(pid)
            installObserver()
            var context = CFRunLoopSourceContext()
            let keepAlive = CFRunLoopSourceCreate(nil, 0, &context)
            CFRunLoopAddSource(CFRunLoopGetCurrent(), keepAlive, .defaultMode)
            CFRunLoopRun()
            // Teardown in reverse creation order: observer, then window elements, then the app element.
            if let observer {
                CFRunLoopRemoveSource(CFRunLoopGetCurrent(), AXObserverGetRunLoopSource(observer), .defaultMode)
            }
            observer = nil
            windows = [:]
            app = nil
            CFRunLoopSourceInvalidate(keepAlive)
            frameContinuation.finish()
        }
        thread.name = "AXAppThread \(pid)"
        thread.start()
        ready.wait()
    }

    private func installObserver() {
        let callback: AXObserverCallback = { _, element, notification, refcon in
            guard let refcon else { return }
            // The thread object outlives its observer: the thread's closure retains it until teardown.
            // Runs on this thread's run loop, so reading the cache is thread-confined; CFEqual is no IPC.
            let me = Unmanaged<AXAppThread>.fromOpaque(refcon).takeUnretainedValue()
            let windowID = me.windows.first { CFEqual($0.value.element, element) }?.key
            me.hints.yield(AXEventHint(pid: me.pid, windowID: windowID, notification: notification as String))
        }
        var created: AXObserver?
        guard AXObserverCreate(pid, callback, &created) == .success, let created, let app else { return }
        let refcon = Unmanaged.passUnretained(self).toOpaque()
        for name in Self.appNotifications {
            _ = AXObserverAddNotification(created, app, name as CFString, refcon)
        }
        CFRunLoopAddSource(CFRunLoopGetCurrent(), AXObserverGetRunLoopSource(created), .defaultMode)
        observer = created
    }

    /// Runs `body` with the app element on this thread. Returns nil once the thread is stopped.
    func perform<T: Sendable>(_ body: @escaping @Sendable (AXUIElement) -> T) async -> T? {
        await withCheckedContinuation { (continuation: CheckedContinuation<T?, Never>) in
            // Enqueue under the lock so no job can land behind the stop block and never run.
            let enqueued = stopped.withLock { isStopped -> Bool in
                guard !isStopped, let runLoop else { return false }
                CFRunLoopPerformBlock(runLoop, CFRunLoopMode.defaultMode.rawValue) { [self] in
                    continuation.resume(returning: app.map(body))
                }
                CFRunLoopWakeUp(runLoop)
                return true
            }
            if !enqueued { continuation.resume(returning: nil) }
        }
    }

    /// Reads the app's windows on this thread and keeps the element cache and its registrations in step.
    /// Each `known` window that left `AXWindows` is probed through its cached element (one AXRole read), so a
    /// closed one answers -25202 instead of silently vanishing (D-09); one with no cached element is omitted.
    /// `duration` covers the whole job. A stop request ends the job between AX calls (nil) instead of
    /// letting a hung app time out on every remaining window.
    func observe(known: [UInt32] = []) async -> AppObservation? {
        await perform { [self] app -> AppObservation? in
            guard !isStopped else { return nil }
            let start = ContinuousClock.now
            let hidden = AXSnapshotReader.isHidden(app)
            guard !isStopped,
                  let (listed, elements) = AXSnapshotReader.observeApp(
                      app, pid: pid, bundleID: bundleID, hidden: hidden, cache: windows, forceFallback: forceWindowIDFallback,
                      isCancelled: { self.isStopped })
            else { return nil }
            var observation = listed
            if var cache = elements {
                for id in known where cache[id] == nil {
                    guard let cached = windows[id] else { continue }
                    if isStopped { return nil }
                    cache[id] = cached
                    observation.windows.append(WindowObservation(
                        windowID: id, idSource: cached.source, read: Self.role(of: cached.element), title: "", listedInAXWindows: false
                    ))
                }
                updateWindows(cache)
            }
            observation.duration = start.duration(to: .now)
            return observation
        } ?? nil
    }

    /// A probe of a window element: its AXRole, or the AX error that decides a close.
    private static func role(of element: AXUIElement) -> Result<WindowSnapshot, AXFailure> {
        var value: CFTypeRef?
        let error = AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &value)
        return error == .success ? .success(WindowSnapshot(role: value as? String)) : .failure(AXFailure(code: error.rawValue))
    }

    /// Reads only the app element's AXRole: the cheap check that a degraded app answers again (D-16).
    func probe() async -> (JobOutcome, Duration) {
        await perform { app -> (JobOutcome, Duration) in
            let start = ContinuousClock.now
            var value: CFTypeRef?
            let outcome: JobOutcome =
                switch AXUIElementCopyAttributeValue(app, kAXRoleAttribute as CFString, &value) {
                case .success: .success
                case .cannotComplete: .cannotComplete
                default: .otherFailure
                }
            return (outcome, start.duration(to: .now))
        } ?? (.otherFailure, .zero)
    }

    /// Puts `rect` in the window's slot, replacing any frame still waiting, and schedules a drain if none is.
    func enqueueFrame(windowID: UInt32, rect: Rect, ref: PaneModel.WindowRef) {
        let schedule = frames.withLock { queue in
            queue.slots[windowID] = (rect, ref)
            return queue.claimDrain()
        }
        if schedule { scheduleDrain() }
    }

    /// False while the app is degraded: frames wait in their slots. Back to true flushes the latest ones.
    var drainEnabled: Bool {
        get { frames.withLock { $0.drainEnabled } }
        set {
            let schedule = frames.withLock { queue in
                queue.drainEnabled = newValue
                return queue.claimDrain()
            }
            if schedule { scheduleDrain() }
        }
    }

    private func scheduleDrain() {
        stopped.withLock { isStopped in
            guard !isStopped, let runLoop else { return }
            CFRunLoopPerformBlock(runLoop, CFRunLoopMode.defaultMode.rawValue) { [self] in drainFrames() }
            CFRunLoopWakeUp(runLoop)
        }
    }

    /// Thread-confined. Writes every waiting frame against its cached element and yields each result. A write
    /// the app did not answer (-25204) goes back in its slot with the rest, unless a newer frame is waiting, and
    /// the drain stops: the app is not answering, and the responsiveness rule decides when to try again.
    private func drainFrames() {
        let batch = frames.withLock { queue -> [UInt32: (rect: Rect, ref: PaneModel.WindowRef)] in
            queue.drainScheduled = false
            guard queue.drainEnabled else { return [:] }
            defer { queue.slots = [:] }
            return queue.slots
        }
        let ordered = batch.sorted { $0.key < $1.key }
        for (index, (windowID, slot)) in ordered.enumerated() {
            guard !isStopped, let app else { return }
            guard let element = windows[windowID]?.element else {
                frameContinuation.yield(FrameWriteResult(window: slot.ref, requested: slot.rect, actual: nil, failure: .invalidElement))
                continue
            }
            let (actual, failure) = FrameWriter.write(
                slot.rect, window: element, app: app,
                reenableEnhancedUI: Self.reenableEnhancedUIOverrides[bundleID] ?? true, isCancelled: { self.isStopped })
            if isStopped { return }
            if failure == .cannotComplete {
                frames.withLock { queue in
                    for (id, waiting) in ordered[index...] where queue.slots[id] == nil { queue.slots[id] = waiting }
                }
            }
            frameContinuation.yield(FrameWriteResult(window: slot.ref, requested: slot.rect, actual: actual, failure: failure))
            if failure == .cannotComplete { return }
        }
    }

    /// The job token: true once `stop()` was called.
    private var isStopped: Bool { stopped.withLock { $0 } }

    /// Thread-confined. A window that left the cache (no longer listed or known) loses its registrations; it is
    /// re-added if it returns.
    private func updateWindows(_ current: [UInt32: CachedWindow]) {
        guard let observer else { return }
        let refcon = Unmanaged.passUnretained(self).toOpaque()
        for (id, cached) in windows where current[id] == nil {
            for name in Self.windowNotifications { _ = AXObserverRemoveNotification(observer, cached.element, name as CFString) }
        }
        for (id, cached) in current where windows[id] == nil {
            for name in Self.windowNotifications { _ = AXObserverAddNotification(observer, cached.element, name as CFString, refcon) }
        }
        windows = current
    }

    /// Stops the run loop after already-queued jobs; the thread then tears down its AX objects.
    func stop() {
        stopped.withLock { isStopped in
            guard !isStopped, let runLoop else { return }
            isStopped = true
            CFRunLoopPerformBlock(runLoop, CFRunLoopMode.defaultMode.rawValue) { CFRunLoopStop(CFRunLoopGetCurrent()) }
            CFRunLoopWakeUp(runLoop)
        }
    }
}

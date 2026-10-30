import AppKit
import TransomEngine
import TransomModel
import os

/// The main-actor owner of the gesture tap (05-03): publishes what its rules read, drains its events, logs and counts
/// each gesture once at its end (UI-SPEC Logging). Created by ArrangeController, which decides when the tap runs.
@MainActor final class GestureController {
    /// E-04 sender filter on: on the host, field 87 equalled the built-in trackpad's AppleMultitouchDevice registry ID on
    /// every gesture event (05-SPIKE T6). Events from any other sender (a mouse, a tablet) pass.
    static let filtersBySender = true

    private let tap: GestureTap
    private weak var controller: ArrangeController?
    private let log = Logger(subsystem: "com.eightabyte.transom", category: "gesture")
    /// The state the tap last got, so an unchanged one is not swapped in again.
    private var published: GestureTapState?
    private var reader: Task<Void, Never>?
    /// Between `start` and `stop`: only then is state published.
    private(set) var isActive = false
    private var loggedStartFailure = false
    private var seenCounters = GestureTapCounters()
    private var finderPID: Int32 = 0
    private var trackpadSenders: Set<UInt64> = []
    private var watcher: TrackpadWatcher?
    private var wakeObservers: [any NSObjectProtocol] = []

    /// The taken gesture whose samples are arriving, until its line is logged.
    private struct Current {
        var seq: UInt64
        var kind: GestureSample.Kind
        var reason: GestureSample.Reason?
        var first: Double
        var last: Double
        var events = 0
        var fingersUp = false
    }
    private var current: Current?
    /// Sequences whose line the timeout timer wrote; their late `.ended` writes none.
    private var loggedByTimer: Set<UInt64> = []
    private let timeoutTimer = WakeTimer()

    private(set) var taken = 0
    private(set) var timeouts = 0
    private(set) var passedWithOption = 0
    private(set) var republished = 0
    /// The last gesture the tap summed up (taken or passed), for plan 05-06's Debug lines.
    private(set) var lastSummary: GestureTapSummary?
    /// The current gesture's latest consumed sample; plan 05-04 feeds them to the recognizer.
    private(set) var latestSample: GestureSample?

    init(tap: GestureTap, controller: ArrangeController) {
        self.tap = tap
        self.controller = controller
    }

    /// Publishes the state, then starts the tap. False (logged once) when macOS refuses it.
    func start() -> Bool {
        isActive = true
        refresh()
        guard tap.start() else {
            isActive = false
            if !loggedStartFailure { log.error("gesture tap failed to start") }
            loggedStartFailure = true
            return false
        }
        loggedStartFailure = false
        log.info("gesture tap started")
        watcher = TrackpadWatcher { [weak self] in self?.refresh() }  // hot-plug: re-published, no line
        let center = NSWorkspace.shared.notificationCenter
        wakeObservers = [NSWorkspace.screensDidWakeNotification, NSWorkspace.didWakeNotification].map { name in
            center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.republish(reason: "wake") }
            }
        }
        if reader == nil {
            reader = Task { [weak self, tap] in
                for await event in tap.events {
                    guard let self else { return }
                    self.handle(event)
                }
            }
        }
        return true
    }

    /// Stops the tap; `reason` is `zoom off`, `access lost` or `quit`. A no-op when not active.
    func stop(reason: String) {
        guard isActive else { return }
        isActive = false
        tap.stop()
        watcher?.stop()
        watcher = nil
        for observer in wakeObservers { NSWorkspace.shared.notificationCenter.removeObserver(observer) }
        wakeObservers = []
        timeoutTimer.cancel()
        current = nil
        log.info("gesture tap stopped: \(reason, privacy: .public)")
    }

    /// After a watchdog tick: one line per re-enable kind whose counter grew.
    func noteReEnables() {
        let now = tap.counters()
        if now.reEnabledByTimeout > seenCounters.reEnabledByTimeout { log.info("gesture tap re-enabled after timeout") }
        if now.reEnabledByUserInput > seenCounters.reEnabledByUserInput { log.info("gesture tap re-enabled after user input") }
        seenCounters = now
    }

    /// Hands the tap what its rules read, when it changed. Called after every Arranger change and when readiness changes.
    func publish() {
        guard isActive, let controller else { return }
        let arranger = controller.arranger
        let disarm: GestureTapState.DisarmReason? =
            !controller.isReady() ? .notReady
            : !arranger.pauseReasons.isEmpty ? .zoomPaused
            : arranger.isDragging || controller.isRectZoomActive ? .rectZoomOrDrag : nil
        let hasDesk = { (display: DisplayInfo) in arranger.world[ZoomInput.deskKey(display)] != nil }
        let state = GestureTapState(
            armed: controller.isZoomEnabled && disarm == nil, disarmReason: disarm,
            deskDisplays: arranger.displays.filter(hasDesk).map { ZoomInput.cgRect($0.frame) },
            fullScreenDisplays: arranger.displays.filter { !hasDesk($0) }.map { ZoomInput.cgRect($0.frame) }, finderPID: finderPID,
            trackpadSenders: Self.filtersBySender ? trackpadSenders : [])
        guard state != published else { return }
        published = state
        tap.setState(state)
    }

    /// Re-reads what can change behind Transom's back and publishes even if nothing changed.
    func republish(reason: String) {
        guard isActive else { return }
        refresh()
        republished += 1
        log.info("gesture state re-published: \(reason, privacy: .public)")
    }

    private func refresh() {
        trackpadSenders = Set(Trackpads.current().map(\.registryID))
        finderPID = NSRunningApplication.runningApplications(withBundleIdentifier: Arranger.finderBundleID).first?.processIdentifier ?? 0
        published = nil
        publish()
    }

    private func handle(_ event: GestureTapEvent) {
        switch event {
        case .sample(let sample, let seq):
            latestSample = sample
            if current?.seq != seq {
                current = Current(seq: seq, kind: sample.kind, reason: sample.reason, first: sample.timestamp, last: sample.timestamp)
            }
            current?.events += 1
            current?.last = sample.timestamp
            current?.fingersUp = sample.kind == .pan && (sample.phase == 4 || sample.momentum != 0)
            let limit = current?.fingersUp == true ? GestureTapRules.quietTimeout : GestureTapRules.fingersDownTimeout
            timeoutTimer.set(.now + .seconds(limit) + .milliseconds(50)) { [weak self] in self?.expire(seq) }
        case .ended(let summary):
            lastSummary = summary
            if summary.seq == current?.seq {
                timeoutTimer.cancel()
                current = nil
            }
            guard loggedByTimer.remove(summary.seq) == nil else { return }
            logEnd(summary)
        }
    }

    /// No event for the latch's timeout: the tap drops the latch at its next event, but the line is due now. Quiet after
    /// lift is a normal end; quiet with fingers down is a release by timeout.
    private func expire(_ seq: UInt64) {
        guard let gesture = current, gesture.seq == seq else { return }
        current = nil
        loggedByTimer.insert(seq)
        let kind = gesture.kind == .pinch ? "pinch" : "pan"
        if gesture.fingersUp {
            taken += 1
            let ms = Int(((gesture.last - gesture.first) * 1000).rounded())
            let reason = gesture.reason == .wallpaper ? "wallpaper" : "⌥ held"
            log.info("took \(kind, privacy: .public) #\(seq, privacy: .public): \(reason, privacy: .public), \(gesture.events, privacy: .public) events, \(ms, privacy: .public) ms")
        } else {
            timeouts += 1
            let ms = Int(((Double(clock_gettime_nsec_np(CLOCK_UPTIME_RAW)) / 1e9 - gesture.first) * 1000).rounded())
            log.info("released \(kind, privacy: .public) #\(seq, privacy: .public) by timeout after \(ms, privacy: .public) ms (\(gesture.events, privacy: .public) events)")
        }
    }

    private func logEnd(_ summary: GestureTapSummary) {
        let kind = summary.kind == .pinch ? "pinch" : "pan"
        let ms = Int(((summary.endedAt - summary.startedAt) * 1000).rounded())
        let events = summary.consumed + summary.passed
        if summary.taken, summary.endedByTimeout, !summary.fingersUp {
            timeouts += 1
            log.info("released \(kind, privacy: .public) #\(summary.seq, privacy: .public) by timeout after \(ms, privacy: .public) ms (\(events, privacy: .public) events)")
        } else if summary.taken {
            taken += 1
            let reason = summary.reason == .wallpaper ? "wallpaper" : "⌥ held"
            log.info("took \(kind, privacy: .public) #\(summary.seq, privacy: .public): \(reason, privacy: .public), \(events, privacy: .public) events, \(ms, privacy: .public) ms")
        } else if summary.optionHeld {
            passedWithOption += 1
            log.debug("passed \(kind, privacy: .public) with ⌥: \(Self.optionPassText(summary.passReason), privacy: .public)")
        } else if summary.passReason == .windowUnderPointer {
            log.debug("passed \(kind, privacy: .public): window under pointer")
        } else if summary.passReason == .overlayUnderPointer {
            log.debug("passed \(kind, privacy: .public): menu or popover under pointer")
        }
    }

    /// UI-SPEC Logging's ⌥ pass reasons. A sequence decided without ⌥ (window, overlay, mid-sequence) that later had ⌥
    /// down is "⌥ pressed mid-gesture".
    private static func optionPassText(_ reason: GestureTapRules.PassReason?) -> String {
        switch reason {
        case .disarmed(.notReady): "not ready"
        case .disarmed(.rectZoomOrDrag): "rect zoom or drag in progress"
        case .disarmed: "zoom paused"
        case .fullScreen: "full screen"
        case .notDeskDisplay: "not a desk display"
        case .chord: "⌃ or ⌘ also held"
        case .notTrackpad: "not a trackpad"
        case .midSequence, .windowUnderPointer, .overlayUnderPointer, .shortCircuit, nil: "⌥ pressed mid-gesture"
        }
    }
}

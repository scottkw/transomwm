import AppKit
import TransomEngine
import TransomModel
import os

/// The main-actor owner of the gesture tap (05-03): publishes what its rules read, drains its events, logs and counts
/// each gesture once at its end (UI-SPEC Logging). Created by ArrangeController, which decides when the tap runs.
@MainActor final class GestureController {
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

    private(set) var taken = 0
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
            : arranger.isDragging ? .rectZoomOrDrag : nil
        let hasDesk = { (display: DisplayInfo) in arranger.world[ZoomInput.deskKey(display)] != nil }
        let state = GestureTapState(
            armed: controller.isZoomEnabled && disarm == nil, disarmReason: disarm,
            deskDisplays: arranger.displays.filter(hasDesk).map { ZoomInput.cgRect($0.frame) },
            fullScreenDisplays: arranger.displays.filter { !hasDesk($0) }.map { ZoomInput.cgRect($0.frame) }, finderPID: finderPID)
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
        finderPID = NSRunningApplication.runningApplications(withBundleIdentifier: Arranger.finderBundleID).first?.processIdentifier ?? 0
        published = nil
        publish()
    }

    private func handle(_ event: GestureTapEvent) {
        switch event {
        case .sample(let sample, _):
            latestSample = sample
        case .ended(let summary):
            lastSummary = summary
            logEnd(summary)
        }
    }

    private func logEnd(_ summary: GestureTapSummary) {
        let kind = summary.kind == .pinch ? "pinch" : "pan"
        let ms = Int(((summary.endedAt - summary.startedAt) * 1000).rounded())
        let events = summary.consumed + summary.passed
        if summary.taken {
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

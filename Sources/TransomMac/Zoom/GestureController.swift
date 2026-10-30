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

    /// The taken gesture's judgement and stage (05-04), from its first sample to its release.
    private struct Follow {
        var seq: UInt64
        var kind: GestureSample.Kind
        var recognizer: GestureRecognizer
        var uuid: String
        /// The pointer at the latch: the pinch point.
        var pointer: Point
        var first: Double
        var target: ViewTarget?
        var refusal: Navigator.Refusal?
        /// The stage is up for this gesture.
        var shown = false
        /// Released; kept until the tap ends the sequence, so its momentum tail starts no new judgement.
        var ended = false
    }
    private var follow: Follow?
    /// Polls the recognizer while a gesture is open: a released pan decides within `momentumWait` (05-02).
    private let recognizerTimer = WakeTimer()

    /// How a gesture ended, for the log line and plan 05-06's Debug line.
    enum Outcome: Equatable {
        case moved(ViewTarget), sprangBack, refused(Navigator.Refusal), tooSmall
    }
    struct LastGesture: Equatable {
        var seq: UInt64
        var kind: GestureSample.Kind
        /// Nil when it never left the dead zone or locked an axis.
        var direction: GestureRecognizer.Direction?
        var outcome: Outcome
    }
    private(set) var lastGesture: LastGesture?
    /// Sequences whose line the timeout timer wrote; their late `.ended` writes none.
    private var loggedByTimer: Set<UInt64> = []
    private let timeoutTimer = WakeTimer()

    private(set) var taken = 0
    private(set) var timeouts = 0
    private(set) var passedWithOption = 0
    private(set) var republished = 0
    /// The last gesture the tap summed up (taken or passed), for plan 05-06's Debug lines.
    private(set) var lastSummary: GestureTapSummary?
    /// The current gesture's latest consumed sample.
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
        if let seq = follow?.seq { finishFollow(seq) }  // never leave a stage up over the screen
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
            feed(sample, seq: seq)
        case .ended(let summary):
            lastSummary = summary
            if summary.seq == current?.seq {
                timeoutTimer.cancel()
                current = nil
            }
            guard loggedByTimer.remove(summary.seq) == nil else { return }
            if summary.taken { finishFollow(summary.seq) }
            logEnd(summary)
        }
    }

    /// No event for the latch's timeout: the tap drops the latch at its next event, but the line is due now. Quiet after
    /// lift is a normal end; quiet with fingers down is a release by timeout.
    private func expire(_ seq: UInt64) {
        guard let gesture = current, gesture.seq == seq else { return }
        current = nil
        loggedByTimer.insert(seq)
        finishFollow(seq)
        let kind = gesture.kind == .pinch ? "pinch" : "pan"
        if gesture.fingersUp {
            taken += 1
            let ms = Int(((gesture.last - gesture.first) * 1000).rounded())
            let reason = gesture.reason == .wallpaper ? "wallpaper" : "⌥ held"
            log.info("took \(kind, privacy: .public) #\(seq, privacy: .public): \(reason, privacy: .public), \(gesture.events, privacy: .public) events, \(ms, privacy: .public) ms\(self.outcomeText(seq), privacy: .public)")
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
            log.info("took \(kind, privacy: .public) #\(summary.seq, privacy: .public): \(reason, privacy: .public), \(events, privacy: .public) events, \(ms, privacy: .public) ms\(self.outcomeText(summary.seq), privacy: .public)")
        } else if summary.optionHeld {
            passedWithOption += 1
            log.debug("passed \(kind, privacy: .public) with ⌥: \(Self.optionPassText(summary.passReason), privacy: .public)")
        } else if summary.passReason == .windowUnderPointer {
            log.debug("passed \(kind, privacy: .public): window under pointer")
        } else if summary.passReason == .overlayUnderPointer {
            log.debug("passed \(kind, privacy: .public): menu or popover under pointer")
        }
    }

    // MARK: Follow (05-04)

    private static func uptime() -> Double { Double(clock_gettime_nsec_np(CLOCK_UPTIME_RAW)) / 1e9 }

    /// One taken sample into the recognizer; the first of a sequence picks the display under it and the pinch point.
    private func feed(_ sample: GestureSample, seq: UInt64) {
        if follow?.seq != seq {
            if let old = follow?.seq { finishFollow(old) }
            let pointer = Point(x: sample.location.x, y: sample.location.y)
            guard let display = controller?.arranger.displays.first(where: { $0.frame.contains(pointer) }) else { return }
            let size = Size(width: display.visibleFrame.width, height: display.visibleFrame.height)
            follow = Follow(
                seq: seq, kind: sample.kind, recognizer: GestureRecognizer(kind: sample.kind == .pinch ? .pinch : .pan, viewSize: size),
                uuid: display.uuid, pointer: pointer, first: sample.timestamp)
        }
        guard var gesture = follow, gesture.seq == seq else { return }
        let update = gesture.recognizer.feed(
            GestureRecognizer.Sample(
                t: sample.timestamp - gesture.first, kind: gesture.recognizer.kind, phase: sample.phase, momentum: sample.momentum,
                magnification: sample.magnification, dx: sample.dx, dy: sample.dy))
        follow = gesture
        apply(update)
        pollRecognizer(seq)
    }

    private func pollRecognizer(_ seq: UInt64) {
        guard let gesture = follow, gesture.seq == seq, !gesture.recognizer.isFinished else { return recognizerTimer.cancel() }
        recognizerTimer.set(.now + .seconds(GestureTuning.momentumWait)) { [weak self] in
            guard let self, var gesture = self.follow, gesture.seq == seq else { return }
            let update = gesture.recognizer.timeout(now: Self.uptime() - gesture.first)
            self.follow = gesture
            self.apply(update)
            self.pollRecognizer(seq)
        }
    }

    /// The tap ended or dropped the sequence: a recognizer still open decides now (a release, or a cancel with fingers
    /// down), so a stage that is up is always resolved.
    private func finishFollow(_ seq: UInt64) {
        guard var gesture = follow, gesture.seq == seq else { return }
        let update = gesture.recognizer.timeout(now: .greatestFiniteMagnitude)
        follow = gesture
        apply(update)
        if follow?.ended != true {  // never started (spike C2 noise): nothing to resolve
            lastGesture = LastGesture(seq: seq, kind: gesture.kind, direction: nil, outcome: .tooSmall)
        }
        follow = nil
    }

    private func apply(_ update: GestureRecognizer.Update?) {
        guard let update, var gesture = follow, let controller else { return }
        switch update {
        case .started(let direction):
            aim(&gesture, direction)
            if let target = gesture.target, let preview = controller.arranger.previewMove(to: target, displayUUID: gesture.uuid),
                controller.zoomController?.isIdle ?? true
            {
                // A busy display (a move or settle running, E-03) and a refused gesture are plan 05-05's.
                gesture.shown = controller.beginFollow(preview, gesture: Self.kindText(gesture.kind))
            }
            follow = gesture
            followFrame(gesture, direction)
        case .progress(let direction, _):
            followFrame(gesture, direction)
        case .reversed(let direction):
            aim(&gesture, direction)
            follow = gesture
            if gesture.shown {
                let preview = gesture.target.flatMap { controller.arranger.previewMove(to: $0, displayUUID: gesture.uuid) }
                if let move = preview ?? controller.arranger.stillMove(displayUUID: gesture.uuid) { controller.followStage().refollow(move) }
            }
            followFrame(gesture, direction)
        case .ended(let release):
            follow?.ended = true
            recognizerTimer.cancel()
            let outcome: Outcome =
                if release.tooSmall { .tooSmall } else if release.passedThreshold, let target = gesture.target { .moved(target) } else {
                    gesture.refusal.map { .refused($0) } ?? .sprangBack
                }
            lastGesture = LastGesture(seq: gesture.seq, kind: gesture.kind, direction: release.direction, outcome: outcome)
            let uuid = gesture.uuid
            guard case .moved(let target) = outcome else {
                if gesture.shown { controller.followStage().springBack(displayUUID: uuid) }
                return
            }
            // A committed gesture is an ordinary zoomTo: its .cameraMove retargets the following stage, then Phase 4's
            // settle, parks and history.
            Task { [weak controller] in
                guard let controller else { return }
                await controller.zoom(to: target, displayUUID: uuid)
                // Refused at the last moment (paused meanwhile): nothing took the stage over, so it springs back.
                if controller.zoomController?.isFollowing(uuid) == true { controller.followStage().springBack(displayUUID: uuid) }
            }
        }
    }

    /// The target for `direction`, from Phase 4's camera step with the pinch point; never a beep (UI-SPEC Surface 3).
    private func aim(_ gesture: inout Follow, _ direction: GestureRecognizer.Direction) {
        switch controller?.arranger.gestureTarget(direction, displayUUID: gesture.uuid, pointer: gesture.pointer) {
        case .success(let target)?: (gesture.target, gesture.refusal) = (target, nil)
        case .failure(let refusal)?: (gesture.target, gesture.refusal) = (nil, refusal)
        case nil: (gesture.target, gesture.refusal) = (nil, nil)
        }
    }

    private func followFrame(_ gesture: Follow, _ direction: GestureRecognizer.Direction) {
        guard gesture.shown, let controller else { return }
        controller.followStage().follow(
            displayUUID: gesture.uuid, state: gesture.recognizer.follow(hasTarget: gesture.target != nil), anchor: gesture.pointer,
            direction: direction)
    }

    private static func kindText(_ kind: GestureSample.Kind) -> String { kind == .pinch ? "pinch" : "pan" }

    /// ", moved to {node}" / ", sprang back" / ", too small" / ", {refusal}" for the took line (UI-SPEC Logging).
    private func outcomeText(_ seq: UInt64) -> String {
        guard let last = lastGesture, last.seq == seq else { return "" }
        return switch last.outcome {
        case .moved(let target): ", moved to \(target)"
        case .sprangBack: ", sprang back"
        case .tooSmall: ", too small"
        case .refused(let refusal): ", \(Self.refusalText(refusal))"
        }
    }

    private static func refusalText(_ refusal: Navigator.Refusal) -> String {
        switch refusal {
        case .alreadyHome: "already home"
        case .nothingToZoomIn: "nothing to zoom in to"
        case .noArea(let edge): "no area \(edge)"
        default: "\(refusal)"
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

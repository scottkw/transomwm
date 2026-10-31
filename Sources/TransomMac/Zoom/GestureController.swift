import AppKit
import TransomEngine
import TransomModel
import TransomPrivate
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
    /// E-04: on the host, field 87 equalled the built-in trackpad's AppleMultitouchDevice registry ID on every gesture
    /// event (05-SPIKE T6). Events from any other sender (a mouse, a tablet) pass, and all of them do when none is found.
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
        /// Left the dead zone or locked an axis.
        var started = false
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
    /// The tap's last seq before the current start: events at or below it are a stopped tap's, still buffered (WR-07).
    private var seqFloor: UInt64 = 0

    private(set) var taken = 0
    private(set) var timeouts = 0
    private(set) var passedWithOption = 0
    private(set) var republished = 0
    /// The last gesture the tap summed up (taken or passed), for plan 05-06's Debug lines.
    private(set) var lastSummary: GestureTapSummary?
    /// The current gesture's latest consumed sample.
    private(set) var latestSample: GestureSample?
    /// Posts a refusal's VoiceOver announcement; a seam for tests.
    var announce: (String) -> Void = { postAnnouncement($0) }

    /// Multitouch devices, started and stopped with the tap (05-07, D-07).
    let multitouch: MultitouchDevices
    /// One tracker per streaming device, and the multitouch pinch being followed (spike C4).
    private var trackers: [Int: TwoFingerTracker] = [:]
    private var multitouchPinch: (seq: UInt64, number: Int, reason: GestureSample.Reason?, location: CGPoint, first: Double, frames: Int)?
    private var multitouchCount = 0
    /// Tap sequences shut out by a multitouch pinch, ignored until their end (WR-10).
    private var suppressed: Set<UInt64> = []
    /// Multitouch sequences never collide with the tap's, which count up from 1.
    private static let multitouchSeqBase: UInt64 = 1 << 62

    init(tap: GestureTap, controller: ArrangeController, multitouch: MultitouchDevices = MultitouchDevices()) {
        self.tap = tap
        self.controller = controller
        self.multitouch = multitouch
    }

    /// Publishes the state, then starts the tap. False (logged once) when macOS refuses it.
    func start() -> Bool {
        isActive = true
        refresh()
        seqFloor = tap.counters().lastSeq  // read before the start, so no new sequence can fall under it
        guard tap.start() else {
            isActive = false
            if !loggedStartFailure { log.error("gesture tap failed to start") }
            loggedStartFailure = true
            return false
        }
        loggedStartFailure = false
        log.info("gesture tap started")
        multitouch.onFrame = { [weak self] frame, info in self?.multitouchFrame(frame, info) }
        multitouch.start()
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
        multitouch.stop()
        trackers = [:]
        multitouchPinch = nil
        suppressed = []
        watcher?.stop()
        watcher = nil
        for observer in wakeObservers { NSWorkspace.shared.notificationCenter.removeObserver(observer) }
        wakeObservers = []
        timeoutTimer.cancel()
        if let seq = follow?.seq { finishFollow(seq) }  // never leave a stage up over the screen
        current = nil
        loggedByTimer = []  // their late `.ended` can no longer be handled (WR-07)
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
        let disarm = Self.disarmReason(
            ready: controller.isReady(), paused: !arranger.pauseReasons.isEmpty, turningOff: controller.isTurningOff,
            busy: arranger.isDragging || controller.isRectZoomActive)
        let hasDesk = { (display: DisplayInfo) in arranger.world[ZoomInput.deskKey(display)] != nil }
        // The windows publishGreenButtons trusts, so the no-⌥ test skips the CG read over them (WR-01).
        let windows = arranger.windows.values.filter {
            $0.kind == .dockable && !$0.isExcluded && $0.state == .present && arranger.deskKey(of: $0.window) != nil
        }
        let state = GestureTapState(
            armed: controller.isZoomEnabled && disarm == nil, disarmReason: disarm,
            deskDisplays: arranger.displays.filter(hasDesk).map { ZoomInput.cgRect($0.frame) },
            fullScreenDisplays: arranger.displays.filter { !hasDesk($0) }.map { ZoomInput.cgRect($0.frame) }, finderPID: finderPID,
            trackpadSenders: trackpadSenders, windowRects: windows.map { ZoomInput.cgRect($0.frame) })
        guard state != published else { return }
        published = state
        tap.setState(state)
    }

    /// Why the tap is not armed. Turn Off Zoom's move home counts as paused: a gesture must not take it over (WR-09).
    nonisolated static func disarmReason(ready: Bool, paused: Bool, turningOff: Bool, busy: Bool, overviewOpen: Bool = false) -> GestureTapState.DisarmReason? {
        !ready ? .notReady : paused || turningOff ? .zoomPaused : busy ? .rectZoomOrDrag : nil
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

    /// WR-07: only the running tap's events count. Nothing is handled after `stop`, and after a restart the old tap's
    /// buffered events are dropped, so no stage comes up once the tap is gone.
    nonisolated static func isCurrent(_ event: GestureTapEvent, active: Bool, floor: UInt64) -> Bool {
        switch event {
        case .sample(_, let seq): active && seq > floor
        case .ended(let summary): active && summary.seq > floor
        }
    }

    private func handle(_ event: GestureTapEvent) {
        guard Self.isCurrent(event, active: isActive, floor: seqFloor) else { return }
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
            suppressed.remove(summary.seq)
            guard loggedByTimer.remove(summary.seq) == nil else { return }
            if summary.taken { finishFollow(summary.seq) }
            logEnd(summary)
        }
    }

    /// No event for the latch's timeout: the tap drops the latch at its next event, but the line is due now. Quiet after
    /// lift is a normal end; quiet with fingers down is a release by timeout.
    private func expire(_ seq: UInt64) {
        suppressed.remove(seq)
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
            // A multitouch pinch under way keeps the stage; the tap still consumes what it took (C4).
            let ownedByMultitouch = follow.map { $0.seq >= Self.multitouchSeqBase && $0.started && !$0.ended } ?? false
            if Self.dropsSample(seq, ownedByMultitouch: ownedByMultitouch, suppressed: &suppressed) { return }
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

    /// WR-10: a sample of another sequence is dropped while a started multitouch pinch owns the stage, and so is the rest
    /// of that sequence, until its end: tap events trail multitouch by ~63 ms (05-SPIKE M4), so its late samples must not
    /// open a new follow once the pinch has ended.
    nonisolated static func dropsSample(_ seq: UInt64, ownedByMultitouch: Bool, suppressed: inout Set<UInt64>) -> Bool {
        if ownedByMultitouch { suppressed.insert(seq) }
        return suppressed.contains(seq)
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
            gesture.started = true
            // A started gesture is a Transom command (UI-SPEC Surface 2); a two-finger rest that never starts is not (IN-06).
            controller.endPick(reason: "gesture")
            aim(&gesture, direction)
            // No target (refused, UI-SPEC Surface 3): the current view's still tile set overscrolls and springs back.
            let preview = gesture.target.flatMap { controller.arranger.previewMove(to: $0, displayUUID: gesture.uuid) }
            // A display that is busy (a move or settle running) is taken over by ZoomController (E-03).
            if let move = preview ?? controller.arranger.stillMove(displayUUID: gesture.uuid) {
                gesture.shown = controller.beginFollow(move, gesture: Self.kindText(gesture.kind))
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
                // Silent to the ear; VoiceOver hears the refusal only when the gesture would have committed (Surface 3).
                if case .refused(let refusal) = outcome, release.passedThreshold { announce(refusal.announcement) }
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

    /// The target for `direction`, from Phase 4's camera step with the pinch point; no sound (UI-SPEC Surface 3).
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

    // MARK: Multitouch pinch (05-07, spike C4)

    /// Two-finger frames become pinch samples for the same recognizer and follow path as the tap's. Multitouch never
    /// consumes anything; it supplies pinch only when the tap sees none.
    private func multitouchFrame(_ frame: MultitouchSupport.Frame, _ info: MultitouchSupport.Info) {
        var tracker = trackers[frame.device] ?? TwoFingerTracker(surface: Size(width: info.widthMM, height: info.heightMM))
        let touches = frame.touches.map { TwoFingerTracker.Touch(state: Int($0.state), x: Double($0.x), y: Double($0.y)) }
        let pinch = tracker.feed(t: frame.t, touches: touches).first { $0.kind == .pinch }
        trackers[frame.device] = tracker
        guard let pinch else { return }
        if pinch.phase == 1 {
            multitouchPinch = nil
            let location = CGEvent(source: nil)?.location ?? .zero  // the pinch point
            guard follow?.ended ?? true, let reason = takesMultitouchPinch(info, at: location, t: frame.t) else { return }
            multitouchCount += 1
            multitouchPinch = (Self.multitouchSeqBase + UInt64(multitouchCount), multitouchCount, reason, location, frame.t, 0)
        } else if let open = follow, let current = multitouchPinch, open.seq != current.seq {
            multitouchPinch = nil  // the tap took a gesture over
        }
        guard var current = multitouchPinch else { return }
        current.frames += 1
        multitouchPinch = current
        feed(
            GestureSample(
                kind: .pinch, phase: pinch.phase, momentum: 0, magnification: pinch.magnification, dx: 0, dy: 0, location: current.location,
                timestamp: frame.t, flags: [], senderID: info.registryID, reason: pinch.phase == 1 ? current.reason : nil),
            seq: current.seq)
        guard pinch.phase == 4 else { return }
        finishFollow(current.seq)
        multitouchPinch = nil
        taken += 1
        let ms = Int(((frame.t - current.first) * 1000).rounded())
        let reason = current.reason == .wallpaper ? "wallpaper" : "⌥ held"
        log.info("took pinch #m\(current.number, privacy: .public): multitouch, \(reason, privacy: .public), \(current.frames, privacy: .public) frames, \(ms, privacy: .public) ms\(self.outcomeText(current.seq), privacy: .public)")
    }

    /// The tap's own rules, as for a zoom-began event at the pointer, decide whether this pinch is Transom's: ⌥ held or
    /// bare wallpaper, armed, a desk display, no ⌃/⌘. Nil (not taken) while the system's pinch-zoom is on: the tap sees
    /// that pinch then, and two sources must not follow one gesture.
    private func takesMultitouchPinch(_ info: MultitouchSupport.Info, at location: CGPoint, t: Double) -> GestureSample.Reason? {
        guard !Self.systemPinchZoomOn() else { return nil }
        var latch = GestureTapRules.Latch()
        let input = GestureTapRules.Input(
            type: GestureEventFields.gestureType, hidType: GestureEventFields.hidZoom, gesturePhase: 1, senderID: info.registryID,
            flags: CGEventSource.flagsState(.combinedSessionState), location: location, timestamp: t)
        guard case .consume(let sample?) = GestureTapRules.decide(input, state: published ?? GestureTapState(), latch: &latch, surface: GestureTapRules.liveSurface)
        else { return nil }
        return sample.reason
    }

    /// System Settings ▸ Trackpad ▸ "Zoom in or out" (`TrackpadPinch`; absent means on, the default). With it off the tap
    /// gets no zoom events at all (05-SPIKE checklist item 3).
    static func systemPinchZoomOn() -> Bool {
        let domain = "com.apple.AppleMultitouchTrackpad" as CFString
        CFPreferencesAppSynchronize(domain)
        return CFPreferencesCopyAppValue("TrackpadPinch" as CFString, domain) as? Bool ?? true
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
    nonisolated static func optionPassText(_ reason: GestureTapRules.PassReason?) -> String {
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

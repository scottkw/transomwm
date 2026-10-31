import CoreGraphics
import Foundation
import TransomPrivate
import os

/// One gesture sequence the tap decided, summed up on the tap thread and handed to main when it ends (UI-SPEC Logging).
nonisolated struct GestureTapSummary: Equatable, Sendable {
    /// Per launch, shared by every start of the tap.
    var seq: UInt64
    var kind: GestureSample.Kind
    var taken: Bool
    var reason: GestureSample.Reason?
    var passReason: GestureTapRules.PassReason?
    /// ⌥ was down on any event of the sequence.
    var optionHeld: Bool
    var fingersUp = false
    var consumed = 0
    var passed = 0
    /// Uptime seconds of the first and last event.
    var startedAt: Double
    var endedAt: Double
    /// Its latch expired: a later event found it stale, its own end never came.
    var endedByTimeout = false
}

nonisolated enum GestureTapEvent: Sendable {
    case sample(GestureSample, seq: UInt64)
    case ended(GestureTapSummary)
}

nonisolated struct GestureTapCounters: Equatable, Sendable {
    var shortCircuited = 0
    var reEnabledByTimeout = 0
    var reEnabledByUserInput = 0
    /// The last sequence number handed out.
    var lastSeq: UInt64 = 0
}

/// What the gesture callback reaches through its refcon. `latch`, `pan` and `pinch` are touched on the tap thread only;
/// `port` and `runLoop` are written before the tap's source is added, then only read.
nonisolated private final class GestureTapBox: @unchecked Sendable {
    let continuation: AsyncStream<GestureTapEvent>.Continuation
    let state: OSAllocatedUnfairLock<GestureTapState>
    let counters: OSAllocatedUnfairLock<GestureTapCounters>
    var latch = GestureTapRules.Latch.none
    /// The open sequence per kind, as the latch holds it.
    var pan: GestureTapSummary?
    var pinch: GestureTapSummary?
    var port: CFMachPort?
    var runLoop: CFRunLoop?

    init(
        _ continuation: AsyncStream<GestureTapEvent>.Continuation, state: OSAllocatedUnfairLock<GestureTapState>,
        counters: OSAllocatedUnfairLock<GestureTapCounters>
    ) {
        self.continuation = continuation
        self.state = state
        self.counters = counters
    }

    /// Keeps the open summary of `kind` in step with the latch after one decided event, and yields its sample and its end.
    func track(
        _ kind: GestureSample.Kind, _ input: GestureTapRules.Input, before: GestureTapRules.Sequence?, after: GestureTapRules.Sequence?,
        decision: GestureTapRules.Decision
    ) {
        let now = input.timestamp
        var open = kind == .pinch ? pinch : pan
        let live = before.flatMap { GestureTapRules.isExpired($0, now: now) ? nil : $0 }
        if let stale = open, live?.started != stale.startedAt {
            var ended = stale
            ended.endedByTimeout = true
            continuation.yield(.ended(ended))
            open = nil
        }
        if let after, after.started == now, live?.started != now {
            if let replaced = open { continuation.yield(.ended(replaced)) }
            open = nil
            if after.passReason == .shortCircuit {
                counters.withLock { $0.shortCircuited += 1 }
            } else {
                let seq = counters.withLock { $0.lastSeq += 1; return $0.lastSeq }
                open = GestureTapSummary(
                    seq: seq, kind: kind, taken: after.consuming, reason: after.reason, passReason: after.passReason,
                    optionHeld: after.optionHeld, startedAt: now, endedAt: now)
            }
        }
        if var summary = open {
            if case .consume(let sample) = decision {
                summary.consumed += 1
                if let sample { continuation.yield(.sample(sample, seq: summary.seq)) }
            } else {
                summary.passed += 1
            }
            summary.endedAt = now
            summary.optionHeld = summary.optionHeld || input.flags.contains(.maskAlternate)
            summary.fingersUp = after?.fingersUp ?? summary.fingersUp
            if after == nil {
                continuation.yield(.ended(summary))
                open = nil
            } else {
                open = summary
            }
        }
        if kind == .pinch { pinch = open } else { pan = open }
    }
}

/// The gesture session tap (D-06, D-07, RESEARCH Pattern 1): scroll and kCGSEventGesture only, never bit 30. A sibling of
/// `InputTap` with the same thread, run loop and watchdog shape. It exists only while zoom is on and the mouse tap runs.
/// The callback copies fields, runs `GestureTapRules.decide` and consumes or passes: no logging, no AX, no file I/O.
/// Call `start`, `stop` and `watchdogTick` from one thread (main).
nonisolated final class GestureTap: @unchecked Sendable {
    static let mask = GestureTapRules.mask

    let events: AsyncStream<GestureTapEvent>
    private let continuation: AsyncStream<GestureTapEvent>.Continuation
    private var box: GestureTapBox?
    private(set) var port: CFMachPort?
    private(set) var thread: Thread?
    /// Main swaps the whole state; the callback holds the lock only to copy it.
    private let state = OSAllocatedUnfairLock(initialState: GestureTapState())
    private let counterLock = OSAllocatedUnfairLock(initialState: GestureTapCounters())

    init() {
        // Bounded: if main stalls, the oldest samples go, never the tap.
        (events, continuation) = AsyncStream.makeStream(bufferingPolicy: .bufferingNewest(256))
    }

    var isRunning: Bool { port.map(CFMachPortIsValid) ?? false }

    func setState(_ new: GestureTapState) {
        state.withLock { $0 = new }
    }

    func counters() -> GestureTapCounters {
        counterLock.withLock { $0 }
    }

    /// Creates the tap and starts its thread. False when macOS refuses the tap (no Accessibility access).
    func start() -> Bool {
        if isRunning { return true }
        let box = GestureTapBox(continuation, state: state, counters: counterLock)
        guard let port = Self.makePort(box) else { return false }
        box.port = port
        let ready = DispatchSemaphore(value: 0)
        let thread = Thread { [box] in
            let runLoop = CFRunLoopGetCurrent()
            box.runLoop = runLoop
            if let port = box.port, let source = CFMachPortCreateRunLoopSource(nil, port, 0) {
                CFRunLoopAddSource(runLoop, source, .commonModes)
                CGEvent.tapEnable(tap: port, enable: true)
            }
            ready.signal()
            CFRunLoopRun()
        }
        thread.name = "GestureTap"
        thread.qualityOfService = .userInteractive
        thread.start()
        ready.wait()
        self.box = box
        self.port = port
        self.thread = thread
        return true
    }

    /// Disables and invalidates the tap and ends its thread. Safe to call when stopped.
    func stop() {
        guard let port, CFMachPortIsValid(port) else { return }
        CGEvent.tapEnable(tap: port, enable: false)
        CFMachPortInvalidate(port)
        if let runLoop = box?.runLoop { CFRunLoopStop(runLoop) }
        box = nil
        thread = nil
    }

    /// InputTap's watchdog: re-enables a tap macOS disabled, and takes it down when a trial tap is refused (Pitfall 4).
    func watchdogTick() {
        guard let port, CFMachPortIsValid(port) else { return }
        guard let trial = Self.makePort(nil) else {
            stop()
            return
        }
        CFMachPortInvalidate(trial)
        if !CGEvent.tapIsEnabled(tap: port) { CGEvent.tapEnable(tap: port, enable: true) }
    }

    /// The only place a gesture tap is created, for the product tap and the watchdog's trial (nil box: passes everything).
    private static func makePort(_ box: GestureTapBox?) -> CFMachPort? {
        let callback: CGEventTapCallBack = { _, type, event, refcon in
            guard let refcon else { return Unmanaged.passUnretained(event) }
            let box = Unmanaged<GestureTapBox>.fromOpaque(refcon).takeUnretainedValue()
            if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
                if let port = box.port { CGEvent.tapEnable(tap: port, enable: true) }
                // Never resume a half-seen sequence: main resolves the open ones now, and a taken one's tail is still
                // swallowed (WR-05), since its events after the gap are no start.
                for case var summary? in [box.pan, box.pinch] {
                    summary.endedByTimeout = true
                    box.continuation.yield(.ended(summary))
                }
                box.latch = box.latch.orphaned()
                box.pan = nil
                box.pinch = nil
                box.counters.withLock {
                    if type == .tapDisabledByTimeout { $0.reEnabledByTimeout += 1 } else { $0.reEnabledByUserInput += 1 }
                }
                return Unmanaged.passUnretained(event)
            }
            let kind: GestureSample.Kind
            if type == .scrollWheel {
                kind = .pan
            } else if type.rawValue == GestureEventFields.gestureType {
                kind = .pinch
            } else {
                return Unmanaged.passUnretained(event)
            }
            let input = GestureTapRules.Input(event: event, type: type)
            let state = box.state.withLock { $0 }
            let before = kind == .pinch ? box.latch.pinch : box.latch.pan
            let decision = GestureTapRules.decide(input, state: state, latch: &box.latch, surface: GestureTapRules.liveSurface)
            box.track(kind, input, before: before, after: kind == .pinch ? box.latch.pinch : box.latch.pan, decision: decision)
            if case .consume = decision { return nil }
            return Unmanaged.passUnretained(event)
        }
        return CGEvent.tapCreate(
            tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap, eventsOfInterest: mask,
            callback: callback, userInfo: box.map { Unmanaged.passUnretained($0).toOpaque() })
    }
}

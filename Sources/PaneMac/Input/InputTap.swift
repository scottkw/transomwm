import CoreGraphics
import Foundation

/// One pointer or modifier event, copied out of the CGEvent in the tap callback. `location` is in global top-left
/// points, Pane's model space (A16, checked live).
nonisolated struct TapEvent: Sendable {
    let type: CGEventType
    let location: CGPoint
    let flags: CGEventFlags
    let windowUnderPointer: Int64
}

/// What the tap callback reaches through its refcon. Retained by the InputTap and by the tap thread for the tap's
/// lifetime. `port` and `runLoop` are written before the tap's source is added (and before `start` returns), then only
/// read.
nonisolated private final class TapBox: @unchecked Sendable {
    let continuation: AsyncStream<TapEvent>.Continuation
    var port: CFMachPort?
    var runLoop: CFRunLoop?

    init(_ continuation: AsyncStream<TapEvent>.Continuation) {
        self.continuation = continuation
    }
}

/// The one active session event tap (RESEARCH Pattern 6): left mouse down, dragged and up, and flagsChanged. No keyboard
/// key events are in the mask, so Pane never sees typed characters (T-03-28). It runs on its own thread with its own
/// CFRunLoop, never main (Pitfall 5). The callback copies four fields and returns the event unchanged: no AX, no file
/// I/O, no logging (T-03-29). Call `start`, `stop` and `watchdogTick` from one thread (main).
nonisolated final class InputTap: @unchecked Sendable {
    let events: AsyncStream<TapEvent>
    private let continuation: AsyncStream<TapEvent>.Continuation
    private var box: TapBox?
    /// The running tap's port (kept after `stop`, invalidated, so a check can read it).
    private(set) var port: CFMachPort?
    private(set) var thread: Thread?

    private static let mask: CGEventMask = (1 << CGEventType.leftMouseDown.rawValue) | (1 << CGEventType.leftMouseUp.rawValue)
        | (1 << CGEventType.leftMouseDragged.rawValue) | (1 << CGEventType.flagsChanged.rawValue)

    init() {
        // Bounded: if main stalls, the oldest samples go, never the tap.
        (events, continuation) = AsyncStream.makeStream(bufferingPolicy: .bufferingNewest(256))
    }

    var isRunning: Bool { port.map(CFMachPortIsValid) ?? false }

    /// Creates the tap and starts its thread. False when macOS refuses the tap (no Accessibility access).
    func start() -> Bool {
        if isRunning { return true }
        let box = TapBox(continuation)
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
            // Returns once `stop` invalidates the port (its source goes with it) or stops the run loop.
            CFRunLoopRun()
        }
        thread.name = "InputTap"
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

    /// The 2 s watchdog (RESEARCH Pattern 6): re-enables a tap macOS disabled, and takes the tap down at once when a
    /// trial tap is refused. An active tap left running after Accessibility is revoked can block clicks system-wide,
    /// while `AXIsProcessTrusted()` may still say yes (Pitfall 4, T-03-30).
    func watchdogTick() {
        guard let port, CFMachPortIsValid(port) else { return }
        guard let trial = Self.makePort(nil) else {
            stop()
            return
        }
        CFMachPortInvalidate(trial)
        if !CGEvent.tapIsEnabled(tap: port) { CGEvent.tapEnable(tap: port, enable: true) }
    }

    /// The only place a tap is created, for Pane's tap and for the watchdog's trial. A nil `box` gives a tap whose
    /// callback passes everything through.
    private static func makePort(_ box: TapBox?) -> CFMachPort? {
        let callback: CGEventTapCallBack = { _, type, event, refcon in
            guard let refcon else { return Unmanaged.passUnretained(event) }
            let box = Unmanaged<TapBox>.fromOpaque(refcon).takeUnretainedValue()
            if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
                if let port = box.port { CGEvent.tapEnable(tap: port, enable: true) }
                return Unmanaged.passUnretained(event)
            }
            box.continuation.yield(TapEvent(
                type: type, location: event.location, flags: event.flags,
                windowUnderPointer: event.getIntegerValueField(.mouseEventWindowUnderMousePointer)))
            return Unmanaged.passUnretained(event)
        }
        return CGEvent.tapCreate(
            tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap, eventsOfInterest: mask,
            callback: callback, userInfo: box.map { Unmanaged.passUnretained($0).toOpaque() })
    }
}

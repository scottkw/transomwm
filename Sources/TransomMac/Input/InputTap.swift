import CoreGraphics
import Foundation
import TransomEngine
import TransomModel
import os

/// One pointer or modifier event, copied out of the CGEvent in the tap callback. `location` is in global top-left
/// points, Transom's model space (A16, checked live).
nonisolated struct TapEvent: Sendable {
    enum Kind: Equatable, Sendable {
        case pointer
        /// A swallowed press on this window's green button (TILE-06).
        case greenButton(windowID: UInt32)
        /// A taken zoom press: every event of a rubber band, or the mouse-down of a pick or title-bar click (04-06).
        case zoom(ZoomTapRules.Kind)
    }

    var kind: Kind = .pointer
    let type: CGEventType
    let location: CGPoint
    let flags: CGEventFlags
    let windowUnderPointer: Int64
    /// `mouseEventClickState`: 2 on the second press of a double-click.
    var clickState: Int64 = 0
}

/// What the tap callback reaches through its refcon. Retained by the InputTap and by the tap thread for the tap's
/// lifetime. `port` and `runLoop` are written before the tap's source is added (and before `start` returns), then only
/// read.
nonisolated private final class TapBox: @unchecked Sendable {
    let continuation: AsyncStream<TapEvent>.Continuation
    let greenButtons: OSAllocatedUnfairLock<[UInt32: CGRect]>
    let zoomState: OSAllocatedUnfairLock<ZoomTapState>
    let dragOption: OSAllocatedUnfairLock<DragOptionStrip>
    /// A green-button press was taken and its click is not over yet. Read and written on the tap thread only.
    var swallowing = false
    /// The zoom press being taken. Tap thread only.
    var zoomSwallow = ZoomTapRules.Swallow.none
    var port: CFMachPort?
    var runLoop: CFRunLoop?

    init(
        _ continuation: AsyncStream<TapEvent>.Continuation, greenButtons: OSAllocatedUnfairLock<[UInt32: CGRect]>,
        zoomState: OSAllocatedUnfairLock<ZoomTapState>, dragOption: OSAllocatedUnfairLock<DragOptionStrip>
    ) {
        self.continuation = continuation
        self.greenButtons = greenButtons
        self.zoomState = zoomState
        self.dragOption = dragOption
    }
}

/// The one active session event tap (RESEARCH Pattern 6): left mouse down, dragged and up, and flagsChanged. No keyboard
/// key events are in the mask, so Transom never sees typed characters (T-03-28). It runs on its own thread with its own
/// CFRunLoop, never main (Pitfall 5). The callback copies four fields and passes the event on: no AX, no file I/O, no
/// logging (T-03-29). The exceptions are a press on a published green button (TILE-06) and the zoom presses `ZoomTapRules`
/// takes (04-06), which it takes, and ⌥, which it removes from a passed `flagsChanged`, `leftMouseDragged` or `leftMouseUp`
/// during a window move when `DragOptionRule` says so, after Transom has its own copy (D-07a).
/// Call `start`, `stop` and `watchdogTick` from one thread (main).
nonisolated final class InputTap: @unchecked Sendable {
    let events: AsyncStream<TapEvent>
    private let continuation: AsyncStream<TapEvent>.Continuation
    private var box: TapBox?
    /// The running tap's port (kept after `stop`, invalidated, so a check can read it).
    private(set) var port: CFMachPort?
    private(set) var thread: Thread?
    /// Writers swap the whole dictionary; the callback holds the lock only to copy it (T-03-35).
    private let greenButtons = OSAllocatedUnfairLock(initialState: [UInt32: CGRect]())
    private let zoomState = OSAllocatedUnfairLock(initialState: ZoomTapState())
    /// Written by the Arranger's every change, and cleared by the callback on every mouse-down.
    private let dragOption = OSAllocatedUnfairLock(initialState: DragOptionStrip.off)

    private static let mask: CGEventMask = (1 << CGEventType.leftMouseDown.rawValue) | (1 << CGEventType.leftMouseUp.rawValue)
        | (1 << CGEventType.leftMouseDragged.rawValue) | (1 << CGEventType.flagsChanged.rawValue)

    init() {
        // Bounded: if main stalls, the oldest samples go, never the tap.
        (events, continuation) = AsyncStream.makeStream(bufferingPolicy: .bufferingNewest(256))
    }

    var isRunning: Bool { port.map(CFMachPortIsValid) ?? false }

    /// The green buttons whose press Transom takes, in global top-left points, by CG window ID.
    func setGreenButtons(_ rects: [UInt32: CGRect]) {
        greenButtons.withLock { $0 = rects }
    }

    /// What the zoom rules read (ZoomInput publishes it whole).
    func setZoomState(_ state: ZoomTapState) {
        zoomState.withLock { $0 = state }
    }

    /// What the callback does with ⌥ on the events it passes on (D-07a).
    func setDragOption(_ state: DragOptionStrip) {
        dragOption.withLock { $0 = state }
    }

    /// Creates the tap and starts its thread. False when macOS refuses the tap (no Accessibility access).
    func start() -> Bool {
        if isRunning { return true }
        let box = TapBox(continuation, greenButtons: greenButtons, zoomState: zoomState, dragOption: dragOption)
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

    /// The only place a tap is created, for Transom's tap and for the watchdog's trial. A nil `box` gives a tap whose
    /// callback passes everything through.
    private static func makePort(_ box: TapBox?) -> CFMachPort? {
        let callback: CGEventTapCallBack = { _, type, event, refcon in
            guard let refcon else { return Unmanaged.passUnretained(event) }
            let box = Unmanaged<TapBox>.fromOpaque(refcon).takeUnretainedValue()
            if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
                if let port = box.port { CGEvent.tapEnable(tap: port, enable: true) }
                return Unmanaged.passUnretained(event)
            }
            let userData = event.getIntegerValueField(.eventSourceUserData)
            // Transom's own re-posted ⌘⇧-click goes straight to the app, unseen by every rule and by the Arranger.
            if userData == ZoomTapRules.repostTag { return Unmanaged.passUnretained(event) }
            // Here, before any rule can consume the press: a lost mouse-up must not leave ⌥ stripped from the next click.
            if type == .leftMouseDown { box.dragOption.withLock { $0 = .off } }
            let location = event.location
            let clickState = event.getIntegerValueField(.mouseEventClickState)
            var window = event.getIntegerValueField(.mouseEventWindowUnderMousePointer)
            let rects = box.greenButtons.withLock { $0 }
            let zoom = box.zoomState.withLock { $0 }
            // No window in the event: only a press inside a published rect pays for one CG list read, to find who is on top.
            if type == .leftMouseDown, window == 0,
                rects.values.contains(where: { $0.contains(location) })
                    || ZoomTapRules.needsWindow(location: location, clickState: clickState, state: zoom)
            {
                window = Int64(CGWindowList.topmostWindow(at: Point(x: location.x, y: location.y)) ?? 0)
            }
            let id = UInt32(truncatingIfNeeded: window)
            // Zoom first, so a ⌘⇧ press never reaches the green-button rule.
            switch ZoomTapRules.decide(
                type: type, location: location, flags: event.flags, clickState: clickState, windowID: id, userData: userData, state: zoom,
                swallow: &box.zoomSwallow)
            {
            case .consume(let kind?):
                box.continuation.yield(
                    TapEvent(kind: .zoom(kind), type: type, location: location, flags: event.flags, windowUnderPointer: window, clickState: clickState))
                return nil
            case .consume(nil):
                return nil
            case .pass:
                break
            }
            if GreenButton.shouldSwallow(type: type, location: location, flags: event.flags, windowID: id, rects: rects, swallowing: &box.swallowing) {
                if type == .leftMouseDown {
                    box.continuation.yield(TapEvent(kind: .greenButton(windowID: id), type: type, location: location, flags: event.flags, windowUnderPointer: window))
                }
                return nil
            }
            box.continuation.yield(TapEvent(type: type, location: location, flags: event.flags, windowUnderPointer: window, clickState: clickState))
            // After the copy above: Transom still reads ⌥, macOS's own ⌥ tiling doesn't (D-07a).
            let strip = box.dragOption.withLock { $0 }
            if DragOptionRule.strips(type: type, flags: event.flags, state: strip, leftButtonDown: CGEventSource.buttonState(.combinedSessionState, button: .left)) {
                event.flags.remove(.maskAlternate)
            }
            return Unmanaged.passUnretained(event)
        }
        return CGEvent.tapCreate(
            tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap, eventsOfInterest: mask,
            callback: callback, userInfo: box.map { Unmanaged.passUnretained($0).toOpaque() })
    }
}

import AppKit
import CoreGraphics
import Foundation
import TransomEngine
@testable import TransomMac
import TransomModel
import TransomPrivate
import Testing
import os

/// A pass-through tap at the tail of the session: counts what survived every head tap. Active, not listen-only, as the
/// 05-01 spike's counter was, so it surely runs after the gesture tap.
private final class Downstream: @unchecked Sendable {
    private let count = OSAllocatedUnfairLock(initialState: 0)
    private var port: CFMachPort?
    private var runLoop: CFRunLoop?

    init() throws {
        let callback: CGEventTapCallBack = { _, type, event, refcon in
            if let refcon, type != .tapDisabledByTimeout, type != .tapDisabledByUserInput {
                Unmanaged<Downstream>.fromOpaque(refcon).takeUnretainedValue().count.withLock { $0 += 1 }
            }
            return Unmanaged.passUnretained(event)
        }
        guard let port = CGEvent.tapCreate(
            tap: .cgSessionEventTap, place: .tailAppendEventTap, options: .defaultTap, eventsOfInterest: GestureTap.mask,
            callback: callback, userInfo: Unmanaged.passUnretained(self).toOpaque())
        else { throw FixtureError(description: "the downstream tap was refused") }
        self.port = port
        let ready = DispatchSemaphore(value: 0)
        Thread { [self] in
            let loop = CFRunLoopGetCurrent()
            runLoop = loop
            if let port = self.port {
                CFRunLoopAddSource(loop, CFMachPortCreateRunLoopSource(nil, port, 0), .commonModes)
                CGEvent.tapEnable(tap: port, enable: true)
            }
            ready.signal()
            CFRunLoopRun()
        }.start()
        ready.wait()
    }

    var value: Int { count.withLock { $0 } }

    func stop() {
        guard let port else { return }
        CGEvent.tapEnable(tap: port, enable: false)
        CFMachPortInvalidate(port)
        if let runLoop { CFRunLoopStop(runLoop) }
        self.port = nil
    }
}

/// Everything a GestureTap yielded while it was being collected.
private final class Collected: @unchecked Sendable {
    private let events = OSAllocatedUnfairLock(initialState: [GestureTapEvent]())
    private var task: Task<Void, Never>?

    init(_ tap: GestureTap) {
        task = Task { [events] in
            for await event in tap.events { events.withLock { $0.append(event) } }
        }
    }

    var samples: [GestureSample] { events.withLock { $0 }.compactMap { if case .sample(let s, _) = $0 { s } else { nil } } }
    var ended: [GestureTapSummary] { events.withLock { $0 }.compactMap { if case .ended(let s) = $0 { s } else { nil } } }
    func stop() { task?.cancel() }
}

private let option = CGEventFlags.maskAlternate

/// Synthetic magnify (type 29, sub-type `hid`) and phased scroll events (RESEARCH Code Examples). VM only.
private func magnify(_ phase: Int64, hid: Int64 = GestureEventFields.hidZoom, value: Double = 0.03, flags: CGEventFlags) -> (CGPoint) -> CGEvent? {
    { point in
        guard let event = CGEvent(source: nil), let type = CGEventType(rawValue: GestureEventFields.gestureType) else { return nil }
        event.type = type
        event.setIntegerValueField(GestureEventFields.hidType, value: hid)
        event.setIntegerValueField(GestureEventFields.phase, value: phase)
        event.setDoubleValueField(GestureEventFields.zoomValue, value: value)
        event.flags = flags
        event.location = point
        return event
    }
}

private func scroll(_ phase: Int64, momentum: Int64 = 0, continuous: Bool = true, flags: CGEventFlags) -> (CGPoint) -> CGEvent? {
    { point in
        guard let event = CGEvent(scrollWheelEvent2Source: nil, units: continuous ? .pixel : .line, wheelCount: 2, wheel1: -6, wheel2: 0, wheel3: 0)
        else { return nil }
        if continuous {
            event.setIntegerValueField(.scrollWheelEventScrollPhase, value: phase)
            event.setIntegerValueField(.scrollWheelEventMomentumPhase, value: momentum)
        }
        event.flags = flags
        event.location = point
        return event
    }
}

private func pinch(_ flags: CGEventFlags, changes: Int = 10) -> [(CGPoint) -> CGEvent?] {
    [magnify(1, flags: flags)] + Array(repeating: magnify(2, flags: flags), count: changes) + [magnify(4, value: 0, flags: flags)]
}

/// Posts `events` at `point` through the HID tap, 8 ms apart, then lets them settle; returns how many reached `downstream`.
private func post(_ events: [(CGPoint) -> CGEvent?], at point: CGPoint, downstream: Downstream) async throws -> Int {
    CGWarpMouseCursorPosition(point)
    try await Task.sleep(for: .milliseconds(300))
    let before = downstream.value
    for make in events {
        make(point)?.post(tap: .cghidEventTap)
        try await Task.sleep(for: .milliseconds(8))
    }
    try await Task.sleep(for: .milliseconds(400))
    return downstream.value - before
}

private func displayFrames() -> [CGRect] {
    var ids = [CGDirectDisplayID](repeating: 0, count: 16)
    var count: UInt32 = 0
    CGGetActiveDisplayList(16, &ids, &count)
    return ids.prefix(Int(count)).map(CGDisplayBounds)
}

private func center(_ rect: Rect) -> CGPoint { CGPoint(x: rect.x + rect.width / 2, y: rect.y + rect.height / 2) }

/// ⌥ scroll began, `changes` changed, ended; then momentum 1, 2 ×5, 3 with ⌥ already released.
private func pan(_ flags: CGEventFlags, changes: Int = 8, momentum: Bool = false) -> [(CGPoint) -> CGEvent?] {
    var events = [scroll(1, flags: flags)] + Array(repeating: scroll(2, flags: flags), count: changes) + [scroll(4, flags: flags)]
    if momentum { events += [scroll(0, momentum: 1, flags: [])] + Array(repeating: scroll(0, momentum: 2, flags: []), count: 5) + [scroll(0, momentum: 3, flags: [])] }
    return events
}

/// A bare-wallpaper point on the main display, far from `avoid` (the 05-01 spike's 8 pt grid: the VM desk may be nearly
/// covered by windows other runs left open).
private func wallpaperPoint(avoiding avoid: CGRect = .null) -> CGPoint? {
    let display = CGDisplayBounds(CGMainDisplayID())
    guard let list = CGWindowList.onScreenFrontToBack() else { return nil }
    var best: (CGPoint, Double)?
    for x in stride(from: display.minX + 4, to: display.maxX, by: 8) {
        for y in stride(from: display.minY + 4, to: display.maxY, by: 8) {
            let p = CGPoint(x: x, y: y)
            guard avoid.isNull || !avoid.insetBy(dx: -40, dy: -40).contains(p),
                GestureTapRules.surface(at: p, in: list, excludingPID: getpid(), display: display) == .wallpaper
            else { continue }
            let distance = avoid.isNull ? 0 : hypot(p.x - avoid.midX, p.y - avoid.midY)
            if distance > (best?.1 ?? -1) { best = (p, distance) }
        }
    }
    return best?.0
}

/// A started GestureTap armed on every display, and the downstream counter; both stopped after `body`.
@MainActor private func withArmedTap(_ body: (GestureTap, Downstream) async throws -> Void) async throws {
    let tap = GestureTap()
    defer { tap.stop() }
    tap.setState(GestureTapState(armed: true, deskDisplays: displayFrames()))
    try #require(tap.start())
    let downstream = try Downstream()
    defer { downstream.stop() }
    try await body(tap, downstream)
}

/// The centre of one fixture window, which stays open for `body`.
@MainActor private func withFixtureWindow(_ body: (CGPoint, CGRect) async throws -> Void) async throws {
    let fixture = try await FixtureProcess.launch(["standard"])
    defer { fixture.terminate() }
    let frame = try #require(fixture.windows.first).frame
    try await Task.sleep(for: .milliseconds(500))
    try await body(center(frame), CGRect(x: frame.x, y: frame.y, width: frame.width, height: frame.height))
}

/// D-06 / D-07 / GEST-03 / GEST-04 live, with synthetic events in the VM only (never on the host): Transom's gesture tap
/// takes whole sequences, passes everything it should, and exists only while zoom is on. Every tap is stopped in a defer.
@Suite(.serialized, .enabled(if: IntegrationEnv.trusted, "needs a process with the Accessibility grant"))
@MainActor struct GestureTapIntegrationTests {
    /// The window server connection first (ZoomSettleIntegrationTests: `CGS_REQUIRE_INIT`).
    init() { _ = NSApplication.shared }

    @Test(.timeLimit(.minutes(1)))
    func anOptionPinchIsConsumedWhole() async throws {
        let tap = GestureTap()
        defer { tap.stop() }
        tap.setState(GestureTapState(armed: true, deskDisplays: displayFrames()))
        #expect(tap.start())
        let collected = Collected(tap)
        defer { collected.stop() }
        let downstream = try Downstream()
        defer { downstream.stop() }
        let display = try #require(displayFrames().first)

        let survived = try await post(pinch(option), at: CGPoint(x: display.midX, y: display.midY), downstream: downstream)
        #expect(survived == 0, "\(survived) of 12 ⌥-pinch events reached the app")
        #expect(collected.samples.count >= 10)
        let ended = try #require(collected.ended.last)
        #expect(ended.taken && ended.kind == .pinch && ended.reason == .optionHeld && ended.consumed == 12)
    }

    @Test(.timeLimit(.minutes(1)))
    func zoomOffMeansNoGestureTapAndEverythingPasses() async throws {
        let fixture = try await FixtureProcess.launch(["standard"])
        defer { fixture.terminate() }
        let fixturePID = fixture.pid
        let system = AXWindowSystem(appFilter: { pid, _ in pid == fixturePID })
        await system.start()
        let arrange = ArrangeController(system: system, zoomEnabled: false)
        defer {
            arrange.stopTap()
            withExtendedLifetime(arrange) {}
        }
        await arrange.start()
        let hasDesk = await waitUntil(timeout: .seconds(5)) {
            arrange.arranger.displays.contains { arrange.arranger.world[ZoomInput.deskKey($0)] != nil }
        }
        try #require(hasDesk, "no display got a desk")
        #expect(arrange.startTap())
        let downstream = try Downstream()
        defer { downstream.stop() }
        let window = try #require(fixture.windows.first)
        let point = center(window.frame)

        #expect(!arrange.isGestureTapRunning, "a gesture tap runs with zoom off")
        #expect(try await post(pinch(option), at: point, downstream: downstream) == 12)

        await arrange.setZoomEnabled(true)
        #expect(arrange.isGestureTapRunning)
        #expect(try await post(pinch(option), at: point, downstream: downstream) == 0)

        await arrange.setZoomEnabled(false)
        let stopped = await waitUntil(timeout: .seconds(4)) { !arrange.isGestureTapRunning }
        #expect(stopped, "the gesture tap outlived Turn Off Zoom")
        #expect(try await post(pinch(option), at: point, downstream: downstream) == 12)
    }

    /// C1 (05-SPIKE T2): the sub-type 4 events that leaked inside taken pinches on the host are taken too.
    @Test(.timeLimit(.minutes(1)))
    func subTypeFourInsideAnOptionPinchIsConsumed() async throws {
        try await withArmedTap { _, downstream async throws in
            let events = Array(pinch(option, changes: 3).dropLast()) + Array(repeating: magnify(2, hid: 4, flags: option), count: 4)
                + [magnify(4, value: 0, flags: option)]
            let display = try #require(displayFrames().first)
            #expect(try await post(events, at: CGPoint(x: display.midX, y: display.midY), downstream: downstream) == 0)
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func momentumTailNeverLeaks() async throws {
        try await withArmedTap { tap, downstream async throws in
            let collected = Collected(tap)
            defer { collected.stop() }
            let display = try #require(displayFrames().first)
            #expect(try await post(pan(option, momentum: true), at: CGPoint(x: display.midX, y: display.midY), downstream: downstream) == 0)
            let ended = try #require(collected.ended.last)
            #expect(ended.taken && ended.kind == .pan && ended.consumed == 17 && !ended.endedByTimeout)
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func optionPressedMidSequencePasses() async throws {
        try await withFixtureWindow { point, _ async throws in
            try await withArmedTap { _, downstream async throws in
                let events = [scroll(1, flags: [])] + Array(repeating: scroll(2, flags: option), count: 8) + [scroll(4, flags: option)]
                #expect(try await post(events, at: point, downstream: downstream) == 10)
            }
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func aDiscreteWheelWithOptionPasses() async throws {
        try await withArmedTap { _, downstream async throws in
            let display = try #require(displayFrames().first)
            let wheel = Array(repeating: scroll(0, continuous: false, flags: option), count: 5)
            #expect(try await post(wheel, at: CGPoint(x: display.midX, y: display.midY), downstream: downstream) == 5)
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func controlOrCommandChordsPass() async throws {
        try await withArmedTap { _, downstream async throws in
            let display = try #require(displayFrames().first)
            let point = CGPoint(x: display.midX, y: display.midY)
            #expect(try await post(pinch([.maskAlternate, .maskControl]), at: point, downstream: downstream) == 12)
            #expect(try await post(pan([.maskAlternate, .maskCommand]), at: point, downstream: downstream) == 10)
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func wallpaperWithoutOptionIsTaken() async throws {
        let point = try #require(wallpaperPoint(), "no bare wallpaper on the main display")
        try await withArmedTap { _, downstream async throws in
            #expect(try await post(pinch([]), at: point, downstream: downstream) == 0)
            #expect(try await post(pan([], momentum: true), at: point, downstream: downstream) == 0)
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func aWindowWithoutOptionPasses() async throws {
        try await withFixtureWindow { point, _ async throws in
            try await withArmedTap { _, downstream async throws in
                #expect(try await post(pinch([]), at: point, downstream: downstream) == 12)
                #expect(try await post(pan([]), at: point, downstream: downstream) == 10)
            }
        }
    }

    /// T-05-08: an ⌥ pan whose end never comes holds its latch 2 s at most; the next plain scroll reaches the app.
    @Test(.timeLimit(.minutes(1)))
    func aStuckLatchReleasesTheNextScroll() async throws {
        try await withFixtureWindow { point, _ async throws in
            try await withArmedTap { _, downstream async throws in
                let stuck = [scroll(1, flags: option)] + Array(repeating: scroll(2, flags: option), count: 3)
                #expect(try await post(stuck, at: point, downstream: downstream) == 0)
                try await Task.sleep(for: .milliseconds(2200))
                #expect(try await post(pan([]), at: point, downstream: downstream) == 10)
            }
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func aDisabledGestureTapIsReEnabledByOneTick() async throws {
        let tap = GestureTap()
        defer { tap.stop() }
        #expect(tap.start())
        let port = try #require(tap.port)
        #expect(tap.thread.map { !$0.isMainThread } == true)
        // As InputTapIntegrationTests: the callback may already have re-enabled it; either way one tick leaves it enabled.
        CGEvent.tapEnable(tap: port, enable: false)
        tap.watchdogTick()
        #expect(CGEvent.tapIsEnabled(tap: port), "the watchdog left the gesture tap disabled")
        #expect(tap.isRunning)
        tap.stop()
        #expect(!tap.isRunning)
    }

    @Test(.timeLimit(.minutes(1)))
    func wakeRepublishesState() async throws {
        let arrange = ArrangeController(system: AXWindowSystem(), zoomEnabled: true)
        defer {
            arrange.stopTap()
            withExtendedLifetime(arrange) {}
        }
        #expect(arrange.startTap())
        #expect(arrange.isGestureTapRunning)
        let before = arrange.gestures.republished
        NSWorkspace.shared.notificationCenter.post(name: NSWorkspace.screensDidWakeNotification, object: nil)
        let grew = await waitUntil(timeout: .seconds(2)) { arrange.gestures.republished > before }
        #expect(grew, "screensDidWake did not re-publish the gesture state")
        arrange.stopTap()
        #expect(!arrange.isGestureTapRunning, "stopTap left the gesture tap running")
    }
}

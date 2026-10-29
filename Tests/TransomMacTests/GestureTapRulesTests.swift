import CoreGraphics
import Testing
@testable import TransomMac
import TransomEngine
import TransomModel
import TransomPrivate

private let point = CGPoint(x: 400, y: 300)
private let option = CGEventFlags.maskAlternate
private let finder: Int32 = 300
private let armed = GestureTapState(armed: true, deskDisplays: [CGRect(x: 0, y: 0, width: 1440, height: 900)], finderPID: finder)
private let scroll = CGEventType.scrollWheel.rawValue
private let gesture = GestureEventFields.gestureType

/// The gesture tap's consume rules (D-04, D-05, D-06, E-04, E-05; RESEARCH Pattern 2): decided once per sequence at its
/// first event, held through momentum end, never started mid-sequence, and always released by a new start or a timeout.
@Suite struct GestureTapRulesTests {
    /// Counts surface reads; answers `answer`.
    final class Surface {
        var calls = 0
        let answer: PointerSurface
        init(_ answer: PointerSurface = .window) { self.answer = answer }
    }

    private func decide(
        _ latch: inout GestureTapRules.Latch, type: UInt32 = scroll, phase: Int64 = 0, momentum: Int64 = 0, continuous: Bool = true,
        hid: Int64 = 0, gesturePhase: Int64 = 0, zoom: Double = 0, pid: Int32 = 512, sender: UInt64 = 0, flags: CGEventFlags = [],
        at location: CGPoint = point, t: Double = 0, state: GestureTapState = armed, surface: Surface = Surface()
    ) -> GestureTapRules.Decision {
        let input = GestureTapRules.Input(
            type: type, scrollPhase: phase, momentumPhase: momentum, isContinuous: continuous, dx: 1, dy: -2, hidType: hid,
            gesturePhase: gesturePhase, zoom: zoom, targetPID: pid, senderID: sender, flags: flags, location: location, timestamp: t)
        return GestureTapRules.decide(input, state: state, latch: &latch) { _ in
            surface.calls += 1
            return surface.answer
        }
    }

    private func pinch(
        _ latch: inout GestureTapRules.Latch, _ gesturePhase: Int64, hid: Int64 = GestureEventFields.hidZoom, zoom: Double = 0.05,
        flags: CGEventFlags = option, t: Double = 0, pid: Int32 = 512, surface: Surface = Surface()
    ) -> GestureTapRules.Decision {
        decide(&latch, type: gesture, hid: hid, gesturePhase: gesturePhase, zoom: zoom, pid: pid, flags: flags, t: t, surface: surface)
    }

    private func isConsume(_ decision: GestureTapRules.Decision) -> Bool {
        if case .consume = decision { return true }
        return false
    }

    @Test func theMaskHasScrollAndGestureButNeverDockControl() {
        #expect(GestureTapRules.mask & (1 << 22) != 0)
        #expect(GestureTapRules.mask & (1 << 29) != 0)
        #expect(GestureTapRules.mask & (1 << 30) == 0)
    }

    @Test func anOptionPinchIsConsumedWithSamplesAndItsEnvelopesPass() {
        var latch = GestureTapRules.Latch.none
        #expect(pinch(&latch, 0, hid: GestureEventFields.hidGestureStarted) == .pass)
        guard case .consume(let first?) = pinch(&latch, 1) else { Issue.record("began not consumed"); return }
        #expect(first.kind == .pinch && first.phase == 1 && first.reason == .optionHeld)
        for _ in 0..<5 {
            guard case .consume(let sample?) = pinch(&latch, 2) else { Issue.record("changed not consumed"); return }
            #expect(sample.reason == nil && sample.magnification == 0.05)
        }
        #expect(pinch(&latch, 0, hid: GestureEventFields.hidGestureStarted) == .pass)
        #expect(pinch(&latch, 0, hid: GestureEventFields.hidGestureEnded) == .pass)
        #expect(isConsume(pinch(&latch, 4)))
        #expect(latch.pinch == nil)
        #expect(pinch(&latch, 0, hid: GestureEventFields.hidGestureEnded) == .pass)
    }

    @Test func anOptionPanIsConsumedThroughMomentumAndThePlainScrollAfterPasses() {
        var latch = GestureTapRules.Latch.none
        var t = 0.0
        for phase: Int64 in [1, 2, 4] {
            #expect(isConsume(decide(&latch, phase: phase, flags: option, t: t)))
            t += 0.01
        }
        for momentum: Int64 in [1, 2, 2, 3] {
            #expect(isConsume(decide(&latch, momentum: momentum, t: t)))
            t += 0.01
        }
        #expect(latch.pan == nil)
        #expect(decide(&latch, phase: 1, t: t) == .pass)
        #expect(decide(&latch, phase: 2, t: t + 0.01) == .pass)
    }

    @Test func optionPressedAfterBeganPassesTheWholeSequence() {
        var latch = GestureTapRules.Latch.none
        #expect(decide(&latch, phase: 1) == .pass)
        #expect(decide(&latch, phase: 2, flags: option) == .pass)
        #expect(decide(&latch, phase: 4, flags: option) == .pass)
        #expect(latch.pan?.passReason == .windowUnderPointer)
    }

    @Test func optionReleasedMidPinchStillConsumesTheWholeSequence() {
        var latch = GestureTapRules.Latch.none
        #expect(isConsume(pinch(&latch, 1)))
        #expect(isConsume(pinch(&latch, 2, flags: [])))
        #expect(isConsume(pinch(&latch, 4, flags: [])))
    }

    @Test func controlOrCommandWithOptionPassesButShiftConsumes() {
        var latch = GestureTapRules.Latch.none
        #expect(pinch(&latch, 1, flags: [.maskAlternate, .maskControl]) == .pass)
        #expect(latch.pinch?.passReason == .chord)
        #expect(decide(&latch, phase: 1, flags: [.maskAlternate, .maskCommand]) == .pass)
        #expect(latch.pan?.passReason == .chord)
        #expect(isConsume(pinch(&latch, 1, flags: [.maskAlternate, .maskShift])))
    }

    @Test func discreteAndUnphasedScrollsAlwaysPassAndLeaveTheLatchAlone() {
        var latch = GestureTapRules.Latch.none
        #expect(decide(&latch, flags: option) == .pass)
        #expect(decide(&latch, phase: 1, continuous: false, flags: option) == .pass)
        #expect(latch == .none)
        #expect(isConsume(decide(&latch, phase: 1, flags: option)))
        let held = latch
        #expect(decide(&latch, flags: option) == .pass)
        #expect(latch == held)
    }

    @Test func onlyKnownTrackpadSendersAreTaken() {
        var filtered = armed
        filtered.trackpadSenders = [0x1]
        var latch = GestureTapRules.Latch.none
        #expect(decide(&latch, phase: 1, sender: 0x2, flags: option, state: filtered) == .pass)
        #expect(latch.pan?.passReason == .notTrackpad)
        #expect(isConsume(decide(&latch, phase: 1, sender: 0x1, flags: option, state: filtered)))
        #expect(isConsume(decide(&latch, phase: 1, sender: 0x2, flags: option, state: armed)))
    }

    @Test func aTrustedNonFinderTargetPassesWithNoSurfaceRead() {
        var trusting = armed
        trusting.trustsTargetPID = true
        var latch = GestureTapRules.Latch.none
        let surface = Surface(.wallpaper)
        #expect(decide(&latch, phase: 1, pid: 512, state: trusting, surface: surface) == .pass)
        #expect(decide(&latch, phase: 2, pid: 512, state: trusting, surface: surface) == .pass)
        #expect(surface.calls == 0)
        #expect(latch.pan?.passReason == .shortCircuit)
    }

    /// The VM showed synthetic events carrying the frontmost app's pid over bare wallpaper, so by default the pid
    /// decides nothing and the surface is read.
    @Test func anUntrustedTargetPIDStillReadsTheSurface() {
        var latch = GestureTapRules.Latch.none
        let surface = Surface(.wallpaper)
        #expect(isConsume(decide(&latch, phase: 1, pid: 512, surface: surface)))
        #expect(surface.calls == 1)
        #expect(latch.pan?.reason == .wallpaper)
    }

    @Test(arguments: [Int32(0), finder])
    func withoutOptionTheSurfaceDecidesOncePerSequence(pid: Int32) {
        for (answer, consumed, reason) in [
            (PointerSurface.wallpaper, true, GestureTapRules.PassReason?.none), (.window, false, .windowUnderPointer),
            (.overlay, false, .overlayUnderPointer),
        ] {
            var latch = GestureTapRules.Latch.none
            let surface = Surface(answer)
            #expect(isConsume(decide(&latch, phase: 1, pid: pid, surface: surface)) == consumed)
            #expect(isConsume(decide(&latch, phase: 2, pid: pid, surface: surface)) == consumed)
            #expect(isConsume(decide(&latch, phase: 4, pid: pid, surface: surface)) == consumed)
            #expect(surface.calls == 1)
            #expect(latch.pan?.passReason == reason)
            if consumed { #expect(latch.pan?.reason == .wallpaper) }
        }
    }

    @Test func notArmedOffEveryDeskOrOnAFullScreenDisplayPasses() {
        var latch = GestureTapRules.Latch.none
        var paused = armed
        paused.armed = false
        paused.disarmReason = .zoomPaused
        #expect(decide(&latch, phase: 1, flags: option, state: paused) == .pass)
        #expect(latch.pan?.passReason == .disarmed(.zoomPaused))
        #expect(decide(&latch, phase: 1, flags: option, at: CGPoint(x: 2000, y: 300)) == .pass)
        #expect(latch.pan?.passReason == .notDeskDisplay)
        var fullScreen = armed
        fullScreen.fullScreenDisplays = [CGRect(x: 0, y: 0, width: 1440, height: 900)]
        #expect(decide(&latch, phase: 1, flags: option, state: fullScreen) == .pass)
        #expect(latch.pan?.passReason == .fullScreen)
    }

    @Test func aStuckLatchIsReleasedByTimeoutOrANewStart() {
        var latch = GestureTapRules.Latch.none
        #expect(isConsume(decide(&latch, phase: 1, flags: option, t: 0)))
        #expect(isConsume(decide(&latch, phase: 2, flags: option, t: 0.01)))
        // No end, then 2.1 s of nothing: a fresh plain scroll passes, and so does a stray changed.
        #expect(decide(&latch, phase: 1, t: 2.11) == .pass)
        latch = .none
        #expect(isConsume(decide(&latch, phase: 1, flags: option, t: 0)))
        #expect(decide(&latch, phase: 2, t: 2.11) == .pass)
        #expect(latch.pan?.passReason == .midSequence)
    }

    @Test func quietAfterFingersUpEndsTheLatchButFingersDownQuietKeepsIt() {
        var latch = GestureTapRules.Latch.none
        #expect(isConsume(decide(&latch, phase: 1, flags: option, t: 0)))
        // Resting fingers mid-pan for 1 s keeps consuming (UAT item 10).
        #expect(isConsume(decide(&latch, phase: 2, t: 1.0)))
        #expect(isConsume(decide(&latch, phase: 4, t: 1.01)))
        #expect(latch.pan?.fingersUp == true)
        // 0.31 s of quiet after lift: the late momentum is the app's (as a stray, never taken).
        #expect(decide(&latch, momentum: 1, t: 1.33) == .pass)
        #expect(latch.pan?.passReason == .midSequence)
    }

    @Test func aStrayChangedPassesAndKeepsPassing() {
        var latch = GestureTapRules.Latch.none
        #expect(decide(&latch, phase: 2, flags: option) == .pass)
        #expect(latch.pan?.passReason == .midSequence)
        #expect(decide(&latch, phase: 2, flags: option) == .pass)
        #expect(pinch(&latch, 2) == .pass)
        #expect(latch.pinch?.passReason == .midSequence)
        #expect(pinch(&latch, 4) == .pass)
    }

    @Test func rotateOnlyPassesButRotateInsideAnOptionPinchIsConsumed() {
        var latch = GestureTapRules.Latch.none
        for phase: Int64 in [1, 2, 4] { #expect(pinch(&latch, phase, hid: GestureEventFields.hidRotate) == .pass) }
        #expect(latch == .none)
        #expect(isConsume(pinch(&latch, 1)))
        #expect(pinch(&latch, 2, hid: GestureEventFields.hidRotate) == .consume(nil))
        #expect(pinch(&latch, 2, hid: 0) == .consume(nil))
        #expect(isConsume(pinch(&latch, 2)))
    }

    @Test func magnificationIsClampedAndNonFiniteReadsZero() {
        var latch = GestureTapRules.Latch.none
        guard case .consume(let nan?) = pinch(&latch, 1, zoom: .nan) else { Issue.record("not consumed"); return }
        #expect(nan.magnification == 0)
        guard case .consume(let big?) = pinch(&latch, 2, zoom: 3.0) else { Issue.record("not consumed"); return }
        #expect(big.magnification == 1.0)
        guard case .consume(let small?) = pinch(&latch, 2, zoom: -.infinity) else { Issue.record("not consumed"); return }
        #expect(small.magnification == 0)
    }

    @Test func aScrollCancelledByAStartingPinchLeavesThePinchLatchAlone() {
        var latch = GestureTapRules.Latch.none
        #expect(isConsume(decide(&latch, phase: 128, flags: option)))
        #expect(isConsume(pinch(&latch, 1)))
        #expect(isConsume(decide(&latch, phase: 8, flags: option)))
        #expect(latch.pan == nil)
        #expect(isConsume(pinch(&latch, 2)))
    }

    @Test func surfaceLooksThroughFullDisplayOverlaysAndSkipsItsOwnWindows() {
        let display = CGRect(x: 0, y: 0, width: 1440, height: 900)
        func entry(_ pid: Int32, _ layer: Int, _ rect: Rect, alpha: Double = 1) -> CGWindowEntry {
            CGWindowEntry(windowID: UInt32(pid), pid: pid, bounds: rect, layer: layer, onScreen: true, alpha: alpha)
        }
        let full = Rect(x: 0, y: 0, width: 1440, height: 900)
        let small = Rect(x: 300, y: 200, width: 300, height: 300)
        let own: Int32 = 99
        #expect(GestureTapRules.surface(at: point, in: [], excludingPID: own, display: display) == .wallpaper)
        #expect(GestureTapRules.surface(at: point, in: [entry(own, 0, small)], excludingPID: own, display: display) == .wallpaper)
        #expect(GestureTapRules.surface(at: point, in: [entry(5, 0, small, alpha: 0)], excludingPID: own, display: display) == .wallpaper)
        #expect(GestureTapRules.surface(at: point, in: [entry(7, 20, full), entry(5, 0, small)], excludingPID: own, display: display) == .window)
        #expect(GestureTapRules.surface(at: point, in: [entry(7, 20, full)], excludingPID: own, display: display) == .wallpaper)
        #expect(GestureTapRules.surface(at: point, in: [entry(8, 25, small), entry(5, 0, small)], excludingPID: own, display: display) == .overlay)
    }
}

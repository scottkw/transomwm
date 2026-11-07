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

    /// WR-02: mayBegin (128) then began (1), as real pans start (recorded-pan-maybegin-start), is one sequence: decided
    /// once, one start time, the reason on the first sample only. A began after a finished mayBegin is a new start.
    @Test func mayBeginThenBeganIsOneSequence() {
        var latch = GestureTapRules.Latch.none
        let surface = Surface(.wallpaper)
        guard case .consume(let first?) = decide(&latch, phase: 128, t: 0, surface: surface) else { Issue.record("mayBegin not taken"); return }
        #expect(first.reason == .wallpaper)
        guard case .consume(let began?) = decide(&latch, phase: 1, t: 0.0002, surface: surface) else { Issue.record("began not taken"); return }
        #expect(began.reason == nil && began.phase == 1)
        #expect(isConsume(decide(&latch, phase: 2, t: 0.01, surface: surface)))
        #expect(latch.pan?.started == 0)
        #expect(isConsume(decide(&latch, phase: 4, t: 0.02, surface: surface)))
        #expect(surface.calls == 1)
        // A began after the mayBegin was continued, or after it was cancelled, decides afresh.
        #expect(decide(&latch, phase: 1, t: 0.03, surface: Surface(.window)) == .pass)
        #expect(latch.pan?.started == 0.03)
        latch = .none
        #expect(isConsume(decide(&latch, phase: 128, t: 0, surface: surface)))
        #expect(isConsume(decide(&latch, phase: 8, t: 0.01, surface: surface)))
        #expect(decide(&latch, phase: 1, t: 0.02, surface: Surface(.window)) == .pass)
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
        // WR-06, E-04 fail closed: no trackpad found (a desktop Mac with a Magic Mouse) means a sender is never taken.
        #expect(decide(&latch, phase: 1, sender: 0x2, flags: option, state: armed) == .pass)
        #expect(latch.pan?.passReason == .notTrackpad)
        #expect(isConsume(pinch(&latch, 1)), "synthetic sender 0 is still judged")
        var unfiltered = armed
        unfiltered.filtersBySender = false
        #expect(isConsume(decide(&latch, phase: 1, sender: 0x2, flags: option, state: unfiltered)), "the spike's listen mode")
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

    /// WR-01: a tracked window's frame under the pointer passes a no-⌥ gesture with no CG read in the callback; outside
    /// every frame the surface is read as before, and ⌥ never looks at the frames.
    @Test func aTrackedWindowUnderThePointerPassesWithNoSurfaceRead() {
        var tiled = armed
        tiled.windowRects = [CGRect(x: 300, y: 200, width: 300, height: 300)]
        let surface = Surface(.wallpaper)
        var latch = GestureTapRules.Latch.none
        #expect(decide(&latch, phase: 1, state: tiled, surface: surface) == .pass)
        #expect(decide(&latch, phase: 2, state: tiled, surface: surface) == .pass)
        #expect(latch.pan?.passReason == .windowUnderPointer)
        #expect(surface.calls == 0)
        latch = .none
        #expect(isConsume(decide(&latch, phase: 1, at: CGPoint(x: 100, y: 100), state: tiled, surface: surface)))
        #expect(surface.calls == 1)
        latch = .none
        #expect(isConsume(decide(&latch, phase: 1, flags: option, state: tiled, surface: surface)))
        #expect(surface.calls == 1)
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
        // A plain scroll's stray changed after a passing latch expired is the app's.
        latch = .none
        #expect(decide(&latch, phase: 1, t: 0) == .pass)
        #expect(decide(&latch, phase: 2, t: 2.11) == .pass)
        #expect(latch.pan?.passReason == .midSequence)
    }

    /// WR-03 (UAT item 10): fingers resting over 2 s mid-gesture, then moving on. The taken latch becomes an orphan that
    /// swallows the rest of the gesture with no samples (main resolved the stage at 2.05 s), momentum included, until
    /// its end; the next start decides afresh.
    @Test func aTakenGestureResumedAfterALongRestNeverLeaksItsTail() {
        var latch = GestureTapRules.Latch.none
        #expect(isConsume(decide(&latch, phase: 1, flags: option, t: 0)))
        #expect(isConsume(decide(&latch, phase: 2, flags: option, t: 0.01)))
        #expect(decide(&latch, phase: 2, t: 2.5) == .consume(nil))
        #expect(latch.pan?.orphan == true)
        #expect(decide(&latch, phase: 2, t: 5.0) == .consume(nil), "a second long rest still swallows")
        #expect(decide(&latch, phase: 4, t: 5.01) == .consume(nil))
        for (i, momentum) in [Int64(1), 2, 3].enumerated() { #expect(decide(&latch, momentum: momentum, t: 5.6 + Double(i) * 0.01) == .consume(nil)) }
        #expect(latch.pan == nil)
        #expect(decide(&latch, phase: 1, t: 6) == .pass)

        latch = .none
        #expect(isConsume(pinch(&latch, 1, t: 0)))
        #expect(pinch(&latch, 2, flags: [], t: 2.5) == .consume(nil))
        #expect(latch.pinch?.orphan == true)
        #expect(pinch(&latch, 2, hid: GestureEventFields.hidRotate, flags: [], t: 2.6) == .consume(nil), "C1 inside the orphan")
        #expect(pinch(&latch, 0, hid: GestureEventFields.hidGestureEnded, flags: [], t: 2.7) == .pass)
        #expect(pinch(&latch, 4, flags: [], t: 2.8) == .consume(nil))
        #expect(latch.pinch == nil)
        // A new start replaces an orphan.
        #expect(isConsume(decide(&latch, phase: 1, flags: option, t: 10)))
        #expect(decide(&latch, phase: 2, t: 12.5) == .consume(nil))
        guard case .consume(let fresh?) = decide(&latch, phase: 1, flags: option, t: 12.6) else { Issue.record("new start not taken"); return }
        #expect(fresh.reason == .optionHeld)
        #expect(latch.pan?.orphan == false)
    }

    /// WR-05: what the tap keeps when macOS re-enables it mid-gesture. A taken pan or pinch keeps swallowing its tail
    /// with no samples; a passing one is dropped, so its tail stays the app's.
    @Test func aReEnabledTapOrphansTakenSequencesAndDropsPassingOnes() {
        var latch = GestureTapRules.Latch.none
        #expect(isConsume(decide(&latch, phase: 1, flags: option, t: 0)))
        #expect(pinch(&latch, 1, flags: [], t: 0) == .pass)
        latch = latch.orphaned()
        #expect(latch.pan?.orphan == true && latch.pinch == nil)
        #expect(decide(&latch, phase: 2, t: 0.1) == .consume(nil))
        #expect(decide(&latch, phase: 4, t: 0.2) == .consume(nil))
        #expect(pinch(&latch, 2, flags: [], t: 0.1) == .pass)

        var pinching = GestureTapRules.Latch.none
        #expect(isConsume(pinch(&pinching, 1, t: 0)))
        pinching = pinching.orphaned()
        #expect(pinch(&pinching, 2, flags: [], t: 0.1) == .consume(nil))
        #expect(pinch(&pinching, 4, flags: [], t: 0.2) == .consume(nil))
        #expect(pinching == .none)
    }

    @Test func quietAfterFingersUpOrphansTheLatchButFingersDownQuietKeepsIt() {
        var latch = GestureTapRules.Latch.none
        #expect(isConsume(decide(&latch, phase: 1, flags: option, t: 0)))
        // Resting fingers mid-pan for 1 s keeps consuming (UAT item 10).
        #expect(isConsume(decide(&latch, phase: 2, t: 1.0)))
        #expect(isConsume(decide(&latch, phase: 4, t: 1.01)))
        #expect(latch.pan?.fingersUp == true)
        // 0.31 s of quiet after lift: late momentum of a taken pan is still swallowed, with no sample (WR-03).
        #expect(decide(&latch, momentum: 1, t: 1.33) == .consume(nil))
        #expect(latch.pan?.orphan == true)
        #expect(decide(&latch, phase: 1, t: 1.4) == .pass)
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

    /// C1 (05-SPIKE T2): every type-29 sub-type inside a taken pinch is taken, sub-type 4 above all (81 leaked on the
    /// host); the envelopes still pass, and nothing is taken once the zoom has ended or in a pinch that passes.
    @Test func aTakenPinchTakesEverySubTypeButTheEnvelopes() {
        var latch = GestureTapRules.Latch.none
        #expect(isConsume(pinch(&latch, 1)))
        for hid: Int64 in [4, 0, 6, 32, 5, 7] { #expect(pinch(&latch, 2, hid: hid) == .consume(nil), "sub-type \(hid) passed") }
        #expect(pinch(&latch, 0, hid: GestureEventFields.hidGestureStarted) == .pass)
        #expect(pinch(&latch, 0, hid: GestureEventFields.hidGestureEnded) == .pass)
        #expect(isConsume(pinch(&latch, 4)))
        #expect(pinch(&latch, 2, hid: 4) == .pass)
        #expect(pinch(&latch, 0, hid: 0) == .pass)

        var plain = GestureTapRules.Latch.none
        #expect(pinch(&plain, 1, flags: []) == .pass)
        #expect(pinch(&plain, 2, hid: 4, flags: []) == .pass)
    }

    /// WR-04: a taken pinch whose zoom end was lost is not kept alive by the type-29 companions of later scrolls: 2 s
    /// after its last zoom event they pass again.
    @Test func scrollCompanionsDoNotKeepALostPinchLatchAlive() {
        var latch = GestureTapRules.Latch.none
        #expect(isConsume(pinch(&latch, 1, t: 0)))
        #expect(isConsume(pinch(&latch, 2, t: 0.1)))
        var t = 0.5
        while t < 2.1 {
            #expect(pinch(&latch, 2, hid: 0, flags: [], t: t) == .consume(nil), "companion at \(t) inside the latch")
            t += 0.5
        }
        for hid: Int64 in [0, 6, 32] { #expect(pinch(&latch, 2, hid: hid, flags: [], t: 2.2) == .pass, "sub-type \(hid) still taken") }
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

    // MARK: - Settings ▸ Trackpad switches (09-06)

    private func switches(option: Bool, wallpaper: Bool) -> GestureTapState {
        var state = armed
        state.takesOptionGestures = option
        state.takesWallpaperGestures = wallpaper
        return state
    }

    private func pinchStart(_ latch: inout GestureTapRules.Latch, flags: CGEventFlags, state: GestureTapState, surface: Surface) -> GestureTapRules.Decision {
        decide(&latch, type: gesture, hid: GestureEventFields.hidZoom, gesturePhase: 1, zoom: 0.05, flags: flags, state: state, surface: surface)
    }

    @Test func anOptionPinchOverAWindowPassesWhenOptionGesturesAreOff() {
        var latch = GestureTapRules.Latch.none
        #expect(pinchStart(&latch, flags: option, state: switches(option: false, wallpaper: true), surface: Surface(.window)) == .pass)
        #expect(latch.pinch?.passReason == .windowUnderPointer)
    }

    @Test func anOptionPinchOverTheWallpaperIsStillTakenWhenOnlyWallpaperIsOn() {
        var latch = GestureTapRules.Latch.none
        guard case .consume(let sample?) = pinchStart(&latch, flags: option, state: switches(option: false, wallpaper: true), surface: Surface(.wallpaper))
        else { Issue.record("⌥ wallpaper pinch not taken"); return }
        #expect(sample.reason == .wallpaper)
    }

    @Test func aBareWallpaperPinchPassesWhenWallpaperGesturesAreOff() {
        var latch = GestureTapRules.Latch.none
        #expect(pinchStart(&latch, flags: [], state: switches(option: true, wallpaper: false), surface: Surface(.wallpaper)) == .pass)
        #expect(latch.pinch?.passReason == .turnedOff)
        latch = .none
        #expect(decide(&latch, phase: 1, state: switches(option: true, wallpaper: false), surface: Surface(.wallpaper)) == .pass)
        #expect(latch.pan?.passReason == .turnedOff)
        // ⌥ still takes it while its own switch is on.
        latch = .none
        #expect(isConsume(pinchStart(&latch, flags: option, state: switches(option: true, wallpaper: false), surface: Surface(.window))))
    }

    @Test func bothOnIsTodaysBehaviour() {
        #expect(GestureTapState().takesOptionGestures && GestureTapState().takesWallpaperGestures)
        var latch = GestureTapRules.Latch.none
        guard case .consume(let held?) = pinchStart(&latch, flags: option, state: armed, surface: Surface(.window)) else {
            Issue.record("⌥ pinch not taken"); return
        }
        #expect(held.reason == .optionHeld)
        latch = .none
        guard case .consume(let bare?) = pinchStart(&latch, flags: [], state: armed, surface: Surface(.wallpaper)) else {
            Issue.record("wallpaper pinch not taken"); return
        }
        #expect(bare.reason == .wallpaper)
    }
}

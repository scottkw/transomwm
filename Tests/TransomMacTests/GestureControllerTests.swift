import CoreGraphics
@testable import TransomMac
import Testing

/// GestureController's main-side gates, pure functions only: no tap, device or panel is created.
struct GestureControllerTests {
    private func sample(_ seq: UInt64) -> GestureTapEvent {
        .sample(
            GestureSample(
                kind: .pan, phase: 2, momentum: 0, magnification: 0, dx: 1, dy: 0, location: .zero, timestamp: 0, flags: [], senderID: 0,
                reason: nil),
            seq: seq)
    }

    private func ended(_ seq: UInt64) -> GestureTapEvent {
        .ended(GestureTapSummary(seq: seq, kind: .pan, taken: true, optionHeld: true, startedAt: 0, endedAt: 0))
    }

    /// WR-10: a tap sequence shut out by a multitouch pinch stays out after the pinch ends, until its own end.
    @Test func aSequenceShutOutByAMultitouchPinchStaysOutUntilItsEnd() {
        var suppressed: Set<UInt64> = []
        #expect(!GestureController.dropsSample(7, ownedByMultitouch: false, suppressed: &suppressed))
        #expect(GestureController.dropsSample(7, ownedByMultitouch: true, suppressed: &suppressed))
        #expect(GestureController.dropsSample(7, ownedByMultitouch: false, suppressed: &suppressed), "a late sample after the pinch ended")
        #expect(!GestureController.dropsSample(8, ownedByMultitouch: false, suppressed: &suppressed), "a new sequence")
        suppressed.remove(7)  // its .ended
        #expect(!GestureController.dropsSample(7, ownedByMultitouch: false, suppressed: &suppressed))
    }

    /// WR-09: gestures are disarmed while Turn Off Zoom moves home, as while paused.
    @Test func turningZoomOffDisarmsGestures() {
        #expect(GestureController.disarmReason(ready: true, paused: false, turningOff: true, busy: false) == .zoomPaused)
        #expect(GestureController.disarmReason(ready: true, paused: false, turningOff: false, busy: false) == nil)
        #expect(GestureController.disarmReason(ready: true, paused: true, turningOff: false, busy: true) == .zoomPaused)
        #expect(GestureController.disarmReason(ready: true, paused: false, turningOff: false, busy: true) == .rectZoomOrDrag)
        #expect(GestureController.disarmReason(ready: false, paused: true, turningOff: true, busy: true) == .notReady)
    }

    /// 06 Surface 1 While open: gestures are not armed while the overview is open, logged as "overview open".
    @Test func anOpenOverviewDisarmsGestures() {
        #expect(GestureController.disarmReason(ready: true, paused: false, turningOff: false, busy: false, overviewOpen: true) == .overviewOpen)
        #expect(GestureController.disarmReason(ready: true, paused: false, turningOff: false, busy: true, overviewOpen: true) == .overviewOpen)
        #expect(GestureController.disarmReason(ready: false, paused: false, turningOff: false, busy: false, overviewOpen: true) == .notReady)
        #expect(GestureController.optionPassText(.disarmed(.overviewOpen)) == "overview open")
    }

    /// WR-07: after `stop` nothing is handled; after a restart the stopped tap's buffered events are dropped.
    @Test func onlyTheRunningTapsEventsAreHandled() {
        for event in [sample(5), ended(5)] {
            #expect(GestureController.isCurrent(event, active: true, floor: 0))
            #expect(!GestureController.isCurrent(event, active: false, floor: 0), "handled after stop")
            #expect(!GestureController.isCurrent(event, active: true, floor: 5), "an old tap's event after a restart")
            #expect(GestureController.isCurrent(event, active: true, floor: 4))
        }
    }
}

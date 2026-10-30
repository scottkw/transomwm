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

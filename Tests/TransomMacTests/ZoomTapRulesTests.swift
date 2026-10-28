import CoreGraphics
@testable import TransomMac
import Testing

private let point = CGPoint(x: 400, y: 300)
private let commandShift: CGEventFlags = [.maskCommand, .maskShift]
private let armed = ZoomTapState(armed: true, deskDisplays: [CGRect(x: 0, y: 0, width: 1440, height: 900)])

/// The tap's zoom rules (ZOOM-03, ZOOM-12, D-C): a press is taken only when ⌘⇧ (and neither ⌃ nor ⌥) is held at
/// mouse-down while armed, and then only that one press-release sequence.
@Suite struct ZoomTapRulesTests {
    private func decide(
        _ type: CGEventType, at location: CGPoint = point, flags: CGEventFlags = [], clickState: Int64 = 1, window: UInt32 = 0,
        userData: Int64 = 0, state: ZoomTapState = armed, _ swallow: inout ZoomTapRules.Swallow
    ) -> ZoomTapRules.Decision {
        ZoomTapRules.decide(
            type: type, location: location, flags: flags, clickState: clickState, windowID: window, userData: userData, state: state,
            swallow: &swallow)
    }

    @Test func aCommandShiftPressIsTakenWithItsDragsAndRelease() {
        var swallow = ZoomTapRules.Swallow.none
        #expect(decide(.leftMouseDown, flags: commandShift, &swallow) == .consume(.band))
        #expect(decide(.leftMouseDragged, at: CGPoint(x: 500, y: 400), flags: commandShift, &swallow) == .consume(.band))
        #expect(decide(.leftMouseUp, at: CGPoint(x: 500, y: 400), flags: commandShift, &swallow) == .consume(.band))
        #expect(swallow == .none)
        // The next plain press is the app's again.
        #expect(decide(.leftMouseDown, &swallow) == .pass)
        #expect(decide(.leftMouseUp, &swallow) == .pass)
    }

    @Test func controlOrOptionWithCommandShiftPasses() {
        var swallow = ZoomTapRules.Swallow.none
        #expect(decide(.leftMouseDown, flags: [.maskCommand, .maskShift, .maskControl], &swallow) == .pass)
        #expect(decide(.leftMouseDown, flags: [.maskCommand, .maskShift, .maskAlternate], &swallow) == .pass)
        #expect(swallow == .none)
    }

    @Test func commandAloneOrShiftAlonePasses() {
        var swallow = ZoomTapRules.Swallow.none
        #expect(decide(.leftMouseDown, flags: .maskCommand, &swallow) == .pass)
        #expect(decide(.leftMouseDown, flags: .maskShift, &swallow) == .pass)
        #expect(decide(.leftMouseDragged, flags: .maskShift, &swallow) == .pass)
        #expect(decide(.leftMouseUp, flags: .maskShift, &swallow) == .pass)
    }

    @Test func notArmedOrOffEveryDeskPasses() {
        var swallow = ZoomTapRules.Swallow.none
        #expect(decide(.leftMouseDown, flags: commandShift, state: ZoomTapState(), &swallow) == .pass)
        // A display with no desk (a fullscreen Space) is not armed.
        #expect(decide(.leftMouseDown, at: CGPoint(x: 2000, y: 300), flags: commandShift, &swallow) == .pass)
        #expect(swallow == .none)
    }

    @Test func releasingCommandShiftMidDragKeepsConsumingUntilTheUp() {
        var swallow = ZoomTapRules.Swallow.none
        #expect(decide(.leftMouseDown, flags: commandShift, &swallow) == .consume(.band))
        #expect(decide(.flagsChanged, flags: [], &swallow) == .pass)
        #expect(decide(.leftMouseDragged, flags: [], &swallow) == .consume(.band))
        #expect(decide(.leftMouseUp, flags: [], &swallow) == .consume(.band))
        #expect(decide(.leftMouseDown, flags: [], &swallow) == .pass)
    }

    @Test func aRepostedEventPassesEvenWhenArmedWithCommandShift() {
        var swallow = ZoomTapRules.Swallow.none
        #expect(decide(.leftMouseDown, flags: commandShift, userData: ZoomTapRules.repostTag, &swallow) == .pass)
        #expect(decide(.leftMouseUp, flags: commandShift, userData: ZoomTapRules.repostTag, &swallow) == .pass)
        #expect(swallow == .none)
    }

    @Test func aPressThatIsNotTakenEndsAnEarlierSwallow() {
        // A lost mouse-up (the tap was disabled for a moment) must not swallow the next click.
        var swallow = ZoomTapRules.Swallow.band
        #expect(decide(.leftMouseDown, &swallow) == .pass)
        #expect(decide(.leftMouseDragged, &swallow) == .pass)
        #expect(decide(.leftMouseUp, &swallow) == .pass)
    }
}

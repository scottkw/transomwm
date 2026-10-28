import CoreGraphics
@testable import TransomMac
import Testing

private let button = CGRect(x: 112, y: 104, width: 14, height: 16)
private let rects: [UInt32: CGRect] = [7: button]
private let inside = CGPoint(x: 118, y: 110)

/// The tap's swallow rule (TILE-06, TILE-19, T-03-34): only a press inside a published green button, never with ⌥, and
/// then the whole click, so no app sees half of it.
@Suite struct GreenButtonHitTests {
    private func swallow(
        _ type: CGEventType, at point: CGPoint = inside, flags: CGEventFlags = [], window: UInt32 = 7, _ swallowing: inout Bool
    ) -> Bool {
        GreenButton.shouldSwallow(type: type, location: point, flags: flags, windowID: window, rects: rects, swallowing: &swallowing)
    }

    @Test func aPressInsideTheButtonIsSwallowedWithItsDragsAndRelease() {
        var swallowing = false
        #expect(swallow(.leftMouseDown, &swallowing))
        #expect(swallow(.leftMouseDragged, at: CGPoint(x: 300, y: 300), &swallowing))
        #expect(swallow(.leftMouseUp, at: CGPoint(x: 300, y: 300), &swallowing))
        #expect(!swallowing)
        // The next click elsewhere is the app's again.
        #expect(!swallow(.leftMouseDragged, &swallowing))
        #expect(!swallow(.leftMouseUp, &swallowing))
    }

    @Test func optionPassesThroughSoMacOSZooms() {
        var swallowing = false
        #expect(!swallow(.leftMouseDown, flags: .maskAlternate, &swallowing))
        #expect(!swallow(.leftMouseUp, flags: .maskAlternate, &swallowing))
        // Other modifiers do not change the rule.
        #expect(swallow(.leftMouseDown, flags: .maskShift, &swallowing))
    }

    @Test func outsideTheButtonOrAnUnknownWindowPassesThrough() {
        var swallowing = false
        #expect(!swallow(.leftMouseDown, at: CGPoint(x: 140, y: 110), &swallowing))
        #expect(!swallow(.leftMouseDown, window: 8, &swallowing))
        #expect(!swallow(.leftMouseDown, window: 0, &swallowing))
        #expect(!swallowing)
    }

    @Test func aReleaseWithNoSwallowedPressPassesThrough() {
        var swallowing = false
        #expect(!swallow(.leftMouseUp, &swallowing))
        #expect(!swallow(.leftMouseDragged, &swallowing))
        #expect(!swallow(.flagsChanged, &swallowing))
    }

    @Test func aPressThatIsNotSwallowedEndsAnEarlierSwallow() {
        // A lost mouse-up (the tap was disabled for a moment) must not swallow the next click's release.
        var swallowing = true
        #expect(!swallow(.leftMouseDown, at: CGPoint(x: 500, y: 500), &swallowing))
        #expect(!swallow(.leftMouseUp, at: CGPoint(x: 500, y: 500), &swallowing))
    }
}

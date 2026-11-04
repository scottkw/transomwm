import CoreGraphics
import TransomEngine
@testable import TransomMac
import Testing

private let stripped: [CGEventType] = [.flagsChanged, .leftMouseDragged, .leftMouseUp]
private let states: [DragOptionStrip] = [.off, .always, .withControl]

/// D-07a: ⌥ goes only from the three event types, with the state the Arranger published. Measured: taking it from drags
/// alone or swallowing flagsChanged leaves macOS's guide (RESEARCH Finding 1).
@Suite struct DragOptionRuleTests {
    @Test(arguments: stripped)
    func alwaysRemovesOptionFromThePassedEvents(type: CGEventType) {
        #expect(DragOptionRule.strips(type: type, flags: .maskAlternate, state: .always))
        #expect(DragOptionRule.strips(type: type, flags: [.maskAlternate, .maskCommand], state: .always))
    }

    @Test(arguments: stripped)
    func withControlNeedsControlToo(type: CGEventType) {
        #expect(DragOptionRule.strips(type: type, flags: [.maskAlternate, .maskControl], state: .withControl))
        #expect(!DragOptionRule.strips(type: type, flags: .maskAlternate, state: .withControl))
    }

    @Test(arguments: stripped)
    func withNoOptionThereIsNothingToRemove(type: CGEventType) {
        for state in states {
            #expect(!DragOptionRule.strips(type: type, flags: [], state: state))
            #expect(!DragOptionRule.strips(type: type, flags: .maskControl, state: state))
        }
    }

    @Test(arguments: stripped)
    func offRemovesNothing(type: CGEventType) {
        #expect(!DragOptionRule.strips(type: type, flags: [.maskAlternate, .maskControl], state: .off))
    }

    /// ⌥-click means something to the app, and a press isn't a move yet.
    @Test func aPressIsNeverTouched() {
        for state in states {
            #expect(!DragOptionRule.strips(type: .leftMouseDown, flags: [.maskAlternate, .maskControl], state: state))
        }
    }
}

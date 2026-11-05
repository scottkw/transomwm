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
        #expect(DragOptionRule.strips(type: type, flags: .maskAlternate, state: .always, leftButtonDown: true))
        #expect(DragOptionRule.strips(type: type, flags: [.maskAlternate, .maskCommand], state: .always, leftButtonDown: true))
    }

    @Test(arguments: stripped)
    func withControlNeedsControlToo(type: CGEventType) {
        #expect(DragOptionRule.strips(type: type, flags: [.maskAlternate, .maskControl], state: .withControl, leftButtonDown: true))
        #expect(!DragOptionRule.strips(type: type, flags: .maskAlternate, state: .withControl, leftButtonDown: true))
    }

    @Test(arguments: stripped)
    func withNoOptionThereIsNothingToRemove(type: CGEventType) {
        for state in states {
            #expect(!DragOptionRule.strips(type: type, flags: [], state: state, leftButtonDown: true))
            #expect(!DragOptionRule.strips(type: type, flags: .maskControl, state: state, leftButtonDown: true))
        }
    }

    @Test(arguments: stripped)
    func offRemovesNothing(type: CGEventType) {
        #expect(!DragOptionRule.strips(type: type, flags: [.maskAlternate, .maskControl], state: .off, leftButtonDown: true))
    }

    /// WR-04: a lost mouse-up leaves a stale session publishing the strip. With the button up there is no drag, so ⌥ stays.
    @Test func aModifierChangeWithTheButtonUpIsNotStripped() {
        for state in states {
            #expect(!DragOptionRule.strips(type: .flagsChanged, flags: [.maskAlternate, .maskControl], state: state, leftButtonDown: false))
        }
        #expect(DragOptionRule.strips(type: .flagsChanged, flags: .maskAlternate, state: .always, leftButtonDown: true))
    }

    /// A dragged event and a mouse-up settle it themselves, so the button is never asked about them.
    @Test(arguments: [CGEventType.leftMouseDragged, .leftMouseUp])
    func onlyAModifierChangeAsksAboutTheButton(type: CGEventType) {
        #expect(DragOptionRule.strips(type: type, flags: .maskAlternate, state: .always, leftButtonDown: false))
    }

    /// The read is a call into the window server from the tap, so it must be skipped when nothing would be stripped.
    @Test func theButtonIsReadOnlyWhenItDecides() {
        func asked(_ flags: CGEventFlags, _ state: DragOptionStrip) -> Bool {
            var read = false
            _ = DragOptionRule.strips(type: .flagsChanged, flags: flags, state: state, leftButtonDown: {
                read = true
                return true
            }())
            return read
        }
        #expect(!asked(.maskAlternate, .off))
        #expect(!asked([], .always))
        #expect(!asked(.maskAlternate, .withControl))
        #expect(asked(.maskAlternate, .always))
    }

    /// ⌥-click means something to the app, and a press isn't a move yet.
    @Test func aPressIsNeverTouched() {
        for state in states {
            #expect(!DragOptionRule.strips(type: .leftMouseDown, flags: [.maskAlternate, .maskControl], state: state, leftButtonDown: true))
        }
    }
}

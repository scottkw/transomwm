import TransomEngine
import TransomMac
import TransomModel
import Testing

/// UI-SPEC Surface 5: the gesture Debug lines G1-G4.
@Suite struct GestureCopyTests {
    @Test(arguments: [
        (GestureCopy.Source.on, "Gestures: on, trackpad events"),
        (.onWithMultitouch, "Gestures: on, trackpad events and multitouch"),
        (.offZoom, "Gestures: off (zoom off)"),
        (.offTapNotRunning, "Gestures: off (gesture tap not running)"),
        (.unavailable, "Gestures: unavailable (no gesture source)"),
    ])
    func gesturesLine(source: GestureCopy.Source, expected: String) {
        #expect(GestureCopy.gesturesLine(source) == expected)
    }

    @Test func takenLine() {
        #expect(GestureCopy.takenLine(taken: 0, timeouts: 0) == "Gestures taken: none yet")
        #expect(GestureCopy.takenLine(taken: 12, timeouts: 0) == "Gestures taken: 12")
        #expect(GestureCopy.takenLine(taken: 12, timeouts: 2) == "Gestures taken: 12, 2 ended by timeout")
    }

    @Test func lastGestureNoneYet() {
        #expect(GestureCopy.lastGestureNone == "Last gesture: none yet")
    }

    @Test(arguments: [
        (GestureRecognizer.Direction.pinchIn, GestureCopy.Outcome.moved, "Last gesture: pinch in, moved"),
        (.pan(.right), .sprangBack, "Last gesture: pan right, sprang back"),
        (.pinchOut, .refused(.alreadyHome), "Last gesture: pinch out, already showing all windows"),
        (.pinchIn, .refused(.nothingToZoomIn), "Last gesture: pinch in, nothing to zoom in to"),
        (.pan(.left), .refused(.noArea(.left)), "Last gesture: pan left, no area to the left"),
        (.pan(.bottom), .refused(.noArea(.bottom)), "Last gesture: pan down, no area below"),
        (.pan(.top), .tooSmall, "Last gesture: pan up, too small"),
    ])
    func lastGestureLine(direction: GestureRecognizer.Direction, outcome: GestureCopy.Outcome, expected: String) {
        #expect(GestureCopy.lastGestureLine(kind: .pinch, direction: direction, outcome: outcome) == expected)
    }

    @Test func aGestureThatNeverPickedADirectionIsNamedByItsKind() {
        #expect(GestureCopy.lastGestureLine(kind: .pinch, direction: nil, outcome: .tooSmall) == "Last gesture: pinch, too small")
        #expect(GestureCopy.lastGestureLine(kind: .pan, direction: nil, outcome: .tooSmall) == "Last gesture: pan, too small")
    }

    @Test func refusalTextIsTheAnnouncementLowerCaseFirst() {
        #expect(GestureCopy.refusalText(.noArea(.top)) == "no area above")
        #expect(GestureCopy.refusalText(.noArea(.right)) == "no area to the right")
    }

    @Test(arguments: [
        (GestureCopy.Multitouch.available(1), "Multitouch: available, 1 trackpad"),
        (.available(3), "Multitouch: available, 3 trackpads"),
        (.available(0), "Multitouch: available, no trackpad found"),
        (.off, "Multitouch: off, trackpad events only"),
        (.offAfterCrash, "Multitouch: off after a crash last launch, trackpad events only"),
    ])
    func multitouchLine(state: GestureCopy.Multitouch, expected: String) {
        #expect(GestureCopy.multitouchLine(state) == expected)
    }
}

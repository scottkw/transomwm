import CoreGraphics
@testable import TransomMac
import Testing
import TransomModel

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

    @Test func anEscCanceledBandStillTakesTheRestOfItsPressThenLetsGo() {
        // Esc is heard on main and changes nothing in the tap, so the drags and the up after a cancel are still taken
        // and no app sees half a click (ZOOM-12); the next press is the app's.
        var swallow = ZoomTapRules.Swallow.none
        #expect(decide(.leftMouseDown, flags: commandShift, &swallow) == .consume(.band))
        #expect(decide(.leftMouseDragged, at: CGPoint(x: 600, y: 500), flags: commandShift, &swallow) == .consume(.band))
        #expect(swallow == .band)
        #expect(decide(.leftMouseDragged, at: CGPoint(x: 650, y: 520), &swallow) == .consume(.band))
        #expect(decide(.leftMouseUp, at: CGPoint(x: 650, y: 520), &swallow) == .consume(.band))
        #expect(decide(.leftMouseDown, &swallow) == .pass)
    }

    @Test func theRepostedPairPassesTheRulesWhileAnotherBandIsTaken() {
        var swallow = ZoomTapRules.Swallow.band
        #expect(decide(.leftMouseDown, flags: commandShift, userData: ZoomTapRules.repostTag, &swallow) == .pass)
        #expect(decide(.leftMouseUp, flags: commandShift, userData: ZoomTapRules.repostTag, &swallow) == .pass)
    }
}

private let tile = CGRect(x: 100, y: 100, width: 600, height: 400)
private let titleBand = CGRect(x: 800, y: 100, width: 500, height: 28)
private let inTile = CGPoint(x: 300, y: 300)
private let inTitle = CGPoint(x: 1000, y: 110)
private let full = ZoomTapState(
    armed: true, deskDisplays: [CGRect(x: 0, y: 0, width: 1440, height: 900)], titleBars: [9: titleBand], pickTiles: [7: tile],
    titleBarDoubleClick: true)

/// Pick mode clicks (ZOOM-06) and title-bar double-clicks (ZOOM-10): a click is taken (down and up) only on the window
/// the tile or band belongs to; the Desktop double-click (ZOOM-11) is never taken.
@Suite struct ZoomTapClickRulesTests {
    private func decide(
        _ type: CGEventType, at location: CGPoint, flags: CGEventFlags = [], clickState: Int64 = 1, window: UInt32,
        state: ZoomTapState = full, _ swallow: inout ZoomTapRules.Swallow
    ) -> ZoomTapRules.Decision {
        ZoomTapRules.decide(
            type: type, location: location, flags: flags, clickState: clickState, windowID: window, userData: 0, state: state, swallow: &swallow)
    }

    @Test func aPlainClickOnAPickTileIsTakenWithItsRelease() {
        var swallow = ZoomTapRules.Swallow.none
        #expect(decide(.leftMouseDown, at: inTile, window: 7, &swallow) == .consume(.pick(7)))
        #expect(decide(.leftMouseDragged, at: inTile, window: 7, &swallow) == .consume(nil))
        #expect(decide(.leftMouseUp, at: inTile, window: 7, &swallow) == .consume(nil))
        #expect(swallow == .none)
        #expect(decide(.leftMouseDown, at: inTile, window: 7, state: ZoomTapState(armed: true, deskDisplays: full.deskDisplays), &swallow) == .pass)
    }

    @Test func aClickOutsideEveryTileOrOnAnotherWindowPasses() {
        var swallow = ZoomTapRules.Swallow.none
        #expect(decide(.leftMouseDown, at: CGPoint(x: 750, y: 600), window: 7, &swallow) == .pass)
        // A floating window over the tile is on top.
        #expect(decide(.leftMouseDown, at: inTile, window: 8, &swallow) == .pass)
        #expect(decide(.leftMouseDown, at: inTile, window: 0, &swallow) == .pass)
        #expect(decide(.leftMouseUp, at: inTile, window: 7, &swallow) == .pass)
    }

    @Test func aModifiedClickOnAPickTilePassesAndCommandShiftIsABand() {
        var swallow = ZoomTapRules.Swallow.none
        #expect(decide(.leftMouseDown, at: inTile, flags: .maskCommand, window: 7, &swallow) == .pass)
        #expect(decide(.leftMouseDown, at: inTile, flags: .maskAlternate, window: 7, &swallow) == .pass)
        #expect(decide(.leftMouseDown, at: inTile, flags: [.maskCommand, .maskShift], window: 7, &swallow) == .consume(.band))
    }

    @Test func theSecondPressOfATitleBarDoubleClickIsTakenWithItsRelease() {
        var swallow = ZoomTapRules.Swallow.none
        #expect(decide(.leftMouseDown, at: inTitle, clickState: 1, window: 9, &swallow) == .pass)
        #expect(decide(.leftMouseUp, at: inTitle, clickState: 1, window: 9, &swallow) == .pass)
        #expect(decide(.leftMouseDown, at: inTitle, clickState: 2, window: 9, &swallow) == .consume(.titleBarDoubleClick(9)))
        #expect(decide(.leftMouseUp, at: inTitle, clickState: 2, window: 9, &swallow) == .consume(nil))
        #expect(swallow == .none)
    }

    @Test func aTitleBarDoubleClickPassesWithThePreferenceOffUnarmedOrOnAnotherWindow() {
        var swallow = ZoomTapRules.Swallow.none
        var off = full
        off.titleBarDoubleClick = false
        #expect(decide(.leftMouseDown, at: inTitle, clickState: 2, window: 9, state: off, &swallow) == .pass)
        var unarmed = full
        unarmed.armed = false
        #expect(decide(.leftMouseDown, at: inTitle, clickState: 2, window: 9, state: unarmed, &swallow) == .pass)
        #expect(decide(.leftMouseDown, at: inTile, clickState: 2, window: 7, state: unarmed, &swallow) == .pass)
        #expect(decide(.leftMouseDown, at: inTitle, clickState: 2, window: 4, &swallow) == .pass)
        #expect(swallow == .none)
    }

    @Test func aDesktopDoubleClickIsNeverTaken() {
        var swallow = ZoomTapRules.Swallow.none
        #expect(decide(.leftMouseDown, at: CGPoint(x: 1000, y: 700), clickState: 2, window: 0, &swallow) == .pass)
        #expect(decide(.leftMouseUp, at: CGPoint(x: 1000, y: 700), clickState: 2, window: 0, &swallow) == .pass)
    }

    @Test func onlyAPressInsideAPickTileOrATitleBandOnADoubleClickReadsTheWindowList() {
        #expect(ZoomTapRules.needsWindow(location: inTile, clickState: 1, state: full))
        #expect(ZoomTapRules.needsWindow(location: inTitle, clickState: 2, state: full))
        #expect(!ZoomTapRules.needsWindow(location: inTitle, clickState: 1, state: full))
        #expect(!ZoomTapRules.needsWindow(location: CGPoint(x: 1000, y: 700), clickState: 2, state: full))
        var unarmed = full
        unarmed.armed = false
        #expect(!ZoomTapRules.needsWindow(location: inTile, clickState: 1, state: unarmed))
    }
}

/// The band's pure geometry: a press under 4 pt is a click (re-posted), and the band stays on its display.
@Suite struct ZoomInputGeometryTests {
    private let start = CGPoint(x: 100, y: 100)

    @Test(arguments: [(3.9, true), (4.0, false), (4.1, false)])
    func aPressUnderFourPointsIsAClick(travel: Double, click: Bool) {
        #expect(ZoomInput.isClick(start: start, end: CGPoint(x: start.x + travel, y: start.y)) == click)
        #expect(ZoomInput.isClick(start: start, end: CGPoint(x: start.x, y: start.y - travel)) == click)
    }

    @Test func theBandIsClampedToTheDisplayWhereItBegan() {
        let display = Rect(x: 0, y: 0, width: 1440, height: 900)
        #expect(ZoomInput.clamp(CGPoint(x: 2000, y: -50), to: display) == CGPoint(x: 1440, y: 0))
        #expect(ZoomInput.clamp(CGPoint(x: 700, y: 400), to: display) == CGPoint(x: 700, y: 400))
        #expect(ZoomInput.bandRect(CGPoint(x: 300, y: 200), CGPoint(x: 100, y: 500)) == Rect(x: 100, y: 200, width: 200, height: 300))
    }
}

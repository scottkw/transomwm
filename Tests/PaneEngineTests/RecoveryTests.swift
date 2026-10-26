import Foundation
import PaneEngine
import PaneModel
import Testing

private let visible = Rect(x: 0, y: 25, width: 1440, height: 875)
private let main = DisplayInfo(uuid: "main", frame: Rect(x: 0, y: 0, width: 1440, height: 900), visibleFrame: visible, currentSpaceID: nil)
/// A second display to the right of the main one.
private let side = DisplayInfo(
    uuid: "side", frame: Rect(x: 1440, y: 0, width: 1920, height: 1080), visibleFrame: Rect(x: 1440, y: 0, width: 1920, height: 1080),
    currentSpaceID: nil)

/// SAFE-02, SAFE-03, D-17, D-18 (A6 thresholds): the pure recovery rules.
@Suite struct RecoveryTests {
    @Test func aWindowMostlyOnScreenIsNotStranded() {
        // 240 of 400 pt wide inside: 60% of its area.
        #expect(!Recovery.isStranded(Rect(x: 1200, y: 100, width: 400, height: 300), displays: [main]))
    }

    @Test func aWindowMostlyOffScreenIsStranded() {
        // 160 of 400 pt wide inside: 40%.
        #expect(Recovery.isStranded(Rect(x: 1280, y: 100, width: 400, height: 300), displays: [main]))
    }

    @Test func aWindowWhoseVisiblePartIsUnder40ptIsStranded() {
        #expect(Recovery.isStranded(Rect(x: 1410, y: 100, width: 400, height: 300), displays: [main]))
        // 58% of a 60 pt window is visible, but only 35 pt of it: under the 40 pt floor.
        #expect(Recovery.isStranded(Rect(x: 1405, y: 100, width: 60, height: 300), displays: [main]))
    }

    @Test func theFloorIsCappedAtTheWindowsOwnSize() {
        #expect(!Recovery.isStranded(Rect(x: 100, y: 100, width: 30, height: 30), displays: [main]))
    }

    @Test func visibilityUsesTheUnionOfEveryDisplaysVisibleFrame() {
        // Half on each display.
        let straddling = Rect(x: 1240, y: 100, width: 400, height: 300)
        #expect(!Recovery.isStranded(straddling, displays: [main, side]))
        #expect(!Recovery.isStranded(Rect(x: 2000, y: 100, width: 400, height: 300), displays: [main, side]))
        #expect(Recovery.isStranded(Rect(x: 10000, y: 100, width: 400, height: 300), displays: [main, side]))
        #expect(Recovery.isStranded(Rect(x: 100, y: 100, width: 400, height: 300), displays: []))
    }

    @Test func theDestinationIsTheHomeFrameClampedOnScreen() {
        let home = Rect(x: 1300, y: 700, width: 400, height: 300)
        #expect(Recovery.destination(for: Rect(x: 9000, y: 9000, width: 10, height: 10), home: home, display: main)
            == Rect(x: 1040, y: 600, width: 400, height: 300))
        let inside = Rect(x: 100, y: 100, width: 400, height: 300)
        #expect(Recovery.destination(for: .init(x: 9000, y: 0, width: 400, height: 300), home: inside, display: main) == inside)
    }

    @Test func withoutAHomeTheWindowKeepsItsSizeCentredOnItsDisplay() {
        #expect(Recovery.destination(for: Rect(x: 10000, y: 50, width: 400, height: 300), home: nil, display: main)
            == Rect(x: 520, y: 312.5, width: 400, height: 300))
    }

    @Test func withoutAHomeATooLargeWindowShrinksToTheVisibleFrame() {
        #expect(Recovery.destination(for: Rect(x: 10000, y: 50, width: 2000, height: 300), home: nil, display: main)
            == Rect(x: 0, y: 312.5, width: 1440, height: 300))
        #expect(Recovery.destination(for: Rect(x: 10000, y: 50, width: 3000, height: 2000), home: nil, display: main) == visible)
    }

    @Test func aCleanOrMissingPreviousSessionIsANormalLaunch() {
        #expect(Recovery.launchMode(previous: nil) == .normal)
        #expect(Recovery.launchMode(previous: SessionRecord(cleanExit: true, launchedAt: Date())) == .normal)
    }

    @Test func anUncleanPreviousSessionIsARecoveryLaunch() {
        #expect(Recovery.launchMode(previous: SessionRecord(cleanExit: false, launchedAt: Date())) == .recovery)
    }

    /// D-18: a second unclean exit before the recovery launch survived its first minute.
    @Test func anUncleanRecoveryLaunchThatDidNotSurviveAMinuteIsACrashLoop() {
        let now = Date()
        #expect(Recovery.launchMode(previous: SessionRecord(cleanExit: false, launchedAt: now, recoveryLaunch: true, survivedMinute: false))
            == .crashLoop)
        #expect(Recovery.launchMode(previous: SessionRecord(cleanExit: false, launchedAt: now, recoveryLaunch: true, survivedMinute: true))
            == .recovery)
        #expect(Recovery.launchMode(previous: SessionRecord(cleanExit: false, launchedAt: now, recoveryLaunch: false)) == .recovery)
        #expect(Recovery.launchMode(previous: SessionRecord(cleanExit: true, launchedAt: now, recoveryLaunch: true)) == .normal)
    }

    @Test func survivedMinuteIsDueAMinuteAfterARecoveryOrCrashLoopLaunch() {
        let launched = ContinuousClock.now
        #expect(Recovery.survivedMinuteDue(launchedAt: launched, mode: .recovery) == launched + .seconds(60))
        #expect(Recovery.survivedMinuteDue(launchedAt: launched, mode: .crashLoop) == launched + .seconds(60))
        #expect(Recovery.survivedMinuteDue(launchedAt: launched, mode: .normal) == nil)
    }
}

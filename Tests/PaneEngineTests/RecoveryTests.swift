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

    /// WR-05: an unreadable layout.json hides the last session's record, whatever it said.
    @Test func anUnreadableLayoutIsAnUnreadableLaunch() {
        #expect(Recovery.launchMode(previous: nil, unreadable: true) == .unreadable)
        #expect(Recovery.launchMode(previous: nil, unreadable: false) == .normal)
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

    // MARK: Quit restore (SAFE-01, D-15)

    private static func window(_ id: UInt32) -> WindowRef {
        WindowRef(identity: WindowIdentity(windowID: id, pid: 900, bundleID: "com.example.x"))
    }

    private static func info(_ window: WindowRef, _ frame: Rect, display: String = "main", excluded: Bool = false) -> WindowInfo {
        WindowInfo(window: window, frame: frame, state: .present, displayUUID: display, kind: .dockable, isExcluded: excluded)
    }

    @Test func aParkedFloatingWindowGoesToItsHomeFrameClampedOnScreen() {
        let parked = Self.window(1)
        let home = Rect(x: 1300, y: 700, width: 400, height: 300)
        let plan = Recovery.terminationPlan(
            windows: [Self.info(parked, main.parkedFrame(size: Size(width: 400, height: 300), among: [main]))], homeFrames: [parked.identity: home],
            displays: [main], docked: [])
        #expect(plan == [parked: Rect(x: 1040, y: 600, width: 400, height: 300)])
    }

    /// The park corner of the main display can be mostly visible on a display to its right: the home frame still wins,
    /// on the display it is on.
    @Test func aParkedWindowGoesHomeEvenWhenItsParkCornerShowsOnANeighbouringDisplay() {
        let parked = Self.window(1)
        let home = Rect(x: 100, y: 100, width: 400, height: 300)
        // The bottom-right corner, where a window parked before CR-02 (or with both bottom corners taken) can still be.
        let corner = Rect(x: visible.maxX - 1, y: visible.maxY - 1, width: 400, height: 300)
        #expect(!Recovery.isStranded(corner, displays: [main, side]))
        let plan = Recovery.terminationPlan(
            windows: [Self.info(parked, corner, display: "side")], homeFrames: [parked.identity: home], displays: [main, side], docked: [])
        #expect(plan == [parked: home])
    }

    /// CR-02: a parked window never lands on a neighbouring display, so it stays parked and counts as stranded.
    @Test func theParkCornerAvoidsANeighbouringDisplay() {
        let size = Size(width: 400, height: 300)
        #expect(main.parkedFrame(size: size, among: [main]) == Rect(x: visible.maxX - 1, y: visible.maxY - 1, width: 400, height: 300))
        let fromMain = main.parkedFrame(size: size, among: [main, side])
        #expect(!fromMain.overlaps(side.frame), "parked onto the display to the right: \(fromMain)")
        #expect(Recovery.isStranded(fromMain, displays: [main, side]))
        let fromSide = side.parkedFrame(size: size, among: [main, side])
        #expect(!fromSide.overlaps(main.frame), "parked onto the display to the left: \(fromSide)")
    }

    /// With both bottom corners next to another display, the window goes past the bottom-right of every display.
    @Test func withBothBottomCornersTakenTheParkGoesPastEveryDisplay() {
        let left = DisplayInfo(
            uuid: "left", frame: Rect(x: -1920, y: 0, width: 1920, height: 1080), visibleFrame: Rect(x: -1920, y: 0, width: 1920, height: 1080),
            currentSpaceID: nil)
        let parked = main.parkedFrame(size: Size(width: 400, height: 300), among: [left, main, side])
        #expect(parked == Rect(x: 3359, y: 1079, width: 400, height: 300))
        #expect(!parked.overlaps(left.frame) && !parked.overlaps(main.frame))
    }

    @Test func anOffScreenFloatingWindowWithNoHomeIsCentredOnItsDisplay() {
        let lost = Self.window(2)
        let plan = Recovery.terminationPlan(
            windows: [Self.info(lost, Rect(x: 10000, y: 50, width: 400, height: 300))], homeFrames: [:], displays: [main], docked: [])
        #expect(plan == [lost: Rect(x: 520, y: 312.5, width: 400, height: 300)])
    }

    @Test func aDockedOnScreenWindowAndAnOnScreenFloatingOneAreLeftAlone() {
        let docked = Self.window(3), floating = Self.window(4)
        let plan = Recovery.terminationPlan(
            windows: [Self.info(docked, Rect(x: 0, y: 25, width: 720, height: 875)), Self.info(floating, Rect(x: 800, y: 100, width: 300, height: 200))],
            homeFrames: [:], displays: [main], docked: [docked.identity])
        #expect(plan.isEmpty)
    }

    @Test func anExcludedOrNeverDockWindowIsNeverMoved() {
        let excluded = Self.window(5), panel = Self.window(6)
        var never = Self.info(panel, Rect(x: 10000, y: 50, width: 400, height: 300))
        never.kind = .neverDock(.subrole)
        let plan = Recovery.terminationPlan(
            windows: [Self.info(excluded, Rect(x: 10000, y: 50, width: 400, height: 300), excluded: true), never],
            homeFrames: [excluded.identity: Rect(x: 100, y: 100, width: 400, height: 300)], displays: [main], docked: [])
        #expect(plan.isEmpty)
    }
}

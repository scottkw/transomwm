import Foundation
@testable import TransomEngine
import TransomModel
import Testing

private func parse(_ string: String, scheme: String = "transom") -> Command? {
    URL(string: string).flatMap { TransomURL.parse($0, scheme: scheme) }
}

/// SAFE-03, TILE-17, Pitfall 21, T-03-40: two parameterless commands, nothing else gets through.
@Suite struct TransomURLTests {
    @Test func theTwoCommandsParse() {
        #expect(parse("transom://restore") == .restoreAll)
        #expect(parse("transom://split-finder") == .finderSplit)
        #expect(parse("transom://restore/") == .restoreAll)
        #expect(parse("transom-debug://restore", scheme: "transom-debug") == .restoreAll)
    }

    /// Hide/Show Desktop Tile and Frame Desktop were removed (8.1.1 D-09, D-13): their old URLs are unknown and run nothing.
    @Test func theRemovedDesktopCommandsAreUnknown() {
        #expect(parse("transom://toggle-desktop") == nil)
        #expect(parse("transom://frame-desktop") == nil)
    }

    /// 04 UI-SPEC Hotkeys and URLs: every navigation action has a URL.
    @Test(arguments: [
        ("zoom-out", CameraCommand.zoomOutAll), ("step-out", .stepOut), ("step-in", .stepIn), ("back", .back), ("forward", .forward),
        ("pan-left", .pan(.left)), ("pan-right", .pan(.right)), ("pan-up", .pan(.top)), ("pan-down", .pan(.bottom)),
        ("frame-window", .frameWindow), ("overview", .overview),
    ])
    func theZoomCommandsParse(host: String, command: CameraCommand) {
        #expect(parse("transom://\(host)") == .camera(command))
        #expect(parse("transom://\(host)/") == .camera(command))
    }

    @Test(arguments: ["transom://ZOOM-OUT", "transom://zoom-out?x=1", "transom://zoom-out/extra", "transom://zoom-out#f", "transom://zoom-in", "transom://overview?x=1",
        "transom://Overview", "transom://show-overview"])
    func malformedZoomURLsAreRejected(_ string: String) {
        #expect(parse(string) == nil)
    }

    /// 07 UI-SPEC Surface 7: the three tab commands.
    @Test(arguments: [("next-tab", TabCommand.next), ("previous-tab", .previous), ("move-out-of-group", .moveOut)])
    func theTabCommandsParse(host: String, command: TabCommand) {
        #expect(parse("transom://\(host)") == .tabs(command))
        #expect(parse("transom://\(host)/") == .tabs(command))
    }

    @Test(arguments: ["transom://next-tab?x=1", "transom://NEXT-TAB", "transom://next-tab#f", "transom://next-tab/extra", "transom://Move-Out-Of-Group",
        "transom://move-out", "transom://previous-tab:80"])
    func malformedTabURLsAreRejected(_ string: String) {
        #expect(parse(string) == nil)
    }

    /// 08.1 UI-SPEC Surface 5: the ten fourths.
    @Test(arguments: [
        ("dock-column-1", FourthSlot.first, Axis.horizontal), ("dock-column-2", .second, .horizontal), ("dock-column-3", .third, .horizontal),
        ("dock-column-4", .fourth, .horizontal), ("dock-column-middle", .middle, .horizontal), ("dock-row-1", .first, .vertical),
        ("dock-row-2", .second, .vertical), ("dock-row-3", .third, .vertical), ("dock-row-4", .fourth, .vertical),
        ("dock-row-middle", .middle, .vertical),
    ])
    func theFourthCommandsParse(host: String, slot: FourthSlot, axis: Axis) {
        #expect(parse("transom://\(host)") == .dockFourth(slot, axis))
        #expect(parse("transom://\(host)/") == .dockFourth(slot, axis))
    }

    @Test(arguments: ["transom://dock-column-5", "transom://DOCK-COLUMN-1", "transom://dock-column/1", "transom://dock-column-1/1", "transom://dock-column-1?x=1",
        "transom://dock-column-1#f", "transom://dock-row-0", "transom://dock-fourth"])
    func malformedFourthURLsAreRejected(_ string: String) {
        #expect(parse(string) == nil)
    }

    /// 08.1.1 UI-SPEC Surface 4: the ten halves and thirds.
    @Test(arguments: [
        ("dock-left-half", FourthSlot.firstHalf, Axis.horizontal), ("dock-right-half", .secondHalf, .horizontal),
        ("dock-top-half", .firstHalf, .vertical), ("dock-bottom-half", .secondHalf, .vertical),
        ("dock-left-third", .firstThird, .horizontal), ("dock-center-third", .middleThird, .horizontal), ("dock-right-third", .lastThird, .horizontal),
        ("dock-top-third", .firstThird, .vertical), ("dock-middle-third", .middleThird, .vertical), ("dock-bottom-third", .lastThird, .vertical),
    ])
    func theHalfAndThirdCommandsParse(host: String, slot: FourthSlot, axis: Axis) {
        #expect(parse("transom://\(host)") == .dockFourth(slot, axis))
        #expect(parse("transom://\(host)/") == .dockFourth(slot, axis))
    }

    @Test(arguments: ["transom:///dock-left-half/", "transom://DOCK-LEFT-HALF", "transom://dock-half/left", "transom://dock-left-half/1",
        "transom://dock-left-half?x=1", "transom://dock-center-third#f", "transom://dock-middle-half"])
    func malformedHalfAndThirdURLsAreRejected(_ string: String) {
        #expect(parse(string) == nil)
    }

    /// 8.1.1 D-17: the four corner quarters.
    @Test(arguments: [
        ("dock-top-left", DockCorner.topLeft), ("dock-top-right", .topRight), ("dock-bottom-left", .bottomLeft), ("dock-bottom-right", .bottomRight),
    ])
    func theCornerCommandsParse(host: String, corner: DockCorner) {
        #expect(parse("transom://\(host)") == .dockCorner(corner))
        #expect(parse("transom://\(host)/") == .dockCorner(corner))
    }

    @Test func thereAreFortyParameterlessCommands() {
        #expect(TransomURL.commands.count == 40)
    }

    /// T-08.1.1-07: an opened half URL and an opened fourth URL share the one dock second.
    @Test func anOpenedHalfURLSharesTheDockSecondWithAFourth() {
        var limiter = TransomURLRateLimiter()
        let start = ContinuousClock.now
        let attempts: [(Command, Duration)] = [
            (.dockFourth(.firstHalf, .horizontal), .zero), (.dockFourth(.first, .vertical), .milliseconds(10)),
            (.dockFourth(.middleThird, .vertical), .milliseconds(20)), (.dockFourth(.second, .horizontal), .seconds(1)),
        ]
        #expect(attempts.map { limiter.admitOpenedURL($0.0, at: start + $0.1) } == [true, false, false, true])
    }

    /// WR-09: on the URL route the fourths share a second, on top of each command's own, and other commands are untouched.
    @Test func openedDockURLsShareOneSecond() {
        var limiter = TransomURLRateLimiter()
        let start = ContinuousClock.now
        let attempts: [(Command, Duration)] = [
            (.dockFourth(.first, .horizontal), .zero), (.dockFourth(.second, .vertical), .milliseconds(10)), (.restoreAll, .milliseconds(20)),
            (.dockFourth(.middle, .horizontal), .seconds(1)),
        ]
        #expect(attempts.map { limiter.admitOpenedURL($0.0, at: start + $0.1) } == [true, false, true, true])
    }

    /// D-07: one limiter for both routes. The CLI's use of a command uses up its second for URLs too, but not the family's.
    @Test func theCLIUsesUpACommandsSecondButNotTheFamilys() {
        var limiter = TransomURLRateLimiter()
        let start = ContinuousClock.now
        let cli = limiter.admit(.dockFourth(.first, .horizontal), at: start)
        let sameByURL = limiter.admitOpenedURL(.dockFourth(.first, .horizontal), at: start + .milliseconds(10))
        let otherByURL = limiter.admitOpenedURL(.dockFourth(.second, .horizontal), at: start + .milliseconds(20))
        let cliAfterURL = limiter.admit(.dockFourth(.third, .horizontal), at: start + .milliseconds(30))
        #expect([cli, sameByURL, otherByURL, cliAfterURL] == [true, false, true, true])
    }

    /// T-08.1-12: on the CLI route each fourth has its own one-per-second limit.
    @Test func eachFourthIsLimitedSeparately() {
        var limiter = TransomURLRateLimiter()
        let start = ContinuousClock.now
        let attempts: [(Command, Duration)] = [
            (.dockFourth(.first, .horizontal), .zero), (.dockFourth(.second, .horizontal), .milliseconds(10)), (.dockFourth(.first, .horizontal), .milliseconds(20)),
        ]
        #expect(attempts.map { limiter.admit($0.0, at: start + $0.1) } == [true, true, false])
    }

    /// 08 UI-SPEC Surface 4: the same commands as ⌥{n} and ⇧⌥{n}.
    @Test(arguments: 1...9)
    func theViewCommandsParse(number: Int) throws {
        let slot = try #require(ViewSlot(number))
        #expect(parse("transom://view/\(number)") == .camera(.view(slot)))
        #expect(parse("transom://save-view/\(number)") == .camera(.saveView(slot)))
    }

    /// 08 UI-SPEC Surface 4: every other path form, with no side effect (T-08-13).
    @Test(arguments: ["view", "save-view"])
    func malformedViewURLsAreRejected(host: String) {
        for suffix in ["", "/", "/0", "/10", "/3/", "/03", "/%33", "/a", "/3?x=1", "/3#f", ":80/3", "//3"] {
            #expect(parse("transom://\(host)\(suffix)") == nil, "\(host)\(suffix)")
        }
        #expect(parse("transom://\(host.uppercased())/3") == nil)
        #expect(parse("transom://user@\(host)/3") == nil)
    }

    @Test func aPathIsOnlyAcceptedForTheViewCommands() {
        #expect(parse("transom://zoom-out/3") == nil)
        #expect(parse("transom://restore/1") == nil)
    }

    /// D-06: each slot is its own command.
    @Test func eachSlotIsLimitedSeparately() throws {
        var limiter = TransomURLRateLimiter()
        let start = ContinuousClock.now
        let three = try #require(ViewSlot(3))
        let four = try #require(ViewSlot(4))
        let attempts: [(Command, Duration)] = [
            (.camera(.view(three)), .zero), (.camera(.view(four)), .milliseconds(10)), (.camera(.saveView(three)), .milliseconds(20)),
            (.camera(.view(three)), .milliseconds(30)),
        ]
        #expect(attempts.map { limiter.admit($0.0, at: start + $0.1) } == [true, true, true, false])
    }

    @Test(arguments: [
        "transom://Restore", "transom://restore?x=1", "transom://restore?", "transom://restore#a", "transom://user@restore",
        "transom://user:secret@restore", "transom://restore:80", "transom://restore/extra", "transom://zoom", "transom-debug://restore",
        "TRANSOM://restore", "http://restore", "transom://", "transom:restore", "transom://re%73tore",
    ])
    func everythingElseIsRejected(_ string: String) {
        #expect(parse(string) == nil)
    }

    @Test func aCommandRunsAtMostOncePerSecond() {
        var limiter = TransomURLRateLimiter()
        let start = ContinuousClock.now
        let admitted = [start, start + .milliseconds(500), start + .seconds(1)].map { limiter.admit(.restoreAll, at: $0) }
        #expect(admitted == [true, false, true])
    }

    @Test func differentCommandsAreLimitedSeparately() {
        var limiter = TransomURLRateLimiter()
        let start = ContinuousClock.now
        let attempts: [(Command, Duration)] = [(.restoreAll, .zero), (.camera(.back), .zero), (.finderSplit, .milliseconds(10)), (.camera(.back), .milliseconds(20))]
        let admitted = attempts.map { limiter.admit($0.0, at: start + $0.1) }
        #expect(admitted == [true, true, true, false])
    }
}

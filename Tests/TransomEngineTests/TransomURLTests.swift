import Foundation
import TransomEngine
import TransomModel
import Testing

private func parse(_ string: String, scheme: String = "transom") -> Command? {
    URL(string: string).flatMap { TransomURL.parse($0, scheme: scheme) }
}

/// SAFE-03, TILE-15, TILE-17, Pitfall 21, T-03-40: three parameterless commands, nothing else gets through.
@Suite struct TransomURLTests {
    @Test func theThreeCommandsParse() {
        #expect(parse("transom://restore") == .restoreAll)
        #expect(parse("transom://toggle-desktop") == .toggleDesktop)
        #expect(parse("transom://split-finder") == .finderSplit)
        #expect(parse("transom://restore/") == .restoreAll)
        #expect(parse("transom-debug://restore", scheme: "transom-debug") == .restoreAll)
    }

    /// 04 UI-SPEC Hotkeys and URLs: every navigation action has a URL.
    @Test(arguments: [
        ("zoom-out", CameraCommand.zoomOutAll), ("step-out", .stepOut), ("step-in", .stepIn), ("back", .back), ("forward", .forward),
        ("pan-left", .pan(.left)), ("pan-right", .pan(.right)), ("pan-up", .pan(.top)), ("pan-down", .pan(.bottom)),
        ("frame-window", .frameWindow), ("frame-desktop", .frameDesktop), ("overview", .overview),
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

    /// T-08.1-12: each fourth has its own one-per-second limit.
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
        let attempts: [(Command, Duration)] = [(.restoreAll, .zero), (.toggleDesktop, .zero), (.finderSplit, .milliseconds(10)), (.toggleDesktop, .milliseconds(20))]
        let admitted = attempts.map { limiter.admit($0.0, at: start + $0.1) }
        #expect(admitted == [true, true, true, false])
    }
}

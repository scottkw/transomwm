import PaneEngine
import PaneModel
import Testing

/// One row of the close decision table (RESEARCH Pattern 4).
struct CloseRow: Sendable, CustomTestStringConvertible {
    let name: String
    var sessionActive = true
    var app: AppLiveness = .alive
    let ax: AXWindowFact
    let inCGList: Bool
    var tabMember = false
    let expected: CloseDecision

    var testDescription: String { name }
}

private func valid(listed: Bool = true, minimized: Bool = false, appHidden: Bool = false, fullScreen: Bool = false) -> AXWindowFact {
    .valid(listed: listed, minimized: minimized, appHidden: appHidden, fullScreen: fullScreen)
}

private let rows: [CloseRow] = [
    CloseRow(name: "session paused", sessionActive: false, ax: valid(), inCGList: true, expected: .noChange),
    CloseRow(name: "terminated, CG absent", app: .terminated, ax: .timedOut, inCGList: false, expected: .closed),
    CloseRow(name: "terminated, CG present", app: .terminated, ax: .timedOut, inCGList: true, expected: .recheck),
    CloseRow(name: "invalid, CG absent", ax: .invalidElement, inCGList: false, expected: .closed),
    CloseRow(name: "invalid, CG present", ax: .invalidElement, inCGList: true, expected: .recheck),
    CloseRow(name: "invalid, CG present, tab member", ax: .invalidElement, inCGList: true, tabMember: true, expected: .state(.absent)),
    CloseRow(name: "timeout, CG present", ax: .timedOut, inCGList: true, expected: .noChange),
    CloseRow(name: "timeout, CG absent", ax: .timedOut, inCGList: false, expected: .noChange),
    CloseRow(name: "valid, minimised", ax: valid(minimized: true), inCGList: true, expected: .state(.absent)),
    CloseRow(name: "valid, app hidden", ax: valid(appHidden: true), inCGList: true, expected: .state(.absent)),
    CloseRow(name: "valid, fullscreen", ax: valid(fullScreen: true), inCGList: true, expected: .state(.fullscreen)),
    CloseRow(name: "valid, unlisted, CG present", ax: valid(listed: false), inCGList: true, expected: .noChange),
    CloseRow(name: "valid, CG absent", ax: valid(), inCGList: false, expected: .recheck),
    CloseRow(name: "valid, unlisted, CG absent", ax: valid(listed: false), inCGList: false, expected: .recheck),
    CloseRow(name: "valid, listed, CG present", ax: valid(), inCGList: true, expected: .state(.present)),
    CloseRow(name: "minimised and fullscreen", ax: valid(minimized: true, fullScreen: true), inCGList: true, expected: .state(.absent)),
    CloseRow(name: "other failure, CG present", ax: .otherFailure, inCGList: true, expected: .noChange),
    CloseRow(name: "other failure, CG absent", ax: .otherFailure, inCGList: false, expected: .noChange),
    CloseRow(name: "paused overrides terminated, CG absent", sessionActive: false, app: .terminated, ax: .timedOut, inCGList: false, expected: .noChange),
    CloseRow(name: "paused overrides invalid, CG absent", sessionActive: false, ax: .invalidElement, inCGList: false, expected: .noChange),
]

private let identity = WindowIdentity(windowID: 100, pid: 42, bundleID: "com.example.app")
private let t0 = ContinuousClock.now

@Suite struct CloseRuleTests {
    @Test(arguments: rows)
    func theTableDecides(row: CloseRow) {
        let decision = CloseRule.decide(
            sessionActive: row.sessionActive, app: row.app, ax: row.ax, inCGList: row.inCGList, isKnownTabMember: row.tabMember
        )
        #expect(decision == row.expected)
    }

    @Test func noSingleSourceEverCloses() {
        // AX alone (invalid but still listed by CG) and CG alone (absent but AX valid or silent) never close.
        for ax in [valid(), valid(listed: false), .timedOut, .otherFailure] {
            #expect(CloseRule.decide(sessionActive: true, app: .alive, ax: ax, inCGList: false, isKnownTabMember: false) != .closed)
        }
        #expect(CloseRule.decide(sessionActive: true, app: .alive, ax: .invalidElement, inCGList: true, isKnownTabMember: false) != .closed)
        #expect(CloseRule.decide(sessionActive: true, app: .terminated, ax: .timedOut, inCGList: true, isKnownTabMember: false) != .closed)
    }

    @Test func aClosedIdentityIsContainedForJustUnder60s() {
        var cache = ClosedIDCache()
        cache.insert(identity, at: t0)
        #expect(cache.contains(identity, at: t0 + .seconds(59)))
        #expect(!cache.contains(identity, at: t0 + .seconds(60)))
    }

    @Test func purgeDropsExpiredEntries() {
        var cache = ClosedIDCache()
        cache.insert(identity, at: t0)
        cache.purge(at: t0 + .seconds(61))
        #expect(cache == ClosedIDCache())
        #expect(!cache.contains(identity, at: t0))
    }

    @Test func purgeKeepsLiveEntries() {
        var cache = ClosedIDCache()
        cache.insert(identity, at: t0)
        cache.purge(at: t0 + .seconds(30))
        #expect(cache.contains(identity, at: t0 + .seconds(30)))
    }

    @Test func anotherPidWithTheSameWindowIDIsNotContained() {
        var cache = ClosedIDCache()
        cache.insert(identity, at: t0)
        let other = WindowIdentity(windowID: 100, pid: 43, bundleID: "com.example.app")
        #expect(cache.contains(identity, at: t0))
        #expect(!cache.contains(other, at: t0))
    }
}

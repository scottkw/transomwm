import Foundation
import PaneEngine
import Testing

private func parse(_ string: String, scheme: String = "pane") -> Command? {
    URL(string: string).flatMap { PaneURL.parse($0, scheme: scheme) }
}

/// SAFE-03, TILE-15, TILE-17, Pitfall 21, T-03-40: three parameterless commands, nothing else gets through.
@Suite struct PaneURLTests {
    @Test func theThreeCommandsParse() {
        #expect(parse("pane://restore") == .restoreAll)
        #expect(parse("pane://toggle-desktop") == .toggleDesktop)
        #expect(parse("pane://split-finder") == .finderSplit)
        #expect(parse("pane://restore/") == .restoreAll)
        #expect(parse("pane-debug://restore", scheme: "pane-debug") == .restoreAll)
    }

    @Test(arguments: [
        "pane://Restore", "pane://restore?x=1", "pane://restore?", "pane://restore#a", "pane://user@restore",
        "pane://user:secret@restore", "pane://restore:80", "pane://restore/extra", "pane://zoom", "pane-debug://restore",
        "PANE://restore", "http://restore", "pane://", "pane:restore", "pane://re%73tore",
    ])
    func everythingElseIsRejected(_ string: String) {
        #expect(parse(string) == nil)
    }

    @Test func aCommandRunsAtMostOncePerSecond() {
        var limiter = PaneURLRateLimiter()
        let start = ContinuousClock.now
        let admitted = [start, start + .milliseconds(500), start + .seconds(1)].map { limiter.admit(.restoreAll, at: $0) }
        #expect(admitted == [true, false, true])
    }

    @Test func differentCommandsAreLimitedSeparately() {
        var limiter = PaneURLRateLimiter()
        let start = ContinuousClock.now
        let attempts: [(Command, Duration)] = [(.restoreAll, .zero), (.toggleDesktop, .zero), (.finderSplit, .milliseconds(10)), (.toggleDesktop, .milliseconds(20))]
        let admitted = attempts.map { limiter.admit($0.0, at: start + $0.1) }
        #expect(admitted == [true, true, true, false])
    }
}

import Foundation
import TransomEngine
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

import Foundation
import Testing
import TransomEngine
import TransomModel

/// Tests/TransomEngineTests/GestureRecognizerTests.swift -> Tests/TransomEngineTests/Fixtures/Gestures.
private let traceDirectory = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent().appendingPathComponent("Fixtures/Gestures")

/// One sample per line, in the spike's tap-listen keys (t, kind, phase, momentum, m, dx, dy).
private func trace(_ name: String) throws -> [GestureRecognizer.Sample] {
    let text = try String(contentsOf: traceDirectory.appendingPathComponent(name), encoding: .utf8)
    return try text.split(separator: "\n").map { try JSONDecoder().decode(GestureRecognizer.Sample.self, from: Data($0.utf8)) }
}

private let screen = Size(width: 1440, height: 900)

private func run(_ samples: [GestureRecognizer.Sample], kind: GestureRecognizer.Kind) -> (GestureRecognizer, [GestureRecognizer.Update]) {
    var recognizer = GestureRecognizer(kind: kind, viewSize: screen)
    let updates = samples.compactMap { recognizer.feed($0) }
    return (recognizer, updates)
}

private func releases(_ updates: [GestureRecognizer.Update]) -> [GestureRecognizer.Release] {
    updates.compactMap { if case .ended(let release) = $0 { release } else { nil } }
}

private func pinch(_ t: Double, _ phase: Int, _ m: Double) -> GestureRecognizer.Sample {
    GestureRecognizer.Sample(t: t, kind: .pinch, phase: phase, magnification: m)
}

/// D-08: every gesture judgement, headless, from JSONL traces in the spike's sample format.
@Suite struct GestureRecognizerTests {
    @Test func aPinchInPastHalfALevelCommits() throws {
        let (recognizer, updates) = run(try trace("pinch-in-commit.jsonl"), kind: .pinch)

        let starts = updates.filter { if case .started = $0 { true } else { false } }
        #expect(starts == [.started(.pinchIn)])
        #expect(updates.first == .started(.pinchIn), "a dead-zone sample was reported")
        let progress = updates.compactMap { if case .progress(.pinchIn, let p) = $0 { p } else { nil } }
        #expect(progress.count >= 9)
        #expect(zip(progress, progress.dropFirst()).allSatisfy { $0 <= $1 }, "progress is not monotonic")
        let release = try #require(releases(updates).first)
        #expect(releases(updates).count == 1)
        #expect(release.direction == .pinchIn && release.passedThreshold && !release.tooSmall && !release.endedByTimeout)
        #expect(abs(release.progress - log(2.1) / log(2)) < 1e-9)
        #expect(recognizer.follow(hasTarget: true).t == 1)
        #expect(recognizer.isFinished)
    }

    @Test func aPinchInsideTheDeadZoneIsTooSmall() {
        let (_, updates) = run([pinch(0, 1, 0.01), pinch(0.02, 2, 0.01), pinch(0.04, 4, 0)], kind: .pinch)

        #expect(!updates.contains { if case .started = $0 { true } else { false } })
        let release = releases(updates).first
        #expect(updates.count == 1 && release?.tooSmall == true && release?.passedThreshold == false)
    }

    @Test func samplesAfterTheEndAreIgnored() throws {
        var recognizer = GestureRecognizer(kind: .pinch, viewSize: screen)
        for sample in try trace("pinch-in-commit.jsonl") { _ = recognizer.feed(sample) }

        #expect(recognizer.feed(pinch(0.3, 2, 0.5)) == nil)
        #expect(recognizer.timeout(now: 10) == nil)
    }

    @Test func malformedMagnificationCannotPoisonProgress() {
        let (recognizer, updates) = run(
            [pinch(0, 1, .nan), pinch(0.01, 2, .infinity), pinch(0.02, 2, -50), pinch(0.03, 2, -50), pinch(0.04, 4, 0)], kind: .pinch)

        let release = releases(updates).first
        #expect(release?.progress.isFinite == true && release?.direction == .pinchOut)
        let follow = recognizer.follow(hasTarget: false)
        #expect(follow.overscrollScale.isFinite && follow.overscrollScale > 0)
    }
}

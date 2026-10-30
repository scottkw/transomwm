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

private func pan(_ t: Double, _ phase: Int, _ dx: Double, _ dy: Double = 0, momentum: Int = 0) -> GestureRecognizer.Sample {
    GestureRecognizer.Sample(t: t, kind: .pan, phase: phase, momentum: momentum, dx: dx, dy: dy)
}

/// A slow pan: began, then `steps` changed samples `interval` apart, each `dx`; the last sample's t is `steps · interval`.
private func slowPan(dx: Double, steps: Int, interval: Double) -> [GestureRecognizer.Sample] {
    [pan(0, 1, dx)] + (1...steps).map { pan(Double($0) * interval, 2, dx) }
}

private func starts(_ updates: [GestureRecognizer.Update]) -> [GestureRecognizer.Direction] {
    updates.compactMap { if case .started(let direction) = $0 { direction } else { nil } }
}

private let recordedTraces: [String] =
    ((try? FileManager.default.contentsOfDirectory(atPath: traceDirectory.path)) ?? [])
    .filter { $0.hasPrefix("recorded-") && $0.hasSuffix(".jsonl") && !$0.contains("noise") }.sorted()

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

    @Test func aPanPastAThirdCommitsAndMomentumChangesNothing() throws {
        let samples = try trace("pan-left-third.jsonl")
        let (_, updates) = run(samples, kind: .pan)

        #expect(starts(updates) == [.pan(.right)])
        let release = try #require(releases(updates).first)
        #expect(releases(updates).count == 1)
        #expect(release.direction == .pan(.right) && release.passedThreshold && !release.byFlick)
        #expect(abs(release.progress - 500.0 / 1440) < 1e-9)
        let (_, early) = run(Array(samples.prefix { $0.momentum == 0 }), kind: .pan)
        #expect(releases(early) == [release], "the momentum changed the release")
    }

    @Test func aSlowShortPanSpringsBack() throws {
        var recognizer = GestureRecognizer(kind: .pan, viewSize: screen)
        for sample in slowPan(dx: -10, steps: 19, interval: 0.1) { _ = recognizer.feed(sample) }

        #expect(recognizer.feed(pan(1.9, 4, 0)) == nil, "short of the threshold, fingers-up waits for momentum")
        #expect(recognizer.timeout(now: 1.95) == nil)
        guard case .ended(let release)? = recognizer.timeout(now: 1.9 + GestureTuning.momentumWait + 0.001) else {
            Issue.record("no release after the momentum wait")
            return
        }
        #expect(abs(release.progress - 200.0 / 1440) < 1e-9)
        #expect(!release.passedThreshold && !release.endedByTimeout)
    }

    @Test func aFastShortPanFlicks() throws {
        let release = try #require(releases(run(try trace("pan-flick.jsonl"), kind: .pan).1).first)
        #expect(release.direction == .pan(.right) && release.passedThreshold && release.byFlick)

        let tiny = [pan(0, 1, -10), pan(0.005, 2, -10), pan(0.01, 4, 0)]  // 2000 pt/s, but only 20 pt
        var recognizer = GestureRecognizer(kind: .pan, viewSize: screen)
        let updates = tiny.compactMap { recognizer.feed($0) } + [recognizer.timeout(now: 0.1)].compactMap { $0 }
        #expect(releases(updates).count == 1 && releases(updates).first?.passedThreshold == false)
    }

    @Test func theFirstMomentumSampleCanCarryTheFlick() throws {
        var recognizer = GestureRecognizer(kind: .pan, viewSize: screen)
        for sample in [pan(0, 1, -10)] + (1...6).map({ pan(Double($0) * 0.05, 2, -5) }) { _ = recognizer.feed(sample) }  // 100 pt/s
        #expect(recognizer.feed(pan(0.31, 4, 0)) == nil)

        let update = recognizer.feed(pan(0.32, 0, -20, momentum: 1))  // 2000 pt/s

        guard case .ended(let release)? = update else {
            Issue.record("the momentum sample did not decide: \(String(describing: update))")
            return
        }
        #expect(release.direction == .pan(.right) && release.passedThreshold && release.byFlick)
        #expect(recognizer.feed(pan(0.34, 0, -20, momentum: 2)) == nil)
    }

    @Test func aReversedPanRetargetsAndTheOtherAxisIsIgnored() throws {
        let (_, updates) = run(try trace("pan-reverse.jsonl"), kind: .pan)

        #expect(starts(updates) == [.pan(.right)])
        let reversals = updates.compactMap { if case .reversed(let direction) = $0 { direction } else { nil } }
        #expect(reversals == [.pan(.left)])
        let directions = updates.compactMap { update -> GestureRecognizer.Direction? in
            switch update {
            case .started(let d), .progress(let d, _), .reversed(let d): d
            case .ended(let release): release.direction
            }
        }
        #expect(directions.allSatisfy { $0 == .pan(.right) || $0 == .pan(.left) }, "dy noise changed the axis")
        #expect(releases(updates).first?.direction == .pan(.left))
    }

    @Test func theAxisLocksOnlyWithADominantAxis() {
        var recognizer = GestureRecognizer(kind: .pan, viewSize: screen)
        #expect(recognizer.feed(pan(0, 1, 10, 9)) == nil, "|Σ| ≥ 12 but neither axis 1.5× the other")
        #expect(recognizer.feed(pan(0.01, 2, 8, -3)) == .started(.pan(.left)), "Σ 18, 6 locks horizontal")

        var fresh = GestureRecognizer(kind: .pan, viewSize: screen)
        #expect(fresh.feed(pan(0, 1, 18, 6)) == .started(.pan(.left)))
    }

    @Test(arguments: [
        (-20.0, 0.0, Edge.right), (20.0, 0.0, Edge.left), (0.0, -20.0, Edge.bottom), (0.0, 20.0, Edge.top),
    ])
    func panDirectionsFollowNaturalScrolling(dx: Double, dy: Double, edge: Edge) {
        var recognizer = GestureRecognizer(kind: .pan, viewSize: screen)
        #expect(recognizer.feed(pan(0, 1, dx, dy)) == .started(.pan(edge)))
    }

    @Test func panOverscrollUsesTheResistanceCurve() {
        let third = 1440.0 / 3
        var refused = GestureRecognizer(kind: .pan, viewSize: screen)
        _ = refused.feed(pan(0, 1, -third))
        let atHome = refused.follow(hasTarget: false)
        #expect(atHome.t == 0 && atHome.overscrollScale == 1)
        #expect(abs(atHome.overscrollOffset + GestureRecognizer.overscroll(third, limit: 1440)) < 1e-9)
        #expect(abs(atHome.overscrollOffset / 1440 + 0.155) < 0.001, "a third of the display shows ≈ 0.155 W")

        var far = GestureRecognizer(kind: .pan, viewSize: screen)
        _ = far.feed(pan(0, 1, 1.5 * 1440))
        let past = far.follow(hasTarget: true)
        #expect(past.t == 1)
        #expect(abs(past.overscrollOffset - GestureRecognizer.overscroll(0.5 * 1440, limit: 1440)) < 1e-9)
    }

    @Test func pinchOverscrollStaysUnderAQuarterLevel() {
        var refused = GestureRecognizer(kind: .pinch, viewSize: screen)
        for (i, m) in [0.5, 0.5].enumerated() { _ = refused.feed(pinch(Double(i) * 0.02, i == 0 ? 1 : 2, m)) }  // s = 2, p = 1
        let none = refused.follow(hasTarget: false)
        #expect(none.t == 0 && none.overscrollOffset == 0)
        #expect(abs(none.overscrollScale - pow(2, GestureRecognizer.overscroll(1, limit: 0.25))) < 1e-9)
        #expect(none.overscrollScale > 1 && none.overscrollScale < 1.19)

        var far = GestureRecognizer(kind: .pinch, viewSize: screen)
        for i in 0..<6 { _ = far.feed(pinch(Double(i) * 0.02, i == 0 ? 1 : 2, 1)) }  // s = 7, p ≈ 2.8
        let past = far.follow(hasTarget: true)
        #expect(past.t == 1 && past.overscrollScale > 1 && past.overscrollScale <= 1.19)

        var out = GestureRecognizer(kind: .pinch, viewSize: screen)
        _ = out.feed(pinch(0, 1, -0.5))
        let shrink = out.follow(hasTarget: false)
        #expect(shrink.overscrollScale < 1 && shrink.overscrollScale >= 0.84)
    }

    @Test func aShortPinchOutSpringsBack() throws {
        let (_, updates) = run(try trace("pinch-out-short.jsonl"), kind: .pinch)

        #expect(starts(updates) == [.pinchOut])
        let release = try #require(releases(updates).first)
        #expect(release.direction == .pinchOut && !release.passedThreshold && !release.tooSmall)
    }

    @Test func timeoutsEndEveryGesture() {
        var down = GestureRecognizer(kind: .pan, viewSize: screen)
        for sample in [pan(0, 1, -20), pan(1.0, 2, -20)] { _ = down.feed(sample) }
        #expect(down.timeout(now: 2.9) == nil)
        guard case .ended(let held)? = down.timeout(now: 3.01) else {
            Issue.record("fingers down for 2 s did not end")
            return
        }
        #expect(held.endedByTimeout && !held.passedThreshold)

        var up = GestureRecognizer(kind: .pan, viewSize: screen)
        for sample in [pan(0, 1, -20), pan(0.5, 2, -20), pan(1.0, 4, 0)] { _ = up.feed(sample) }
        guard case .ended(let lifted)? = up.timeout(now: 1.31) else {
            Issue.record("fingers up and 0.3 s quiet did not end")
            return
        }
        #expect(lifted.endedByTimeout)
        #expect(up.timeout(now: 9) == nil && up.isFinished)
    }

    /// Spike C2: real trackpads start pinches with a 128 (mayBegin) → 8 (cancelled) scroll pair carrying no delta.
    @Test func aMayBeginCancelPanWithNoMotionIsNoGesture() throws {
        for samples in [try trace("recorded-pan-noise.jsonl"), [pan(0, 128, 0), pan(0.2, 8, 0)]] {
            var recognizer = GestureRecognizer(kind: .pan, viewSize: screen)
            #expect(samples.compactMap { recognizer.feed($0) }.isEmpty)
            #expect(recognizer.isFinished && recognizer.timeout(now: 10) == nil)
        }
        var silent = GestureRecognizer(kind: .pan, viewSize: screen)
        #expect(silent.feed(pan(0, 128, 0)) == nil)
        #expect(silent.timeout(now: 2.01) == nil && silent.isFinished, "a lone mayBegin times out as no gesture")
    }

    /// One recognizer for every source (assumption delta): the same pinch, decoded or built, gives the same release.
    @Test func theSamePinchGivesTheSameReleaseWhoeverBuiltIt() throws {
        let decoded = try trace("pinch-in-commit.jsonl")
        let built = decoded.map { GestureRecognizer.Sample(t: $0.t, kind: .pinch, phase: $0.phase, magnification: $0.magnification) }
        #expect(releases(run(decoded, kind: .pinch).1) == releases(run(built, kind: .pinch).1))
    }

    /// Built-in trackpad sequences from the spike's tap-listen runs (05-01), sample keys only.
    @Test(arguments: recordedTraces)
    func recordedSequencesEndOnceInTheirOwnDirection(file: String) throws {
        let samples = try trace(file)
        let kind = try #require(samples.first?.kind)
        var recognizer = GestureRecognizer(kind: kind, viewSize: screen)
        var updates = samples.compactMap { recognizer.feed($0) }
        if let late = recognizer.timeout(now: (samples.last?.t ?? 0) + GestureTuning.fingersUpTimeout) { updates.append(late) }

        #expect(releases(updates).count == 1, "\(file)")
        let release = try #require(releases(updates).first)
        let fingers = samples.filter { $0.momentum == 0 }
        let (m, dx, dy) = (fingers.map(\.magnification).reduce(0, +), fingers.map(\.dx).reduce(0, +), fingers.map(\.dy).reduce(0, +))
        switch release.direction {
        case .pinchIn?: #expect(m > 0, "\(file)")
        case .pinchOut?: #expect(m < 0, "\(file)")
        case .pan(.right)?: #expect(dx < 0, "\(file)")
        case .pan(.left)?: #expect(dx > 0, "\(file)")
        case .pan(.bottom)?: #expect(dy < 0, "\(file)")
        case .pan(.top)?: #expect(dy > 0, "\(file)")
        case nil: Issue.record("\(file) never started")
        }
    }
}

/// Two fingers at (x ± spread/2, y) on a 100 × 70 mm surface, both touching (state 4).
private func fingers(_ x: Double, _ y: Double, spread: Double) -> [TwoFingerTracker.Touch] {
    [.init(state: 4, x: x - spread / 2, y: y), .init(state: 4, x: x + spread / 2, y: y)]
}

private let trackpad = Size(width: 100, height: 70)

/// 05-07 TwoFingerTracker: multitouch frames feed the one recognizer (assumption-delta "promote").
extension GestureRecognizerTests {
    /// Invariant: one pinch from 0.2 to 0.4 apart as multitouch frames, and as tap samples summing to +1.0, give the same
    /// Release (s = 2, p = 1, past the threshold).
    @Test func aPinchGivesTheSameReleaseAsMultitouchFramesOrTapSamples() throws {
        var tracker = TwoFingerTracker(surface: trackpad)
        let spreads = [0.2, 0.25, 0.3, 0.35, 0.4]
        var frames = spreads.enumerated().flatMap { tracker.feed(t: Double($0.offset) * 0.1, touches: fingers(0.5, 0.5, spread: $0.element)) }
        frames += tracker.feed(t: 0.5, touches: [])
        let fromMultitouch = frames.filter { $0.kind == .pinch }
        #expect(abs(fromMultitouch.map(\.magnification).reduce(0, +) - 1.0) < 1e-9)

        let fromTap = [pinch(0, 1, 0)] + (1...4).map { pinch(Double($0) * 0.1, 2, 0.25) } + [pinch(0.5, 4, 0)]
        let mt = try #require(releases(run(fromMultitouch, kind: .pinch).1).first)
        let tap = try #require(releases(run(fromTap, kind: .pinch).1).first)
        #expect(mt.direction == .pinchIn)
        #expect(mt.passedThreshold)
        #expect(abs(mt.progress - 1) < 1e-9)
        #expect(mt.direction == tap.direction)
        #expect(mt.passedThreshold == tap.passedThreshold)
        #expect(mt.byFlick == tap.byFlick)
        #expect(mt.tooSmall == tap.tooSmall)
        #expect(abs(mt.progress - tap.progress) < 1e-9)
    }

    /// Two fingers moving together 40 mm left: Σdx = −40 mm in points, and the view shows the area to the right.
    @Test func twoFingersTranslatingTogetherArePanSamples() throws {
        var tracker = TwoFingerTracker(surface: trackpad)
        var samples: [GestureRecognizer.Sample] = []
        for step in 0...4 { samples += tracker.feed(t: Double(step) * 0.1, touches: fingers(0.6 - Double(step) * 0.1, 0.5, spread: 0.1)) }
        samples += tracker.feed(t: 0.5, touches: [])
        let pans = samples.filter { $0.kind == .pan }
        let expected: Double = -40 * TwoFingerTracker.pointsPerMM
        let sumX: Double = pans.map(\.dx).reduce(0, +)
        #expect(abs(sumX - expected) < 1e-9)
        #expect(abs(TwoFingerTracker.pointsPerMM - 72 / 25.4) < 1e-12)
        #expect(abs(pans.map(\.dy).reduce(0, +)) < 1e-9)
        #expect(pans.map(\.phase) == [1, 2, 2, 2, 2, 4])
        var (recognizer, updates) = run(pans, kind: .pan)
        if let late = recognizer.timeout(now: 1) { updates.append(late) }  // short of ⅓: the release waits for momentum
        let release = try #require(releases(updates).first)
        #expect(release.direction == .pan(.right))
        #expect(abs(samples.filter { $0.kind == .pinch }.map(\.magnification).reduce(0, +)) < 1e-9, "a pan does not pinch")
    }

    @Test(arguments: [
        [TwoFingerTracker.Touch(state: 4, x: 0.5, y: 0.5)],
        fingers(0.5, 0.5, spread: 0.2) + [.init(state: 4, x: 0.1, y: 0.1)],
        [.init(state: 5, x: 0.4, y: 0.5), .init(state: 7, x: 0.6, y: 0.5)],
    ])
    func oneFingerMoreThanTwoOrBothBreakingEndTheGesture(frame: [TwoFingerTracker.Touch]) {
        var tracker = TwoFingerTracker(surface: trackpad)
        #expect(tracker.feed(t: 0, touches: fingers(0.5, 0.5, spread: 0.2)).map(\.phase) == [1, 1])
        #expect(tracker.feed(t: 0.1, touches: fingers(0.5, 0.5, spread: 0.3)).map(\.phase) == [2, 2])
        #expect(tracker.feed(t: 0.2, touches: frame).map(\.phase) == [4, 4])
        #expect(!tracker.isTracking)
        #expect(tracker.feed(t: 0.3, touches: frame).isEmpty, "nothing more until two fingers are down again")
    }

    @Test func framesWithoutTwoFingersDownStartNothing() {
        var tracker = TwoFingerTracker(surface: trackpad)
        #expect(tracker.feed(t: 0, touches: []).isEmpty)
        #expect(tracker.feed(t: 0.1, touches: [.init(state: 4, x: 0.5, y: 0.5)]).isEmpty)
        #expect(tracker.feed(t: 0.2, touches: [.init(state: 2, x: 0.4, y: 0.5), .init(state: 2, x: 0.6, y: 0.5)]).isEmpty, "hovering")
    }
}

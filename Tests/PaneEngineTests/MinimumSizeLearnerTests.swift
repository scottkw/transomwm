import PaneEngine
import PaneModel
import Testing

private let window = WindowIdentity(windowID: 7, pid: 100, bundleID: "com.example.app")
private let t0 = ContinuousClock.now
private let later = t0 + MinimumSizeLearner.confirmDelay

private func rect(_ width: Double, _ height: Double) -> Rect {
    Rect(x: 100, y: 120, width: width, height: height)
}

private func size(_ width: Double, _ height: Double) -> Size {
    Size(width: width, height: height)
}

/// One write at `t0`, then one confirming refresh `confirmDelay` later that still sees the read-back size.
private func refuseAndConfirm(_ learner: inout MinimumSizeLearner, requested: Rect, actual: Rect) -> Size? {
    learner.recordWrite(window: window, requested: requested, actual: actual, at: t0)
    return learner.confirm(window: window, observed: actual.size, at: later)
}

/// D-13 (in-memory half), WIN-04, lead decision 2026-10-25: a refusal more than 32 pt above the request,
/// confirmed by a refresh at least 1 s later that still sees the window there, teaches the minimum.
@Suite struct MinimumSizeLearnerTests {
    @Test func aRefusalConfirmedOneSecondLaterIsLearned() {
        var learner = MinimumSizeLearner()
        learner.recordWrite(window: window, requested: rect(100, 80), actual: rect(250, 150), at: t0)
        #expect(learner.minimum(for: window) == nil, "nothing is learned at write time")
        #expect(learner.awaitsConfirmation(window))
        #expect(learner.confirm(window: window, observed: size(250, 150), at: later) == size(250, 150))
        #expect(learner.minimum(for: window) == size(250, 150))
        #expect(!learner.awaitsConfirmation(window))
    }

    @Test func aRefreshTooSoonKeepsTheCandidateForALaterOne() {
        var learner = MinimumSizeLearner()
        learner.recordWrite(window: window, requested: rect(100, 80), actual: rect(250, 150), at: t0)
        #expect(learner.confirm(window: window, observed: size(250, 150), at: t0 + .milliseconds(999)) == nil)
        #expect(learner.awaitsConfirmation(window))
        #expect(learner.confirm(window: window, observed: size(250, 150), at: later) == size(250, 150))
    }

    @Test func exactlyThirtyTwoPointsOverIsNoCandidate() {
        var learner = MinimumSizeLearner()
        learner.recordWrite(window: window, requested: rect(100, 80), actual: rect(132, 112), at: t0)
        #expect(!learner.awaitsConfirmation(window))
        #expect(learner.confirm(window: window, observed: size(132, 112), at: later) == nil)
        #expect(learner.minimum(for: window) == nil)
    }

    @Test func justOverThirtyTwoPointsIsLearnedOnceConfirmed() {
        var learner = MinimumSizeLearner()
        #expect(refuseAndConfirm(&learner, requested: rect(100, 80), actual: rect(132.01, 80)) == size(132.01, 0))
    }

    @Test func aWindowSeenElsewhereAtConfirmTimeTeachesNothing() {
        var learner = MinimumSizeLearner()
        learner.recordWrite(window: window, requested: rect(100, 80), actual: rect(250, 150), at: t0)
        // The app applied the size late, or the user resized the window: it is no longer at the read-back size.
        #expect(learner.confirm(window: window, observed: size(252.5, 150), at: later) == nil)
        #expect(!learner.awaitsConfirmation(window), "the candidate is dropped")
        #expect(learner.confirm(window: window, observed: size(250, 150), at: later + .seconds(1)) == nil)
        #expect(learner.minimum(for: window) == nil)
    }

    @Test func withinTwoPointsAtConfirmTimeStillCounts() {
        var learner = MinimumSizeLearner()
        learner.recordWrite(window: window, requested: rect(100, 80), actual: rect(250, 150), at: t0)
        #expect(learner.confirm(window: window, observed: size(252, 148), at: later) == size(250, 150))
    }

    @Test func aNewerWriteReplacesTheCandidate() {
        var learner = MinimumSizeLearner()
        learner.recordWrite(window: window, requested: rect(100, 80), actual: rect(250, 150), at: t0)
        learner.recordWrite(window: window, requested: rect(100, 80), actual: rect(300, 200), at: t0 + .milliseconds(500))
        // One second after the first write, but not after the newer one.
        #expect(learner.confirm(window: window, observed: size(300, 200), at: later) == nil)
        #expect(learner.confirm(window: window, observed: size(300, 200), at: later + .milliseconds(500)) == size(300, 200))
    }

    @Test func aNewerHonouredWriteClearsThatAxis() {
        var learner = MinimumSizeLearner()
        learner.recordWrite(window: window, requested: rect(100, 80), actual: rect(250, 150), at: t0)
        // Width honoured now (within the margin), height still refused.
        learner.recordWrite(window: window, requested: rect(240, 80), actual: rect(250, 150), at: t0)
        #expect(learner.confirm(window: window, observed: size(250, 150), at: later) == size(0, 150))
        var honoured = MinimumSizeLearner()
        honoured.recordWrite(window: window, requested: rect(100, 80), actual: rect(250, 150), at: t0)
        honoured.recordWrite(window: window, requested: rect(400, 300), actual: rect(400, 300), at: t0)
        #expect(!honoured.awaitsConfirmation(window))
        #expect(honoured.confirm(window: window, observed: size(400, 300), at: later) == nil)
    }

    @Test func anAxisSmallerThanRequestedIsIgnored() {
        var learner = MinimumSizeLearner()
        // A terminal snapping to whole cells rounds down.
        #expect(refuseAndConfirm(&learner, requested: rect(500, 300), actual: rect(497, 293)) == nil)
        #expect(learner.minimum(for: window) == nil)
    }

    @Test func onlyTheAxisThatExceededTheMarginIsLearned() {
        var learner = MinimumSizeLearner()
        #expect(refuseAndConfirm(&learner, requested: rect(400, 80), actual: rect(420, 150)) == size(0, 150))
    }

    @Test(arguments: [Double.nan, .infinity, -.infinity, Geometry.maxCoordinate + 1])
    func aNonFiniteOrOutOfRangeValueIsIgnored(bad: Double) {
        var learner = MinimumSizeLearner()
        #expect(refuseAndConfirm(&learner, requested: rect(100, 80), actual: rect(bad, 150)) == nil)
        #expect(refuseAndConfirm(&learner, requested: rect(bad, 80), actual: rect(250, 150)) == nil)
        #expect(refuseAndConfirm(&learner, requested: rect(100, 80), actual: Rect(x: bad, y: 0, width: 250, height: 150)) == nil)
        learner.recordWrite(window: window, requested: rect(100, 80), actual: rect(250, 150), at: t0)
        #expect(learner.confirm(window: window, observed: size(bad, 150), at: later) == nil)
        #expect(learner.minimum(for: window) == nil)
    }

    @Test func learnedValuesOnlyGrow() {
        var learner = MinimumSizeLearner()
        _ = refuseAndConfirm(&learner, requested: rect(100, 80), actual: rect(250, 150))
        #expect(refuseAndConfirm(&learner, requested: rect(100, 80), actual: rect(300, 200)) == size(300, 200))
        #expect(refuseAndConfirm(&learner, requested: rect(100, 80), actual: rect(260, 160)) == nil)
        #expect(learner.minimum(for: window) == size(300, 200))
    }

    @Test func forgetDropsTheMinimumAndTheCandidate() {
        var learner = MinimumSizeLearner()
        _ = refuseAndConfirm(&learner, requested: rect(100, 80), actual: rect(250, 150))
        learner.recordWrite(window: window, requested: rect(100, 80), actual: rect(300, 200), at: t0)
        learner.forget(window)
        #expect(learner.minimum(for: window) == nil)
        #expect(!learner.awaitsConfirmation(window))
        #expect(learner.confirm(window: window, observed: size(300, 200), at: later) == nil, "the candidate went too")
    }
}

import PaneEngine
import PaneModel
import Testing

private let window = WindowIdentity(windowID: 7, pid: 100, bundleID: "com.example.app")

private func rect(_ width: Double, _ height: Double) -> Rect {
    Rect(x: 100, y: 120, width: width, height: height)
}

/// Two writes with the same request and read-back: the second confirms the first.
private func learnTwice(_ learner: inout MinimumSizeLearner, requested: Rect, actual: Rect) -> Size? {
    _ = learner.learn(window: window, requested: requested, actual: actual)
    return learner.learn(window: window, requested: requested, actual: actual)
}

/// D-13 (in-memory half), WIN-04: learning an app's real minimum from what it did with a smaller request.
@Suite struct MinimumSizeLearnerTests {
    @Test func aRefusedSizeIsLearnedOnceASecondWriteAgreesAndAnHonouredOneChangesNothing() {
        var learner = MinimumSizeLearner()
        #expect(learner.learn(window: window, requested: rect(100, 80), actual: rect(250, 150)) == nil)
        #expect(learner.minimum(for: window) == nil, "one read-back is not enough")
        #expect(learner.learn(window: window, requested: rect(120, 90), actual: rect(251, 149)) == Size(width: 251, height: 149))
        #expect(learner.learn(window: window, requested: rect(300, 200), actual: rect(300, 200)) == nil)
        #expect(learner.minimum(for: window) == Size(width: 251, height: 149))
    }

    @Test func aStaleReadBackThatTheNextWriteContradictsTeachesNothing() {
        var learner = MinimumSizeLearner()
        // The app applied the size after the read-back: the old, larger frame came back once.
        #expect(learner.learn(window: window, requested: rect(400, 300), actual: rect(800, 600)) == nil)
        #expect(learner.learn(window: window, requested: rect(400, 300), actual: rect(400, 300)) == nil)
        #expect(learner.learn(window: window, requested: rect(400, 300), actual: rect(800, 600)) == nil)
        #expect(learner.minimum(for: window) == nil)
    }

    @Test func twoRefusalsThatDisagreeTeachNothing() {
        var learner = MinimumSizeLearner()
        #expect(learner.learn(window: window, requested: rect(100, 80), actual: rect(250, 150)) == nil)
        #expect(learner.learn(window: window, requested: rect(100, 80), actual: rect(300, 200)) == nil)
        #expect(learner.minimum(for: window) == nil)
    }

    @Test func exactlyTwoPointsOverIsWithinTolerance() {
        var learner = MinimumSizeLearner()
        #expect(learnTwice(&learner, requested: rect(100, 80), actual: rect(102, 80)) == nil)
        #expect(learner.minimum(for: window) == nil)
    }

    @Test func twoPointZeroOneOverIsLearned() {
        var learner = MinimumSizeLearner()
        #expect(learnTwice(&learner, requested: rect(100, 80), actual: rect(102.01, 80)) == Size(width: 102.01, height: 0))
    }

    @Test func anAxisSmallerThanRequestedIsIgnored() {
        var learner = MinimumSizeLearner()
        // A terminal snapping to whole cells rounds down.
        #expect(learnTwice(&learner, requested: rect(500, 300), actual: rect(497, 293)) == nil)
        #expect(learner.minimum(for: window) == nil)
    }

    @Test func onlyTheAxisThatExceededIsLearned() {
        var learner = MinimumSizeLearner()
        #expect(learnTwice(&learner, requested: rect(400, 80), actual: rect(400, 150)) == Size(width: 0, height: 150))
    }

    @Test(arguments: [Double.nan, .infinity, -.infinity, Geometry.maxCoordinate + 1])
    func aNonFiniteOrOutOfRangeReadBackIsIgnored(bad: Double) {
        var learner = MinimumSizeLearner()
        #expect(learnTwice(&learner, requested: rect(100, 80), actual: rect(bad, 150)) == nil)
        #expect(learnTwice(&learner, requested: rect(100, 80), actual: Rect(x: bad, y: 0, width: 250, height: 150)) == nil)
        #expect(learner.minimum(for: window) == nil)
    }

    @Test func learnedValuesOnlyGrow() {
        var learner = MinimumSizeLearner()
        _ = learnTwice(&learner, requested: rect(100, 80), actual: rect(250, 150))
        #expect(learnTwice(&learner, requested: rect(100, 80), actual: rect(300, 200)) == Size(width: 300, height: 200))
        #expect(learnTwice(&learner, requested: rect(100, 80), actual: rect(260, 160)) == nil)
        #expect(learner.minimum(for: window) == Size(width: 300, height: 200))
    }

    @Test func forgetDropsTheWindowsValues() {
        var learner = MinimumSizeLearner()
        _ = learnTwice(&learner, requested: rect(100, 80), actual: rect(250, 150))
        _ = learner.learn(window: window, requested: rect(100, 80), actual: rect(300, 200))
        learner.forget(window)
        #expect(learner.minimum(for: window) == nil)
        #expect(learner.learn(window: window, requested: rect(100, 80), actual: rect(300, 200)) == nil, "the unconfirmed refusal went too")
    }
}

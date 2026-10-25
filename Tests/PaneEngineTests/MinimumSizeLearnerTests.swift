import PaneEngine
import PaneModel
import Testing

private let window = WindowIdentity(windowID: 7, pid: 100, bundleID: "com.example.app")

private func rect(_ width: Double, _ height: Double) -> Rect {
    Rect(x: 100, y: 120, width: width, height: height)
}

/// D-13 (in-memory half), WIN-04: learning an app's real minimum from what it did with a smaller request.
@Suite struct MinimumSizeLearnerTests {
    @Test func aRefusedSizeIsLearnedAndAnHonouredOneChangesNothing() {
        var learner = MinimumSizeLearner()
        #expect(learner.learn(window: window, requested: rect(100, 80), actual: rect(250, 150)) == Size(width: 250, height: 150))
        #expect(learner.learn(window: window, requested: rect(300, 200), actual: rect(300, 200)) == nil)
        #expect(learner.minimum(for: window) == Size(width: 250, height: 150))
    }

    @Test func exactlyTwoPointsOverIsWithinTolerance() {
        var learner = MinimumSizeLearner()
        #expect(learner.learn(window: window, requested: rect(100, 80), actual: rect(102, 80)) == nil)
        #expect(learner.minimum(for: window) == nil)
    }

    @Test func twoPointZeroOneOverIsLearned() {
        var learner = MinimumSizeLearner()
        #expect(learner.learn(window: window, requested: rect(100, 80), actual: rect(102.01, 80)) == Size(width: 102.01, height: 0))
    }

    @Test func anAxisSmallerThanRequestedIsIgnored() {
        var learner = MinimumSizeLearner()
        // A terminal snapping to whole cells rounds down.
        #expect(learner.learn(window: window, requested: rect(500, 300), actual: rect(497, 293)) == nil)
        #expect(learner.minimum(for: window) == nil)
    }

    @Test func onlyTheAxisThatExceededIsLearned() {
        var learner = MinimumSizeLearner()
        #expect(learner.learn(window: window, requested: rect(400, 80), actual: rect(400, 150)) == Size(width: 0, height: 150))
    }

    @Test(arguments: [Double.nan, .infinity, -.infinity, Geometry.maxCoordinate + 1])
    func aNonFiniteOrOutOfRangeReadBackIsIgnored(bad: Double) {
        var learner = MinimumSizeLearner()
        #expect(learner.learn(window: window, requested: rect(100, 80), actual: rect(bad, 150)) == nil)
        #expect(learner.learn(window: window, requested: rect(100, 80), actual: Rect(x: bad, y: 0, width: 250, height: 150)) == nil)
        #expect(learner.minimum(for: window) == nil)
    }

    @Test func learnedValuesOnlyGrow() {
        var learner = MinimumSizeLearner()
        _ = learner.learn(window: window, requested: rect(100, 80), actual: rect(250, 150))
        #expect(learner.learn(window: window, requested: rect(100, 80), actual: rect(300, 200)) == Size(width: 300, height: 200))
        #expect(learner.learn(window: window, requested: rect(100, 80), actual: rect(260, 160)) == nil)
        #expect(learner.minimum(for: window) == Size(width: 300, height: 200))
    }

    @Test func forgetDropsTheWindowsValues() {
        var learner = MinimumSizeLearner()
        _ = learner.learn(window: window, requested: rect(100, 80), actual: rect(250, 150))
        learner.forget(window)
        #expect(learner.minimum(for: window) == nil)
    }
}

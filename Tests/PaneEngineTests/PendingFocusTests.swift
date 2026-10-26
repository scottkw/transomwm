import PaneEngine
import PaneModel
import Testing

/// The keep/consume rule of `PendingFocus` (G-03-5): a focus hint survives until its window is tracked.
@Suite struct PendingFocusTests {
    private func info(_ id: UInt32, pid: Int32 = 1, visible: UInt32? = nil) -> WindowInfo {
        WindowInfo(
            window: WindowRef(identity: WindowIdentity(windowID: id, pid: pid, bundleID: "com.apple.TextEdit")),
            frame: Rect(x: 0, y: 0, width: 100, height: 100), state: .present, displayUUID: "main", visibleMemberID: visible)
    }

    @Test func aHintForATrackedWindowResolvesAndIsConsumed() {
        var focus = PendingFocus()
        focus.hint(pid: 1, windowID: 8)
        #expect(focus.resolve(pid: 1, mainID: nil, windows: [info(8)]) == info(8).window)
        #expect(focus.resolve(pid: 1, mainID: nil, windows: [info(8)]) == nil)
    }

    @Test func aHintForASettlingWindowIsKeptUntilItIsTracked() {
        var focus = PendingFocus()
        focus.hint(pid: 1, windowID: 8)
        #expect(focus.resolve(pid: 1, mainID: nil, windows: []) == nil)
        #expect(focus.resolve(pid: 1, mainID: nil, windows: [info(8)]) == info(8).window)
    }

    @Test func aHintWithNoIDResolvesThroughAXMain() {
        var focus = PendingFocus()
        focus.hint(pid: 1, windowID: nil)
        #expect(focus.resolve(pid: 1, mainID: nil, windows: [info(8)]) == nil)
        #expect(focus.resolve(pid: 1, mainID: 9, windows: [info(8)]) == nil)
        #expect(focus.resolve(pid: 1, mainID: 8, windows: [info(8)]) == info(8).window)
        #expect(focus.resolve(pid: 1, mainID: 8, windows: [info(8)]) == nil)
    }

    /// G-03-5: A was focused earlier; focus moves to new window B before B is cached or tracked.
    @Test func aSecondWindowOfTheAppBecomesFocusedOnceTracked() {
        var focus = PendingFocus()
        focus.hint(pid: 1, windowID: 1)
        #expect(focus.resolve(pid: 1, mainID: 1, windows: [info(1)]) == info(1).window)
        focus.hint(pid: 1, windowID: nil)
        #expect(focus.resolve(pid: 1, mainID: 2, windows: [info(1)]) == nil)
        #expect(focus.resolve(pid: 1, mainID: 2, windows: [info(1), info(2)]) == info(2).window)
    }

    @Test func aTabGroupMatchesThroughItsVisibleMember() {
        var focus = PendingFocus()
        focus.hint(pid: 1, windowID: 12)
        #expect(focus.resolve(pid: 1, mainID: nil, windows: [info(10, visible: 12)]) == info(10).window)
    }

    @Test func onlyTheSamePidMatches() {
        var focus = PendingFocus()
        focus.hint(pid: 1, windowID: 8)
        #expect(focus.resolve(pid: 1, mainID: nil, windows: [info(8, pid: 2)]) == nil)
        #expect(focus.resolve(pid: 2, mainID: nil, windows: [info(8, pid: 2)]) == nil)
    }

    @Test func aNewerHintReplacesTheOlder() {
        var focus = PendingFocus()
        focus.hint(pid: 1, windowID: 8)
        focus.hint(pid: 1, windowID: 9)
        #expect(focus.resolve(pid: 1, mainID: nil, windows: [info(8)]) == nil)
        #expect(focus.resolve(pid: 1, mainID: nil, windows: [info(8), info(9)]) == info(9).window)
    }

    @Test func rekeyMovesThePendingWindowID() {
        var focus = PendingFocus()
        focus.hint(pid: 1, windowID: 8)
        focus.rekey(pid: 1, from: 8, to: 20)
        #expect(focus.resolve(pid: 1, mainID: nil, windows: [info(8)]) == nil)
        #expect(focus.resolve(pid: 1, mainID: nil, windows: [info(20)]) == info(20).window)
    }

    @Test func forgetDropsThePidsHint() {
        var focus = PendingFocus()
        focus.hint(pid: 1, windowID: 8)
        focus.forget(pid: 1)
        #expect(focus.resolve(pid: 1, mainID: nil, windows: [info(8)]) == nil)
    }
}

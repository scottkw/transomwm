import TransomEngine
import TransomModel
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

    /// 07 UAT Bug 1: ⌘Tab, the Dock or `open -a` activate an app with no focus change when its focused window stays the
    /// same (a hidden tab); the activation resolves through AXMain like a no-ID hint.
    @Test func anActivationResolvesThroughAXMain() {
        var focus = PendingFocus()
        focus.activated(pid: 1)
        #expect(focus.resolve(pid: 1, mainID: nil, windows: [info(8)]) == nil)
        #expect(focus.resolve(pid: 1, mainID: 8, windows: [info(8)]) == info(8).window)
        #expect(focus.resolve(pid: 1, mainID: 8, windows: [info(8)]) == nil)
    }

    @Test func aPendingAXHintNamesTheWindowOverAnActivation() {
        var focus = PendingFocus()
        focus.hint(pid: 1, windowID: 9)
        focus.activated(pid: 1)
        #expect(focus.resolve(pid: 1, mainID: 8, windows: [info(8), info(9)]) == info(9).window)
        focus.activated(pid: 1)
        focus.hint(pid: 1, windowID: 9)
        #expect(focus.resolve(pid: 1, mainID: 8, windows: [info(8), info(9)], now: .now + .seconds(1)) == info(9).window)
    }

    /// The activation and the AX notice of one focus change make one `windowFocused`, whichever resolves first.
    @Test func anActivationAndAnAXHintOfTheSameWindowResolveOnce() {
        let t0 = ContinuousClock.now
        var focus = PendingFocus()
        focus.hint(pid: 1, windowID: 8)
        #expect(focus.resolve(pid: 1, mainID: 8, windows: [info(8)], now: t0) == info(8).window)
        focus.activated(pid: 1)
        #expect(focus.resolve(pid: 1, mainID: 8, windows: [info(8)], now: t0 + .milliseconds(100)) == nil)
        #expect(focus.resolve(pid: 1, mainID: 8, windows: [info(8)], now: t0 + .milliseconds(150)) == nil, "the duplicate was not consumed")

        var reverse = PendingFocus()
        reverse.activated(pid: 1)
        #expect(reverse.resolve(pid: 1, mainID: 8, windows: [info(8)], now: t0) == info(8).window)
        reverse.hint(pid: 1, windowID: 8)
        #expect(reverse.resolve(pid: 1, mainID: 8, windows: [info(8)], now: t0 + .milliseconds(100)) == nil)
    }

    /// Only a duplicate is dropped: the same window again after the window, or after another window was focused, resolves;
    /// two AX hints of one window resolve twice, as before.
    @Test func onlyAnImmediateRepeatAcrossActivationAndAXIsADuplicate() {
        let t0 = ContinuousClock.now
        var focus = PendingFocus()
        focus.hint(pid: 1, windowID: 8)
        _ = focus.resolve(pid: 1, mainID: nil, windows: [info(8)], now: t0)
        focus.activated(pid: 1)
        #expect(focus.resolve(pid: 1, mainID: 8, windows: [info(8)], now: t0 + PendingFocus.duplicateWindow) == info(8).window)

        focus.hint(pid: 2, windowID: 5)
        #expect(focus.resolve(pid: 2, mainID: nil, windows: [info(5, pid: 2)], now: t0 + .seconds(1)) == info(5, pid: 2).window)
        focus.activated(pid: 1)
        #expect(focus.resolve(pid: 1, mainID: 8, windows: [info(8)], now: t0 + .seconds(1) + .milliseconds(50)) == info(8).window)

        focus.hint(pid: 1, windowID: 8)
        #expect(focus.resolve(pid: 1, mainID: nil, windows: [info(8)], now: t0 + .seconds(3)) == info(8).window)
        focus.hint(pid: 1, windowID: 8)
        #expect(focus.resolve(pid: 1, mainID: nil, windows: [info(8)], now: t0 + .seconds(3) + .milliseconds(50)) == info(8).window)
    }

    /// An activation that never resolved (no tracked AXMain) goes when another app activates: it can no longer be right.
    @Test func anotherAppsActivationDropsAnUnresolvedOne() {
        var focus = PendingFocus()
        focus.activated(pid: 1)
        #expect(focus.resolve(pid: 1, mainID: nil, windows: [info(8)]) == nil)
        focus.activated(pid: 2)
        #expect(focus.resolve(pid: 1, mainID: 8, windows: [info(8)]) == nil)
        #expect(focus.resolve(pid: 2, mainID: 5, windows: [info(5, pid: 2)]) == info(5, pid: 2).window)
    }

    @Test func forgetDropsThePidsHint() {
        var focus = PendingFocus()
        focus.hint(pid: 1, windowID: 8)
        focus.forget(pid: 1)
        #expect(focus.resolve(pid: 1, mainID: nil, windows: [info(8)]) == nil)
    }
}

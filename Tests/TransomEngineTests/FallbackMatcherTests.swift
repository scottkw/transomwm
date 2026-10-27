import TransomEngine
import TransomModel
import Testing

private let pid: Int32 = 700
private let bundleID = "com.example.fallback"
private let frame = Rect(x: 40, y: 80, width: 320, height: 232)

private func cg(_ id: UInt32, _ bounds: Rect = frame, onScreen: Bool = true, layer: Int = 0, pid: Int32 = pid) -> CGWindowEntry {
    CGWindowEntry(windowID: id, pid: pid, bounds: bounds, layer: layer, onScreen: onScreen, alpha: 1)
}

private func match(
    _ cgWindows: [CGWindowEntry], title: String = "Doc", names: [UInt32: String] = [:], excluding: Set<UInt32> = []
) -> FallbackMatch {
    FallbackMatcher.match(pid: pid, frame: frame, title: title, cgWindows: cgWindows, cgNames: names, excluding: excluding)
}

private func identity(_ id: UInt32) -> WindowIdentity {
    WindowIdentity(windowID: id, pid: pid, bundleID: bundleID)
}

private let synthetic1 = WindowIdentity.syntheticIDBase | 1
private let synthetic2 = WindowIdentity.syntheticIDBase | 2

@Suite struct FallbackMatcherTests {
    @Test func oneSamePidWindowWithEqualBoundsIsTheMatch() {
        #expect(match([cg(10)]) == .cg(10))
    }

    @Test(arguments: [(1.0, FallbackMatch.cg(10)), (1.01, FallbackMatch.none)])
    func boundsMatchWithinOnePointOnEverySide(offset: Double, expected: FallbackMatch) {
        let shifted = Rect(x: frame.x + offset, y: frame.y, width: frame.width, height: frame.height)
        let taller = Rect(x: frame.x, y: frame.y, width: frame.width, height: frame.height + offset)
        #expect(match([cg(10, shifted)]) == expected)
        #expect(match([cg(10, taller)]) == expected)
    }

    @Test func anOnscreenCandidateBeatsAnOffscreenHiddenTab() {
        #expect(match([cg(10, onScreen: false), cg(11)]) == .cg(11))
    }

    @Test func twoIdenticalOnscreenWindowsWithoutNamesAreAmbiguous() {
        #expect(match([cg(10), cg(11)]) == .ambiguous)
        #expect(match([cg(10), cg(11)], names: [10: "", 11: ""]) == .ambiguous)
    }

    @Test func aMatchingCGNameNarrowsAnAmbiguousMatch() {
        #expect(match([cg(10), cg(11)], title: "Doc", names: [10: "Other", 11: "Doc"]) == .cg(11))
    }

    @Test func anIDAlreadyBoundToAnotherElementIsNeverACandidate() {
        #expect(match([cg(10), cg(11)], excluding: [10]) == .cg(11))
        #expect(match([cg(10)], excluding: [10]) == .none)
    }

    @Test func otherPidAndNonZeroLayerEntriesLoseToALayerZeroOne() {
        #expect(match([cg(9, pid: 8), cg(12, layer: 3), cg(10)]) == .cg(10))
        #expect(match([cg(9, pid: 8)]) == .none)
        // With no layer-0 candidate the other layer still matches.
        #expect(match([cg(12, layer: 3)]) == .cg(12))
    }

    @Test func aSyntheticWindowIsPresentWhileASamePidCGWindowHasItsBounds() {
        let presence = FallbackMatcher.syntheticPresence([(identity(synthetic1), frame)], cgWindows: [cg(11)])
        #expect(presence == [CGWindowEntry(windowID: synthetic1, pid: pid, bounds: frame, layer: 0, onScreen: true, alpha: 1)])
    }

    @Test func aSyntheticWindowWithNoSameBoundsCGWindowHasNoPresence() {
        let moved = Rect(x: 500, y: 80, width: 320, height: 232)
        #expect(FallbackMatcher.syntheticPresence([(identity(synthetic1), frame)], cgWindows: [cg(11, moved), cg(12, pid: 8)]).isEmpty)
    }

    @Test func nonSyntheticWindowsGetNoPresenceAndKeepTheirOwnCGEntry() {
        // 10 is a real ID bound to its own entry; it never vouches for the synthetic window.
        let tracked = [(identity: identity(10), frame: frame), (identity: identity(synthetic1), frame: frame)]
        #expect(FallbackMatcher.syntheticPresence(tracked, cgWindows: [cg(10)]).isEmpty)
    }

    @Test func eachCGWindowVouchesForOneSyntheticWindowInListedOrder() {
        // Two identical windows, one closed: the remaining CG window keeps only the first-listed one present.
        let tracked = [(identity: identity(synthetic2), frame: frame), (identity: identity(synthetic1), frame: frame)]
        let presence = FallbackMatcher.syntheticPresence(tracked, cgWindows: [cg(11)])
        #expect(presence.map(\.windowID) == [synthetic2])
        #expect(FallbackMatcher.syntheticPresence(tracked, cgWindows: [cg(11), cg(12)]).map(\.windowID) == [synthetic2, synthetic1])
    }
}

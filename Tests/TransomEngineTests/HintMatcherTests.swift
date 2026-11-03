import TransomEngine
import TransomModel
import Testing

private let bundleID = "com.example.hints"
private let savedPID: Int32 = 800
private let newPID: Int32 = 801
private let left = Rect(x: 0, y: 25, width: 720, height: 875)
private let right = Rect(x: 720, y: 25, width: 720, height: 875)

private func saved(_ id: UInt32, _ title: String = "", frame: Rect? = nil) -> HintMatcher.Saved {
    HintMatcher.Saved(ref: WindowRef(identity: WindowIdentity(windowID: id, pid: savedPID, bundleID: bundleID), titleHint: title), frame: frame)
}

private func candidate(_ id: UInt32, _ title: String = "", frame: Rect = Rect(x: 100, y: 100, width: 400, height: 300)) -> HintMatcher.Candidate {
    HintMatcher.Candidate(ref: WindowRef(identity: WindowIdentity(windowID: id, pid: newPID, bundleID: bundleID), titleHint: title), frame: frame)
}

/// Saved window ID → matched candidate window ID.
private func pairs(_ matches: [HintMatcher.Match]) -> [UInt32: UInt32] {
    Dictionary(uniqueKeysWithValues: matches.map { ($0.saved.windowID, $0.window.windowID) })
}

/// D-10: saved windows go back to returning windows of the same app by persisted hints, only at 40 or more, and a tie
/// matches neither.
@Suite struct HintMatcherTests {
    @Test func distinctTitlesMatchEachWindowToItsOwnTitle() {
        let result = HintMatcher.assign(saved: [saved(1, "Notes"), saved(2, "Plan")], candidates: [candidate(20, "Plan"), candidate(10, "Notes")])
        #expect(pairs(result.matches) == [1: 10, 2: 20])
        #expect(result.ties.isEmpty)
    }

    @Test func anExactTitlePairBeatsCreationOrder() {
        // Saved 1 and candidate 10 come first in order, but the titles say 1 is 20.
        let result = HintMatcher.assign(saved: [saved(1, "Plan"), saved(2, "Notes")], candidates: [candidate(10, "Notes"), candidate(20, "Plan")])
        #expect(pairs(result.matches) == [1: 20, 2: 10])
    }

    @Test func aSolePairMatchesWithNoTitle() {
        let result = HintMatcher.assign(saved: [saved(1)], candidates: [candidate(10)])
        #expect(pairs(result.matches) == [1: 10])
    }

    @Test func aTwoWayTieMatchesNeither() {
        let result = HintMatcher.assign(saved: [saved(1, "Untitled")], candidates: [candidate(10, "Untitled"), candidate(20, "Untitled")])
        #expect(result.matches.isEmpty)
        #expect(result.ties.map(\.saved) == [[saved(1).ref]])
        #expect(result.ties.map(\.candidates) == [[candidate(10).ref, candidate(20).ref]])
    }
}

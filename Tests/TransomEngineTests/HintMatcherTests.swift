import TransomEngine
import TransomModel
import Testing

private let bundleID = "com.example.hints"
private let savedPID: Int32 = 800
private let newPID: Int32 = 801
private let left = Rect(x: 0, y: 25, width: 720, height: 875)
private let right = Rect(x: 720, y: 25, width: 720, height: 875)

/// Off screen, where the camera parks a window (RESEARCH Pitfall 9).
private let parked = Rect(x: 20_000, y: 20_000, width: 400, height: 300)

private func saved(
    _ id: UInt32, _ title: String = "", frame: Rect? = nil, ax: String? = nil, order: UInt64 = 0, bundle: String = bundleID, desk: DeskKey? = nil
) -> HintMatcher.Saved {
    let identity = WindowIdentity(windowID: id, pid: savedPID, bundleID: bundle)
    return HintMatcher.Saved(ref: WindowRef(identity: identity, titleHint: title, axIdentifier: ax, creationOrder: order), frame: frame, desk: desk)
}

private func candidate(
    _ id: UInt32, _ title: String = "", frame: Rect = Rect(x: 100, y: 100, width: 400, height: 300), ax: String? = nil, order: UInt64 = 0,
    bundle: String = bundleID, display: String? = nil, spaces: Set<UInt64>? = nil
) -> HintMatcher.Candidate {
    let identity = WindowIdentity(windowID: id, pid: newPID, bundleID: bundle)
    return HintMatcher.Candidate(
        ref: WindowRef(identity: identity, titleHint: title, axIdentifier: ax, creationOrder: order), frame: frame, displayUUID: display, spaces: spaces)
}

private let spaceOne = DeskKey(displayUUID: "D", spaceID: 1)
private let spaceTwo = DeskKey(displayUUID: "D", spaceID: 2)

/// One case of the D-10 scoring table: saved windows, returning windows, the expected matches (saved ID → window ID)
/// and the expected ties (saved IDs, window IDs).
struct HintCase: Sendable, CustomTestStringConvertible {
    let name: String
    let saved: [HintMatcher.Saved]
    let candidates: [HintMatcher.Candidate]
    let matches: [UInt32: UInt32]
    var ties: [[UInt32]] = []
    var testDescription: String { name }
}

private let table: [HintCase] = [
    HintCase(
        name: "distinct titles each match their own",
        saved: [saved(1, "Notes", order: 1), saved(2, "Plan", order: 2)],
        candidates: [candidate(10, "Plan", order: 1), candidate(20, "Notes", order: 2)],
        matches: [1: 20, 2: 10]),
    HintCase(
        name: "identical titles told apart by frame",
        saved: [saved(1, "Untitled", frame: left, order: 1), saved(2, "Untitled", frame: right, order: 2)],
        candidates: [candidate(10, "Untitled", frame: right, order: 1), candidate(20, "Untitled", frame: left, order: 2)],
        matches: [1: 20, 2: 10]),
    HintCase(
        name: "identical in every signal is a tie",
        saved: [saved(1, "Untitled", frame: left, order: 5), saved(2, "Untitled", frame: left, order: 5)],
        candidates: [candidate(10, "Untitled", frame: left, order: 9), candidate(20, "Untitled", frame: left, order: 9)],
        matches: [:], ties: [[1, 2], [10, 20]]),
    HintCase(
        name: "a one-window app whose title changed is the sole pair",
        saved: [saved(1, "Draft", frame: left)], candidates: [candidate(10, "Final", frame: parked)],
        matches: [1: 10]),
    HintCase(
        name: "one window, empty title, parked frame: sole pair",
        saved: [saved(1, frame: left)], candidates: [candidate(10, frame: parked)],
        matches: [1: 10]),
    HintCase(
        name: "two windows, empty titles, parked frames: no match",
        saved: [saved(1, frame: left, order: 1), saved(2, frame: right, order: 2)],
        candidates: [candidate(10, frame: parked, order: 1), candidate(20, frame: parked, order: 2)],
        matches: [:]),
    HintCase(
        name: "conflicting AX identifiers with equal titles: no match",
        saved: [saved(1, "Doc", ax: "a", order: 1)],
        candidates: [candidate(10, "Doc", ax: "b", order: 1), candidate(20, "Other", order: 2)],
        matches: [:]),
    HintCase(
        name: "equal AX identifiers and frames match without titles",
        saved: [saved(1, frame: left, ax: "inspector", order: 1), saved(2, frame: right, ax: "main", order: 2)],
        candidates: [candidate(10, frame: right, ax: "main", order: 1), candidate(20, frame: left, ax: "inspector", order: 2)],
        matches: [1: 20, 2: 10]),
    HintCase(
        name: "a window of another bundle is never a candidate",
        saved: [saved(1, "Notes")], candidates: [candidate(10, "Notes", bundle: "com.example.other")],
        matches: [:]),
    HintCase(
        name: "three saved, two returning: one saved window left unmatched",
        saved: [saved(1, "A", order: 1), saved(2, "B", order: 2), saved(3, "C", order: 3)],
        candidates: [candidate(10, "A", order: 1), candidate(20, "B", order: 2)],
        matches: [1: 10, 2: 20]),
    HintCase(
        name: "an edited title alone is not enough",
        saved: [saved(1, "Doc.txt — Edited", order: 1), saved(2, "Notes", order: 2)],
        candidates: [candidate(10, "Plan", order: 1), candidate(20, "Doc.txt", order: 2)],
        matches: [:]),
    HintCase(
        name: "an edited title with a frame matches",
        saved: [saved(1, "Doc.txt — Edited", frame: left, order: 1), saved(2, "Notes", frame: right, order: 2)],
        candidates: [candidate(10, "Plan", order: 1), candidate(20, "Doc.txt", frame: left, order: 2)],
        matches: [1: 20]),
    HintCase(
        name: "an edited title as the sole pair matches",
        saved: [saved(1, "Doc.txt - Edited")], candidates: [candidate(10, " doc.TXT ")],
        matches: [1: 10]),
    HintCase(
        name: "a window on another Space never matches, even by its exact title",
        saved: [saved(1, "Notes", desk: spaceTwo)], candidates: [candidate(10, "Notes", display: "D", spaces: [1])],
        matches: [:]),
    HintCase(
        name: "a window on the desk's Space matches",
        saved: [saved(1, "Notes", desk: spaceTwo)], candidates: [candidate(10, "Notes", display: "D", spaces: [1, 2])],
        matches: [1: 10]),
    HintCase(
        name: "unknown Spaces, or none (a hidden tab), never rule a window out",
        saved: [saved(1, "A", desk: spaceTwo), saved(2, "B", desk: spaceTwo)],
        candidates: [candidate(10, "A", display: "D"), candidate(20, "B", display: "D", spaces: [])],
        matches: [1: 10, 2: 20]),
    HintCase(
        name: "the sole pair counts the windows that fit: one tile per Space, one window on the first",
        saved: [saved(1, desk: spaceOne), saved(2, desk: spaceTwo)], candidates: [candidate(10, display: "D", spaces: [1])],
        matches: [1: 10]),
    HintCase(
        name: "the sole pair counts the windows that fit: one tile, a window per Space",
        saved: [saved(1, desk: spaceTwo)], candidates: [candidate(10, display: "D", spaces: [1]), candidate(20, display: "D", spaces: [2])],
        matches: [1: 20]),
    HintCase(
        name: "a window on another display reaches a shown desk only",
        saved: [saved(1, "A", desk: DeskKey(displayUUID: "E", spaceID: 7)), saved(2, "B", desk: DeskKey(displayUUID: "E", spaceID: 8))],
        candidates: [candidate(10, "A", display: "D", spaces: [1]), candidate(20, "B", display: "D", spaces: [1])],
        matches: [1: 10]),
]

private let shown: Set<DeskKey> = [DeskKey(displayUUID: "E", spaceID: 7)]

/// Saved window ID → matched candidate window ID.
private func pairs(_ matches: [HintMatcher.Match]) -> [UInt32: UInt32] {
    Dictionary(uniqueKeysWithValues: matches.map { ($0.saved.windowID, $0.window.windowID) })
}

/// D-10: saved windows go back to returning windows of the same app by persisted hints, only at 40 or more, and a tie
/// matches neither.
@Suite struct HintMatcherTests {
    /// Every row, with the inputs in the given order and reversed: assignment never depends on input order.
    @Test(arguments: table)
    func theScoringTable(_ row: HintCase) {
        for (saved, candidates) in [(row.saved, row.candidates), (row.saved.reversed(), row.candidates.reversed())] {
            let result = HintMatcher.assign(saved: saved, candidates: candidates, shown: shown)
            #expect(pairs(result.matches) == row.matches)
            #expect(result.ties.flatMap { [$0.saved.map(\.windowID), $0.candidates.map(\.windowID)] } == row.ties)
        }
    }

    /// The locked weights, one signal at a time (frame bands by IoU: 0.9 and up, 0.5 up to 0.9, below 0.5).
    @Test func eachSignalScoresItsWeight() {
        func points(_ s: HintMatcher.Saved, _ c: HintMatcher.Candidate, sole: Bool = false, rank: Bool = false) -> Int {
            HintMatcher.score(s, c, solePair: sole, sameRank: rank)
        }
        let half = Rect(x: 360, y: 25, width: 720, height: 875)  // IoU with `left` is 1/3
        let most = Rect(x: 0, y: 25, width: 720, height: 600)  // IoU with `left` is about 0.69
        let close = Rect(x: 10, y: 25, width: 720, height: 875)  // IoU with `left` is about 0.97
        #expect(points(saved(1, "Doc"), candidate(10, "Doc")) == HintMatcher.exactTitle)
        #expect(points(saved(1, "Doc — Edited"), candidate(10, " doc ")) == HintMatcher.normalisedTitle)
        #expect(points(saved(1, ""), candidate(10, "")) == 0)
        #expect(points(saved(1, ax: "a"), candidate(10, ax: "a")) == HintMatcher.sameAXIdentifier)
        #expect(points(saved(1, ax: "a"), candidate(10, ax: "b")) == HintMatcher.differentAXIdentifier)
        #expect(points(saved(1, ax: "a"), candidate(10)) == 0)
        #expect(points(saved(1, frame: left), candidate(10, frame: close)) == HintMatcher.closeFrame)
        #expect(points(saved(1, frame: left), candidate(10, frame: most)) == HintMatcher.overlappingFrame)
        #expect(points(saved(1, frame: left), candidate(10, frame: half)) == 0)
        #expect(points(saved(1), candidate(10, frame: left)) == 0, "an unknown saved frame scores nothing")
        #expect(points(saved(1), candidate(10), rank: true) == HintMatcher.sameRank)
        #expect(points(saved(1), candidate(10), sole: true) == HintMatcher.solePair)
        #expect(HintMatcher.threshold == 40)
    }

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

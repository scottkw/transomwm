import TransomModel

/// Re-matches saved windows to returning windows of the same app when their IDs changed (an app or Transom relaunch,
/// D-10, VIEW-04): integer scores from the persisted hints, a threshold, and a tie that matches neither, so a window
/// is never put in another window's tile on a guess.
public enum HintMatcher {
    /// Both titles non-empty and equal.
    public static let exactTitle = 50
    /// Exactly one unmatched saved window and one unclaimed candidate of the bundle.
    public static let solePair = 40
    /// The lowest score that matches.
    public static let threshold = 40

    /// A saved window and the frame it was last given (its home-view tile, or its floating frame); nil when unknown.
    public struct Saved: Equatable, Sendable {
        public var ref: WindowRef
        public var frame: Rect?

        public init(ref: WindowRef, frame: Rect?) {
            self.ref = ref
            self.frame = frame
        }
    }

    /// A returning window no saved window holds yet, at its current frame.
    public struct Candidate: Equatable, Sendable {
        public var ref: WindowRef
        public var frame: Rect

        public init(ref: WindowRef, frame: Rect) {
            self.ref = ref
            self.frame = frame
        }
    }

    public struct Match: Equatable, Sendable {
        public var saved: WindowRef
        public var window: WindowRef
        public var score: Int

        public init(saved: WindowRef, window: WindowRef, score: Int) {
            self.saved = saved
            self.window = window
            self.score = score
        }
    }

    /// Equal best scores sharing a saved window or a candidate: none of these saved windows or candidates is matched.
    public struct Tie: Equatable, Sendable {
        public var score: Int
        public var saved: [WindowRef]
        public var candidates: [WindowRef]

        public init(score: Int, saved: [WindowRef], candidates: [WindowRef]) {
            self.score = score
            self.saved = saved
            self.candidates = candidates
        }
    }

    public static func score(_ saved: Saved, _ candidate: Candidate, solePair sole: Bool) -> Int {
        var score = 0
        if !saved.ref.titleHint.isEmpty, saved.ref.titleHint == candidate.ref.titleHint { score += exactTitle }
        if sole { score += solePair }
        return score
    }

    /// Per bundle: every pair at or above `threshold`, then repeatedly the best remaining pair, unless another remaining
    /// pair with the same score shares its saved window or candidate; then all of those pairs' windows are a tie and
    /// leave the pool. Deterministic for any input order: equal scores are taken in identity order.
    public static func assign(saved: [Saved], candidates: [Candidate]) -> (matches: [Match], ties: [Tie]) {
        var matches: [Match] = []
        var ties: [Tie] = []
        let bundles = Set(saved.map(\.ref.bundleID)).intersection(candidates.map(\.ref.bundleID))
        for bundle in bundles.sorted() {
            let s = saved.filter { $0.ref.bundleID == bundle }.sorted { $0.ref.identity < $1.ref.identity }
            let c = candidates.filter { $0.ref.bundleID == bundle }.sorted { $0.ref.identity < $1.ref.identity }
            let sole = s.count == 1 && c.count == 1
            var pairs: [Match] = []
            for one in s {
                for other in c {
                    let points = score(one, other, solePair: sole)
                    if points >= threshold { pairs.append(Match(saved: one.ref, window: other.ref, score: points)) }
                }
            }
            // Highest score first; equal scores in the identity order the pairs were built in.
            pairs = pairs.enumerated().sorted { ($1.element.score, $0.offset) < ($0.element.score, $1.offset) }.map(\.element)
            while let best = pairs.first {
                let tied = pairs.filter { $0.score == best.score && ($0.saved == best.saved || $0.window == best.window) }
                if tied.count == 1 {
                    matches.append(best)
                    pairs.removeAll { $0.saved == best.saved || $0.window == best.window }
                } else {
                    let tiedSaved = Set(tied.map(\.saved)), tiedWindows = Set(tied.map(\.window))
                    ties.append(Tie(
                        score: best.score, saved: tiedSaved.sorted { $0.identity < $1.identity },
                        candidates: tiedWindows.sorted { $0.identity < $1.identity }))
                    pairs.removeAll { tiedSaved.contains($0.saved) || tiedWindows.contains($0.window) }
                }
            }
        }
        return (matches, ties)
    }
}

import Foundation
import TransomModel

/// Re-matches saved windows to returning windows of the same app when their IDs changed (an app or Transom relaunch,
/// D-10, VIEW-04): integer scores from the persisted hints, a threshold, and a tie that matches neither, so a window
/// is never put in another window's tile on a guess.
public enum HintMatcher {
    /// Both titles non-empty and equal.
    public static let exactTitle = 50
    /// Both titles non-empty and equal only after `normalised` (instead of `exactTitle`).
    public static let normalisedTitle = 30
    /// Both AX identifiers known and equal.
    public static let sameAXIdentifier = 15
    /// Both AX identifiers known and different.
    public static let differentAXIdentifier = -30
    /// The saved frame and the window's frame overlap with IoU ≥ `closeIoU`.
    public static let closeFrame = 25
    /// IoU ≥ `overlapIoU` and below `closeIoU`.
    public static let overlappingFrame = 10
    public static let closeIoU = 0.9
    public static let overlapIoU = 0.5
    /// The same rank of `creationOrder` within the bundle (`WindowTracker`'s order is session-global).
    public static let sameRank = 10
    /// Exactly one unmatched saved window and one unclaimed candidate of the bundle, with no title against it: the saved
    /// window has none, or the candidate's agrees, or else the frames overlap (a one-window app whose title changed, but
    /// not its Welcome or sign-in window, or a window whose title has yet to come; WR-03).
    public static let solePair = 40
    /// The lowest score that matches.
    public static let threshold = 40

    /// A saved window and the frame it was last given (its home-view tile, or its floating frame); nil when unknown.
    public struct Saved: Equatable, Sendable {
        public var ref: WindowRef
        public var frame: Rect?
        /// The desk holding it, which only a window that can be there may match (`canFill`); nil when unknown.
        public var desk: DeskKey?

        public init(ref: WindowRef, frame: Rect?, desk: DeskKey? = nil) {
            self.ref = ref
            self.frame = frame
            self.desk = desk
        }
    }

    /// A returning window no saved window holds yet, at its current frame.
    public struct Candidate: Equatable, Sendable {
        public var ref: WindowRef
        public var frame: Rect
        public var displayUUID: String?
        /// As `WindowInfo.spaces`: nil unknown, empty for a hidden tab.
        public var spaces: Set<UInt64>?

        public init(ref: WindowRef, frame: Rect, displayUUID: String? = nil, spaces: Set<UInt64>? = nil) {
            self.ref = ref
            self.frame = frame
            self.displayUUID = displayUUID
            self.spaces = spaces
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

    /// Whether `candidate` can be in `saved`'s tile (CR-03). A frame write can't move a window to another Space of its own
    /// display, so its known Spaces must hold the desk's, or `rehome` floats it and the tile is lost. On another display a
    /// write lands on the Space that display shows, so the desk must be showing (`shown`).
    static func canFill(_ saved: Saved, with candidate: Candidate, shown: Set<DeskKey>) -> Bool {
        guard let desk = saved.desk else { return true }
        if let display = candidate.displayUUID, display != desk.displayUUID { return shown.contains(desk) }
        guard let space = desk.spaceID, let spaces = candidate.spaces, !spaces.isEmpty else { return true }
        return spaces.contains(space)
    }

    public static func score(_ saved: Saved, _ candidate: Candidate, solePair sole: Bool, sameRank same: Bool) -> Int {
        var score = 0
        let a = saved.ref, b = candidate.ref
        var noTitleAgainst = a.titleHint.isEmpty
        if !a.titleHint.isEmpty, !b.titleHint.isEmpty {
            if a.titleHint == b.titleHint {
                score += exactTitle
                noTitleAgainst = true
            } else if normalised(a.titleHint) == normalised(b.titleHint) {
                score += normalisedTitle
                noTitleAgainst = true
            }
        }
        if let x = a.axIdentifier, let y = b.axIdentifier { score += x == y ? sameAXIdentifier : differentAXIdentifier }
        if let frame = saved.frame {
            let overlap = iou(frame, candidate.frame)
            score += overlap >= closeIoU ? closeFrame : overlap >= overlapIoU ? overlappingFrame : 0
            if overlap >= overlapIoU { noTitleAgainst = true }
        }
        if same { score += sameRank }
        if sole, noTitleAgainst { score += solePair }
        return score
    }

    /// Trimmed, case-folded, without a trailing " — Edited" or " - Edited" (the document-modified marker).
    static func normalised(_ title: String) -> String {
        var folded = title.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        for marker in [" — edited", " - edited"] where folded.hasSuffix(marker) { folded.removeLast(marker.count) }
        return folded.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Intersection over union; 0 when either rect has no area.
    private static func iou(_ a: Rect, _ b: Rect) -> Double {
        let width = max(0, min(a.maxX, b.maxX) - max(a.minX, b.minX)), height = max(0, min(a.maxY, b.maxY) - max(a.minY, b.minY))
        let intersection = width * height
        let union = a.width * a.height + b.width * b.height - intersection
        return union > 0 ? intersection / union : 0
    }

    /// Each window's rank among `refs` by `creationOrder`: the number with a smaller one, so equal orders share a rank
    /// and the result does not depend on input order.
    private static func ranks(_ refs: [WindowRef]) -> [WindowIdentity: Int] {
        Dictionary(uniqueKeysWithValues: refs.map { ref in (ref.identity, refs.count { $0.creationOrder < ref.creationOrder }) })
    }

    /// Per bundle: every pair that `canFill` and is at or above `threshold`, then repeatedly the best remaining pair, unless
    /// another remaining pair with the same score shares its saved window or candidate; then all of those pairs' windows are
    /// a tie and leave the pool. Deterministic for any input order: equal scores are taken in identity order. `shown` are the
    /// desks on screen.
    public static func assign(saved: [Saved], candidates: [Candidate], shown: Set<DeskKey> = []) -> (matches: [Match], ties: [Tie]) {
        var matches: [Match] = []
        var ties: [Tie] = []
        let bundles = Set(saved.map(\.ref.bundleID)).intersection(candidates.map(\.ref.bundleID))
        for bundle in bundles.sorted() {
            let s = saved.filter { $0.ref.bundleID == bundle }.sorted { $0.ref.identity < $1.ref.identity }
            let c = candidates.filter { $0.ref.bundleID == bundle }.sorted { $0.ref.identity < $1.ref.identity }
            let savedRanks = ranks(s.map(\.ref)), candidateRanks = ranks(c.map(\.ref))
            var pairs: [Match] = []
            for one in s {
                let fitting = c.filter { canFill(one, with: $0, shown: shown) }
                for other in fitting {
                    let sole = fitting.count == 1 && s.count { canFill($0, with: other, shown: shown) } == 1
                    let points = score(one, other, solePair: sole, sameRank: savedRanks[one.ref.identity] == candidateRanks[other.ref.identity])
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

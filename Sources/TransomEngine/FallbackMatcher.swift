import TransomModel

/// The outcome of matching one AX window to the CG window list without `_AXUIElementGetWindow`.
public enum FallbackMatch: Equatable, Sendable {
    case cg(UInt32), ambiguous, none
}

/// Window identity when the private window-ID lookup is unavailable (D-15, SAFE-05): the same-pid CG window whose
/// bounds equal the AX frame, or nothing when that is ambiguous, so the caller assigns a synthetic ID rather than guess.
public enum FallbackMatcher {
    public static let boundsTolerance: Double = 1.0

    /// Candidates are same-pid entries within `boundsTolerance` on every side and not in `excluding` (IDs already
    /// bound to other elements). Layer 0 beats other layers, a single onscreen one beats offscreen hidden tabs, and a
    /// non-empty CG name equal to `title` (readable only with Screen Recording) narrows what is left.
    public static func match(
        pid: Int32, frame: Rect, title: String, cgWindows: [CGWindowEntry], cgNames: [UInt32: String], excluding: Set<UInt32>
    ) -> FallbackMatch {
        var candidates = cgWindows.filter { $0.pid == pid && !excluding.contains($0.windowID) && matches($0.bounds, frame) }
        if candidates.contains(where: { $0.layer == 0 }) { candidates.removeAll { $0.layer != 0 } }
        let onScreen = candidates.filter(\.onScreen)
        if onScreen.count == 1 { return .cg(onScreen[0].windowID) }
        if candidates.count > 1, !title.isEmpty {
            let named = (onScreen.isEmpty ? candidates : onScreen).filter { cgNames[$0.windowID] == title }
            if named.count == 1 { return .cg(named[0].windowID) }
        }
        switch candidates.count {
        case 0: return .none
        case 1: return .cg(candidates[0].windowID)
        default: return .ambiguous
        }
    }

    /// CG presence for synthetic IDs, which no CG entry carries: a copy of a same-pid entry with the window's last-known
    /// bounds, re-labelled with the synthetic ID. Each entry vouches for at most one synthetic window, in `tracked`
    /// order (callers list windows AX still shows first), and never an entry whose ID a tracked window owns, so a closed
    /// twin of an identical window still closes.
    public static func syntheticPresence(_ tracked: [(identity: WindowIdentity, frame: Rect)], cgWindows: [CGWindowEntry]) -> [CGWindowEntry] {
        var claimed = Set(tracked.map(\.identity.windowID))
        var presence: [CGWindowEntry] = []
        for window in tracked where window.identity.isSyntheticWindowID {
            guard var entry = cgWindows.first(where: {
                $0.pid == window.identity.pid && !claimed.contains($0.windowID) && matches($0.bounds, window.frame)
            }) else { continue }
            claimed.insert(entry.windowID)
            entry.windowID = window.identity.windowID
            presence.append(entry)
        }
        return presence
    }

    private static func matches(_ a: Rect, _ b: Rect) -> Bool {
        abs(a.x - b.x) <= boundsTolerance && abs(a.y - b.y) <= boundsTolerance
            && abs(a.width - b.width) <= boundsTolerance && abs(a.height - b.height) <= boundsTolerance
    }
}

import ApplicationServices
import PaneEngine
import PaneModel
import PanePrivate

/// Window-ID resolution for one app (D-15, SAFE-05), owned by its `AXAppThread` and confined to that thread.
///
/// The element `_AXUIElementGetWindow` names owns that ID. A cached `.axPrivate` element keeps its ID with no lookup.
/// A cached fallback ID (frame match or synthetic) is looked up again on every resolve while the lookup works, and is
/// replaced when the answer differs; a holder whose ID another element's lookup claims is re-identified by frame.
/// So no two elements ever share an ID, and every change is reported as `replaces` for the tracker to re-key.
/// A lookup failure counts towards switching the capability off at most once per element while it stays listed, and
/// every real lookup that succeeds (new elements and re-checks) counts as a success; a cached `.axPrivate` element
/// does not, so a lookup that really broke mid-session still switches off. A new element whose lookup fails for the
/// first time never takes an offscreen-only frame match: it may be a same-frame twin on another Space or a hidden tab,
/// so the element waits one refresh (`identityPending`) for its own CG entry.
nonisolated struct WindowIDResolver {
    struct Item {
        let element: AXUIElement
        /// The batched read succeeded with role AXWindow: only such an element's lookup failure is unexpected.
        let isReadableWindow: Bool
        let frame: Rect?
        let title: String
    }

    struct Resolved: Equatable {
        let id: UInt32
        let source: WindowIDSource
        /// The ID the element was cached under, when this resolve changed it.
        let replaces: UInt32?
    }

    struct Resolution {
        /// Parallel to the items; nil means unidentified this pass.
        var ids: [Resolved?]
        var byID: [UInt32: CachedWindow]
        /// A new element waits one more refresh before the frame fallback may identify it.
        var identityPending: Bool
    }

    let pid: Int32
    /// Elements whose lookup failure was already counted; pruned to the listed elements on each resolve.
    private var failed: [AXUIElement] = []

    init(pid: Int32) {
        self.pid = pid
    }

    /// `lookup` nil means unavailable (forced fallback or capability off). `cgWindows` is called once, on first need;
    /// `cgNames` only for an ambiguous frame match.
    mutating func resolve(
        _ items: [Item], cache: [UInt32: CachedWindow], lookup: ((AXUIElement) -> UInt32?)?, session: CapabilitySession,
        cgWindows: () -> [CGWindowEntry]?, cgNames: () -> [UInt32: String]
    ) -> Resolution {
        failed.removeAll { element in !items.contains { CFEqual($0.element, element) } }
        let cached = items.map { item in cache.first { CFEqual($0.value.element, item.element) } }
        var ids = [Resolved?](repeating: nil, count: items.count)
        var firstFailure: Set<Int> = []

        // Pass 1: cached real IDs as they are, the lookup for everything else.
        for (i, item) in items.enumerated() {
            if let c = cached[i], c.value.source == .axPrivate {
                ids[i] = Resolved(id: c.key, source: .axPrivate, replaces: nil)
                continue
            }
            guard let lookup, session.isAvailable(.axWindowID) else { continue }
            if let id = lookup(item.element) {
                session.recordSuccess(.axWindowID)
                failed.removeAll { CFEqual($0, item.element) }
                ids[i] = Resolved(id: id, source: .axPrivate, replaces: cached[i].flatMap { $0.key == id ? nil : $0.key })
            } else if item.isReadableWindow, !failed.contains(where: { CFEqual($0, item.element) }) {
                // -25201 on a non-window (Finder's desktop) is expected; only a readable AXWindow counts.
                session.recordFailure(.axWindowID)
                failed.append(item.element)
                firstFailure.insert(i)
            }
        }

        // Pass 2: a cached fallback ID nobody claimed is kept; the rest go through the frame fallback.
        let claimed = Set(ids.compactMap { $0?.id })
        for i in items.indices where ids[i] == nil {
            if let c = cached[i], !claimed.contains(c.key) { ids[i] = Resolved(id: c.key, source: c.value.source, replaces: nil) }
        }
        var bound = Set(cache.keys).union(ids.compactMap { $0?.id })
        var snapshot: [CGWindowEntry]?
        var identityPending = false
        for (i, item) in items.enumerated() where ids[i] == nil {
            guard item.isReadableWindow, let frame = item.frame else { continue }
            // No CG list: leave the window unidentified this time rather than give it a synthetic ID.
            guard let cg = snapshot ?? cgWindows() else { continue }
            snapshot = cg
            var match = FallbackMatcher.match(pid: pid, frame: frame, title: item.title, cgWindows: cg, cgNames: [:], excluding: bound)
            if match == .ambiguous {
                // Names need Screen Recording; they decide this match only and are dropped with it (T-02-31).
                match = FallbackMatcher.match(pid: pid, frame: frame, title: item.title, cgWindows: cg, cgNames: cgNames(), excluding: bound)
            }
            let resolved: Resolved
            if case .cg(let id) = match {
                if cached[i] == nil, firstFailure.contains(i), cg.first(where: { $0.windowID == id })?.onScreen != true {
                    identityPending = true
                    continue
                }
                resolved = Resolved(id: id, source: .cgFrameMatch, replaces: cached[i]?.key)
            } else {
                let id = SyntheticWindowIDs.next(avoiding: Set(cg.map(\.windowID)).union(bound))
                resolved = Resolved(id: id, source: .synthetic, replaces: cached[i]?.key)
            }
            bound.insert(resolved.id)
            ids[i] = resolved
        }

        // Defensive: an ID already taken leaves the later element unidentified this pass.
        var byID: [UInt32: CachedWindow] = [:]
        for (i, item) in items.enumerated() {
            guard let resolved = ids[i] else { continue }
            guard byID[resolved.id] == nil else {
                ids[i] = nil
                continue
            }
            byID[resolved.id] = CachedWindow(element: item.element, source: resolved.source)
        }
        return Resolution(ids: ids, byID: byID, identityPending: identityPending)
    }
}

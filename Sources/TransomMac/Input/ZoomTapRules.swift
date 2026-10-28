import CoreGraphics

/// What the tap needs to decide zoom input, published whole from main (RESEARCH Pattern 7). Rects are global top-left
/// points, keyed by the CG window they show.
nonisolated struct ZoomTapState: Equatable, Sendable {
    /// Zoom on, Transom ready, not paused, no move or settle in progress.
    var armed = false
    /// The frames of displays whose shown Space has a desk (not a fullscreen Space): only there is a press taken.
    var deskDisplays: [CGRect] = []
    /// Docked windows' title bands, from the window's top edge down to its green button's bottom.
    var titleBars: [UInt32: CGRect] = [:]
    /// Pick mode's window tiles (Surface 5); nil when pick mode is off.
    var pickTiles: [UInt32: CGRect]?
    /// The `zoomTitleBarDoubleClick` preference.
    var titleBarDoubleClick = false
}

/// The tap's zoom rules (ZOOM-03, ZOOM-06, ZOOM-10, ZOOM-12). Pure, like `GreenButton`, so the callback stays a lookup.
nonisolated enum ZoomTapRules {
    /// The press being taken: a rubber band reports every event, a click only its mouse-down.
    enum Swallow: Equatable, Sendable { case none, band, click }
    enum Kind: Equatable, Sendable {
        case band
        case pick(UInt32)
        case titleBarDoubleClick(UInt32)
    }
    enum Decision: Equatable, Sendable {
        case pass
        /// Take the event; nil for the drags and release of a taken click, which report nothing.
        case consume(Kind?)
    }

    /// Carried in `eventSourceUserData` by Transom's own re-posted ⌘⇧-click, so the tap never takes it back ("TRNS").
    static let repostTag: Int64 = 0x5452_4E53

    private static let chordMask: CGEventFlags = [.maskCommand, .maskShift, .maskControl, .maskAlternate]

    /// Whether a mouse-down at `location` must know the topmost window (one CG list read): only inside a pick tile, or
    /// a title band on a double-click (Pitfall 9).
    static func needsWindow(location: CGPoint, clickState: Int64, state: ZoomTapState) -> Bool {
        guard state.armed else { return false }
        if state.pickTiles?.values.contains(where: { $0.contains(location) }) == true { return true }
        return clickState == 2 && state.titleBarDoubleClick && state.titleBars.values.contains { $0.contains(location) }
    }

    /// Whether the tap takes this event. Modifiers are read at mouse-down only, and a press is taken for exactly one
    /// press-release sequence: every mouse-down decides afresh, so a lost mouse-up can never trap the next click.
    static func decide(
        type: CGEventType, location: CGPoint, flags: CGEventFlags, clickState: Int64, windowID: UInt32, userData: Int64,
        state: ZoomTapState, swallow: inout Swallow
    ) -> Decision {
        if userData == repostTag { return .pass }
        switch type {
        case .leftMouseDown:
            swallow = .none
            guard state.armed, state.deskDisplays.contains(where: { $0.contains(location) }) else { return .pass }
            let chord = flags.intersection(chordMask)
            if chord == [.maskCommand, .maskShift] {
                swallow = .band
                return .consume(.band)
            }
            // Clicks are plain only; the window must be the one on top at the point, so a floater over a tile passes.
            guard chord.isEmpty, windowID != 0 else { return .pass }
            if state.pickTiles?[windowID]?.contains(location) == true {
                swallow = .click
                return .consume(.pick(windowID))
            }
            if clickState == 2, state.titleBarDoubleClick, state.titleBars[windowID]?.contains(location) == true {
                swallow = .click
                return .consume(.titleBarDoubleClick(windowID))
            }
            return .pass
        case .leftMouseDragged:
            return swallow == .band ? .consume(.band) : swallow == .click ? .consume(nil) : .pass
        case .leftMouseUp:
            defer { swallow = .none }
            return swallow == .band ? .consume(.band) : swallow == .click ? .consume(nil) : .pass
        default:
            return .pass
        }
    }
}

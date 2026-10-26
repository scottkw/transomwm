import PaneModel

/// The one command enum every route dispatches: hotkeys, menu items and (later) the URL scheme all call
/// `ArrangeController.dispatch(_:)`. Later plans add cases; never rename one.
public enum Command: Hashable, Sendable {
    case dock, float, undo
    /// Hide or show the Desktop tile of the focused window's desk (TILE-15).
    case toggleDesktop
    /// Focus the nearest tile across that edge of the focused window (D-11, TILE-09).
    case focus(Edge)
    /// Split the current tile with a new Finder window (D-14, TILE-17).
    case finderSplit
    /// Pause Arranging when nothing pauses it, otherwise Resume Arranging (TILE-08, D-23).
    case togglePause
    /// Don't Arrange the frontmost app (TILE-18, D-29). The shell handles it with its exclusion list; the window
    /// system's `windowChanged` events then tell the Arranger.
    case toggleExcludeFrontmost
    /// Move a docked window into the tile across that edge, or snap a floating one to that half of the Desktop tile
    /// (D-09, D-11, TILE-13, TILE-14).
    case moveOrSnap(Edge)
    /// Swap the focused docked window with the docked window focused before it on the same desk (TILE-11).
    case swapPrevious
    /// Grow or shrink the focused tile by a tenth of its split's length (TILE-13).
    case growTile, shrinkTile
    /// Balance or flip the focused tile's parent split; rotate the whole layout from the desk's root split (TILE-12,
    /// D-32). Rotate's hotkey name stays `rotateSplit` (Pitfall 13).
    case balanceSplit, rotateSplit, flipSplit
    /// Snap a floating window to a target inside the Desktop tile (TILE-14).
    case snap(SnapTarget)
    /// Dock every eligible floating window, or float every docked one, on the target desk: one undo step (TILE-16).
    case arrangeAll, floatAll
    case restoreAll
}

/// What a command's availability depends on besides the layout: the frontmost app's focused tracked window, and
/// whether Pane has working Accessibility access.
public struct CommandContext: Equatable, Sendable {
    public var focused: WindowRef?
    public var ready: Bool

    public init(focused: WindowRef?, ready: Bool) {
        self.focused = focused
        self.ready = ready
    }
}

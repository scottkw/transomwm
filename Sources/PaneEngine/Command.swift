import PaneModel

/// The one command enum every route dispatches: hotkeys, menu items and (later) the URL scheme all call
/// `ArrangeController.dispatch(_:)`. Later plans add cases; never rename one.
public enum Command: Hashable, Sendable {
    case dock, float, undo
    /// Hide or show the Desktop tile of the focused window's desk (TILE-15).
    case toggleDesktop
    /// Focus the nearest tile across that edge of the focused window (D-11, TILE-09).
    case focus(Edge)
}

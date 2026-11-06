import TransomModel

/// The one command enum every route dispatches: hotkeys, menu items and (later) the URL scheme all call
/// `ArrangeController.dispatch(_:)`. Later plans add cases; never rename one.
public enum Command: Hashable, Sendable {
    case dock, float, undo
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
    /// Dock the focused window, or move it if docked, to a share of the whole desk (TILE-23, D-14, D-15).
    case dockFourth(FourthSlot, Axis)
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
    /// Bring every window Transom may move back on screen (SAFE-03); acts while paused.
    case restoreAll
    /// A zoom camera command (ZOOM-01..04, 09..11). It acts on one display, so it runs as `ArrangerInput.camera`; a
    /// bare `.command(.camera)` has no display and faults.
    case camera(CameraCommand)
    /// A tab command on the focused window's group (07 UI-SPEC Surface 7, TABS-02, TABS-06).
    case tabs(TabCommand)
}

/// Next Tab and Previous Tab (wrapping) and Move Out of Group (07 UI-SPEC Surface 7).
public enum TabCommand: Hashable, Sendable {
    case next, previous, moveOut
}

/// The camera commands every trigger (hotkey, menu, URL) sends (UI-SPEC Hotkeys and URLs).
public enum CameraCommand: Hashable, Sendable {
    case zoomOutAll, stepOut, stepIn, back, forward
    /// Move View: the node across that edge of the view at the same depth (ZOOM-09).
    case pan(Edge)
    /// Toggles: frame the focused docked window's leaf, or go back when already framed (ZOOM-10).
    case frameWindow
    /// Show or dismiss the overview on every display (OVER-01, D-01). The shell handles it; it never reaches the Arranger.
    case overview
    /// Go to the saved view in that slot (⌥1–9, D-01): the smallest node holding its windows still there (D-02).
    case view(ViewSlot)
    /// Save the pointer display's current view into that slot (⇧⌥1–9, D-01): its desk and window identities, never a
    /// NodeID or a rect (D-02).
    case saveView(ViewSlot)
}

/// A saved-view slot, 1–9 (D-01). Decoding rejects any other number, so a stored file can't address a tenth slot.
public struct ViewSlot: Hashable, Sendable, Codable, Comparable, CustomStringConvertible {
    public let number: Int

    public init?(_ number: Int) {
        guard (1...9).contains(number) else { return nil }
        self.number = number
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        let number = try container.decode(Int.self)
        guard let slot = Self(number) else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "view slot \(number) is not 1–9"))
        }
        self = slot
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(number)
    }

    public static let all: [ViewSlot] = (1...9).compactMap(ViewSlot.init)
    public static func < (a: Self, b: Self) -> Bool { a.number < b.number }
    public var description: String { "\(number)" }
}

/// What a command's availability depends on besides the layout: the frontmost app's focused tracked window, and
/// whether Transom has working Accessibility access.
public struct CommandContext: Equatable, Sendable {
    public var focused: WindowRef?
    public var ready: Bool
    /// The display a camera command would act on (the pointer's, or the menu's); camera availability needs it.
    public var displayUUID: String?

    public init(focused: WindowRef?, ready: Bool, displayUUID: String? = nil) {
        self.focused = focused
        self.ready = ready
        self.displayUUID = displayUUID
    }
}

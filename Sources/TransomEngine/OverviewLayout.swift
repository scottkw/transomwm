import TransomModel

/// One window the overview draws, at its frame in top-left global points.
public struct OverviewWindow: Equatable, Sendable {
    public var window: WindowRef
    public var frame: Rect

    public init(window: WindowRef, frame: Rect) {
        self.window = window
        self.frame = frame
    }
}

/// One display's inputs (06 UI-SPEC Surfaces 1-2). `windows` are the current Space's shown windows, back to front;
/// `home` replaces a window's frame with its home-view tile rect when the display is zoomed in. `hiddenSpaceWindows` are
/// the other Spaces' windows by Space ID, at their planned frames (D-14: never read from AX).
public struct OverviewDisplayInput: Equatable, Sendable {
    public var uuid: String
    public var visibleFrame: Rect
    public var isMain: Bool
    public var isFullScreen: Bool
    public var spaces: [SpaceInfo]
    public var current: UInt64?
    public var windows: [OverviewWindow]
    public var home: [WindowRef: Rect]
    public var hiddenSpaceWindows: [UInt64: [OverviewWindow]]

    public init(
        uuid: String, visibleFrame: Rect, isMain: Bool = true, isFullScreen: Bool = false, spaces: [SpaceInfo] = [], current: UInt64? = nil,
        windows: [OverviewWindow] = [], home: [WindowRef: Rect] = [:], hiddenSpaceWindows: [UInt64: [OverviewWindow]] = [:]
    ) {
        self.uuid = uuid
        self.visibleFrame = visibleFrame
        self.isMain = isMain
        self.isFullScreen = isFullScreen
        self.spaces = spaces
        self.current = current
        self.windows = windows
        self.home = home
        self.hiddenSpaceWindows = hiddenSpaceWindows
    }
}

/// A main-area tile: the window and its rect in the overview.
public struct OverviewTile: Equatable, Sendable {
    public var window: WindowRef
    public var rect: Rect
}

/// One display's overview geometry, top-left global points.
public struct OverviewDisplayLayout: Equatable, Sendable {
    public var uuid: String
    public var mainArea: Rect
    /// The uniform scale from the visibleFrame into the main area.
    public var scale: Double
    /// Back to front, as the input's windows.
    public var tiles: [OverviewTile]
}

/// The overview's pure geometry (06 UI-SPEC Spacing Scale, Surfaces 1-2): every rect the panels draw.
public struct OverviewLayout: Equatable, Sendable {
    public static let margin = 24.0

    /// Displays showing a full-screen Space get no layout (no panel).
    public let displays: [OverviewDisplayLayout]

    public init(displays inputs: [OverviewDisplayInput], stripShown: Bool = false, separateSpaces: Bool = true) {
        displays = inputs.filter { !$0.isFullScreen }.map(Self.layout)
    }

    private static func layout(_ input: OverviewDisplayInput) -> OverviewDisplayLayout {
        let visible = input.visibleFrame
        let area = Rect(
            x: visible.x + margin, y: visible.y + margin, width: max(0, visible.width - 2 * margin), height: max(0, visible.height - 2 * margin))
        let scale = visible.width > 0 && visible.height > 0 ? min(area.width / visible.width, area.height / visible.height) : 0
        let originX = area.midX - visible.width * scale / 2, originY = area.midY - visible.height * scale / 2
        let tiles = input.windows.map { window in
            let r = input.home[window.window] ?? window.frame
            return OverviewTile(
                window: window.window,
                rect: Rect(x: originX + (r.x - visible.x) * scale, y: originY + (r.y - visible.y) * scale, width: r.width * scale, height: r.height * scale))
        }
        return OverviewDisplayLayout(uuid: input.uuid, mainArea: area, scale: scale, tiles: tiles)
    }
}

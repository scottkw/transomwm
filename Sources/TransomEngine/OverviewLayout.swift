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
    /// The tiles held for absent windows, at home: drawn, never selected or counted as windows (08 UI-SPEC Surface 2).
    public var placeholders: [OverviewWindow] = []

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

/// A main-area or mini tile: the window and its rect in the overview.
public struct OverviewTile: Equatable, Sendable {
    public var window: WindowRef
    public var rect: Rect
}

/// One Space's thumbnail in the strip, its label capsule 8 pt below, and its windows as mini tiles (back to front).
public struct ThumbnailLayout: Equatable, Sendable {
    public var rect: Rect
    public var labelRect: Rect
    public var spaceID: UInt64
    public var isCurrent: Bool
    public var miniTiles: [OverviewTile]
}

/// What a point in the overview hits (the empty-message capsule is never an item).
public enum OverviewItem: Equatable, Sendable {
    case tile(WindowRef)
    case miniTile(WindowRef, space: UInt64)
    case thumbnail(space: UInt64)
}

/// One display's overview geometry, top-left global points.
public struct OverviewDisplayLayout: Equatable, Sendable {
    public var uuid: String
    /// The display's visibleFrame: which display the pointer is on, and the left-to-right display order.
    public var visibleFrame: Rect
    public var mainArea: Rect
    /// The uniform scale from the visibleFrame into the main area.
    public var scale: Double
    /// Back to front, as the input's windows.
    public var tiles: [OverviewTile]
    /// The placeholders' tiles, drawn behind `tiles`. Not items: nothing selects them.
    public var placeholders: [OverviewTile] = []
    /// The strip's band across the top of the visibleFrame; nil when the strip is hidden on this display.
    public var stripBand: Rect?
    public var thumbnails: [ThumbnailLayout]
    /// Centred in the main area when the current Space shows no windows.
    public var emptyCapsule: Rect?
}

/// The overview's pure geometry (06 UI-SPEC Spacing Scale, Surfaces 1-2): every rect the panels draw.
public struct OverviewLayout: Equatable, Sendable {
    public static let margin = 24.0
    public static let gap = 16.0
    public static let labelGap = 8.0
    public static let labelHeight = 21.0
    public static let thumbnailMin = 32.0
    public static let thumbnailClampLow = 64.0
    public static let thumbnailClampHigh = 112.0
    /// macOS allows at most 16 Spaces per display, so the strip never scrolls.
    public static let maxSpaces = 16

    /// Displays showing a full-screen Space get no layout (no panel).
    public let displays: [OverviewDisplayLayout]

    /// `stripShown` is the Spaces lookup working (D-15); with `separateSpaces` off only the `isMain` display has a strip
    /// (D-12). `emptyCapsuleSize` is the measured "No windows on this desktop" capsule.
    public init(
        displays inputs: [OverviewDisplayInput], stripShown: Bool = false, separateSpaces: Bool = true, emptyCapsuleSize: Size = Size(width: 0, height: 0)
    ) {
        displays = inputs.filter { !$0.isFullScreen }.map { input in
            Self.layout(input, strip: stripShown && (separateSpaces || input.isMain) && !input.spaces.isEmpty, capsule: emptyCapsuleSize)
        }
    }

    /// A layout already made, with tiles changed while the overview is open (06-09 live updates).
    public init(laidOut displays: [OverviewDisplayLayout]) { self.displays = displays }

    /// The front-most item under `point`: the strip first (it is drawn above), then main-area tiles front to back.
    public func item(at point: Point) -> OverviewItem? {
        for display in displays {
            for thumb in display.thumbnails where thumb.rect.contains(point) {
                if let mini = thumb.miniTiles.last(where: { $0.rect.contains(point) }) { return .miniTile(mini.window, space: thumb.spaceID) }
                return .thumbnail(space: thumb.spaceID)
            }
            if let tile = display.tiles.last(where: { $0.rect.contains(point) }) { return .tile(tile.window) }
        }
        return nil
    }

    /// `rect` (in `from`) scaled uniformly by `scale` into the box at `origin`.
    private static func map(_ rect: Rect, from: Rect, scale: Double, origin: Point) -> Rect {
        Rect(
            x: origin.x + (rect.x - from.x) * scale, y: origin.y + (rect.y - from.y) * scale, width: rect.width * scale, height: rect.height * scale)
    }

    private static func layout(_ input: OverviewDisplayInput, strip: Bool, capsule: Size) -> OverviewDisplayLayout {
        let visible = input.visibleFrame
        let aspect = visible.height > 0 ? visible.width / visible.height : 1
        let spaces = Array(input.spaces.prefix(maxSpaces))
        var height = min(max(visible.height * 0.12, thumbnailClampLow), thumbnailClampHigh)
        let count = Double(spaces.count)
        let available = visible.width - 2 * margin - (count - 1) * gap
        if strip, count * height * aspect > available { height = max(thumbnailMin, available / count / aspect) }
        let width = height * aspect
        let band = strip ? gap + height + labelGap + labelHeight + gap : 0

        let top = strip ? band : margin
        let area = Rect(
            x: visible.x + margin, y: visible.y + top, width: max(0, visible.width - 2 * margin), height: max(0, visible.height - top - margin))
        let scale = visible.width > 0 && visible.height > 0 ? min(area.width / visible.width, area.height / visible.height) : 0
        let origin = Point(x: area.midX - visible.width * scale / 2, y: area.midY - visible.height * scale / 2)
        let tiles = input.windows.map { window in
            OverviewTile(window: window.window, rect: map(input.home[window.window] ?? window.frame, from: visible, scale: scale, origin: origin))
        }
        let placeholders = input.placeholders.map { OverviewTile(window: $0.window, rect: map($0.frame, from: visible, scale: scale, origin: origin)) }

        var thumbnails: [ThumbnailLayout] = []
        if strip {
            let row = count * width + (count - 1) * gap
            let thumbScale = visible.width > 0 ? width / visible.width : 0
            for (i, space) in spaces.enumerated() {
                let rect = Rect(x: visible.midX - row / 2 + Double(i) * (width + gap), y: visible.y + gap, width: width, height: height)
                let isCurrent = space.id == input.current
                let windows = isCurrent ? input.windows : input.hiddenSpaceWindows[space.id] ?? []
                let minis: [OverviewTile]
                if space.kind == .fullScreen {
                    minis = windows.first.map { [OverviewTile(window: $0.window, rect: rect)] } ?? []
                } else {
                    minis = windows.map { window in
                        let frame = isCurrent ? input.home[window.window] ?? window.frame : window.frame
                        return OverviewTile(window: window.window, rect: map(frame, from: visible, scale: thumbScale, origin: rect.origin))
                    }
                }
                thumbnails.append(ThumbnailLayout(
                    rect: rect, labelRect: Rect(x: rect.x, y: rect.maxY + labelGap, width: width, height: labelHeight), spaceID: space.id,
                    isCurrent: isCurrent, miniTiles: minis))
            }
        }
        let empty = input.windows.isEmpty
            ? Rect(x: area.midX - capsule.width / 2, y: area.midY - capsule.height / 2, width: capsule.width, height: capsule.height) : nil
        return OverviewDisplayLayout(
            uuid: input.uuid, visibleFrame: visible, mainArea: area, scale: scale, tiles: tiles, placeholders: placeholders, stripBand: strip ? Rect(x: visible.x, y: visible.y, width: visible.width, height: band) : nil,
            thumbnails: thumbnails, emptyCapsule: empty)
    }
}

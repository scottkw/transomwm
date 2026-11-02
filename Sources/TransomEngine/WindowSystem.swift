import TransomModel

/// One display as the window system reports it. `uuid` and `currentSpaceID` key the desk (`DeskKey`).
public struct DisplayInfo: Equatable, Sendable {
    public var uuid: String
    public var frame: Rect
    public var visibleFrame: Rect
    public var currentSpaceID: UInt64?

    public init(uuid: String, frame: Rect, visibleFrame: Rect, currentSpaceID: UInt64?) {
        self.uuid = uuid
        self.frame = frame
        self.visibleFrame = visibleFrame
        self.currentSpaceID = currentSpaceID
    }
}

extension DisplayInfo {
    /// Where `park` puts a window of `size`: just past a bottom corner of the visibleFrame, so macOS keeps only a 1 pt
    /// sliver on screen (RESEARCH Pattern 15, AeroSpace prior art). The bottom-right corner unless the window would then
    /// overlap another of `displays`, else the bottom-left (CR-02); with both taken, the bottom-right corner of all the
    /// displays together, which no display extends past.
    public func parkedFrame(size: Size, among displays: [DisplayInfo]) -> Rect {
        let others = displays.filter { $0.uuid != uuid }.map(\.frame)
        for x in [visibleFrame.maxX - 1, visibleFrame.minX - size.width + 1] {
            let rect = Rect(x: x, y: visibleFrame.maxY - 1, width: size.width, height: size.height)
            if !others.contains(where: rect.overlaps) { return rect }
        }
        let all = others + [frame]
        return Rect(x: (all.map(\.maxX).max() ?? frame.maxX) - 1, y: (all.map(\.maxY).max() ?? frame.maxY) - 1, width: size.width, height: size.height)
    }
}

/// Why a tracked window is never arranged into a tile.
public enum NeverDockReason: String, Codable, Sendable, CaseIterable {
    case floatingLevel, subrole, modal, noCloseButton, noFullscreenButton
}

/// Whether a window may be docked into a tile. Never-dock windows are tracked but never arranged (D-06).
public enum WindowKind: Codable, Equatable, Hashable, Sendable {
    case dockable
    case neverDock(NeverDockReason)
}

/// Where a window's `WindowIdentity.windowID` came from.
public enum WindowIDSource: String, Codable, Sendable {
    /// `_AXUIElementGetWindow` (TransomPrivate).
    case axPrivate
    /// The same-pid CG window whose bounds match the AX frame (fallback, SAFE-05).
    case cgFrameMatch
    /// A session-only ID from `WindowIdentity.syntheticIDBase` when the fallback match is ambiguous.
    case synthetic
}

/// One window as the window system reports it, with its lifecycle state and the display it is on.
///
/// `frame` is in the global top-left space. `visibleMemberID` is the CGWindowID to address right now
/// when the window is a native tab group (whose identity is the first-seen member).
public struct WindowInfo: Equatable, Sendable {
    public var window: WindowRef
    public var frame: Rect
    public var state: WindowState
    public var displayUUID: String?
    public var kind: WindowKind
    public var idSource: WindowIDSource
    public var visibleMemberID: UInt32?
    public var tabCount: Int
    public var isExcluded: Bool
    public var learnedMinimum: Size?
    /// The part of `learnedMinimum` safe to share with the bundle and save (`MinimumSizeLearner.persistableMinimum`).
    public var persistableMinimum: Size?
    /// The Spaces the window is on (SkyLight, D-25). Nil means no Space data; empty means the lookup reported none,
    /// as for a hidden native tab (02-14).
    public var spaces: Set<UInt64>?
    /// The green button's frame as an offset from `frame`'s top-left (`WindowSnapshot.greenButton`); nil when unknown.
    public var greenButton: Rect?

    public init(
        window: WindowRef, frame: Rect, state: WindowState, displayUUID: String?,
        kind: WindowKind = .dockable, idSource: WindowIDSource = .axPrivate, visibleMemberID: UInt32? = nil,
        tabCount: Int = 1, isExcluded: Bool = false, learnedMinimum: Size? = nil, spaces: Set<UInt64>? = nil,
        greenButton: Rect? = nil, persistableMinimum: Size? = nil
    ) {
        self.window = window
        self.frame = frame
        self.state = state
        self.displayUUID = displayUUID
        self.kind = kind
        self.idSource = idSource
        self.visibleMemberID = visibleMemberID
        self.tabCount = tabCount
        self.isExcluded = isExcluded
        self.learnedMinimum = learnedMinimum
        self.persistableMinimum = persistableMinimum
        self.spaces = spaces
        self.greenButton = greenButton
    }
}

/// A full refresh of every display and window.
public struct WindowInventory: Equatable, Sendable {
    public var displays: [DisplayInfo]
    public var windows: [WindowInfo]
    /// Apps whose AX calls are currently timing out; their windows keep their last known info.
    public var degradedPIDs: Set<Int32>
    /// True while the screen is locked or the Mac sleeps; nothing is closed while paused.
    public var sessionPaused: Bool
    /// True once every app has answered or failed the first sweep.
    public var initialRefreshComplete: Bool
    /// The layer-0 entries of the latest CG optionAll list for tracked apps, so windows on Spaces AX does not list are
    /// included (G-03-8). Nil means unknown, and nothing may be decided from it.
    public var liveWindows: [CGWindowEntry]?

    public init(
        displays: [DisplayInfo], windows: [WindowInfo], degradedPIDs: Set<Int32> = [],
        sessionPaused: Bool = false, initialRefreshComplete: Bool = false, liveWindows: [CGWindowEntry]? = nil
    ) {
        self.displays = displays
        self.windows = windows
        self.degradedPIDs = degradedPIDs
        self.sessionPaused = sessionPaused
        self.initialRefreshComplete = initialRefreshComplete
        self.liveWindows = liveWindows
    }
}

/// Something the window system observed.
public enum WindowEvent: Equatable, Sendable {
    case windowCreated(WindowInfo)
    case windowDestroyed(WindowRef)
    case windowMoved(WindowRef, Rect)
    case windowResized(WindowRef, Rect)
    case windowFocused(WindowRef)
    case windowStateChanged(WindowRef, WindowState)
    /// Title, kind, tab or exclusion changed. Titles are never logged.
    case windowChanged(WindowInfo)
    /// The same window, only its ID changed (a fallback ID corrected, D-15): never a close and a reopen. Consumers
    /// re-point every reference to `from` at `to.window`.
    case windowRekeyed(from: WindowRef, to: WindowInfo)
    /// A frame write finished; `actual` is the read-back frame.
    case frameApplied(WindowRef, requested: Rect, actual: Rect)
    case appResponsiveness(pid: Int32, degraded: Bool)
    case sessionPaused(Bool)
    case appLaunched(pid: Int32, bundleID: String)
    case appTerminated(pid: Int32)
    case displaysChanged
    case spaceChanged(displayUUID: String, spaceID: UInt64?)
    /// The window system's set of layer-0 CG windows of tracked apps changed. It carries nothing: the shell then feeds
    /// the inventory, whose `liveWindows` prunes dormant saved windows that closed (G-03-8).
    case liveWindowsChanged
}

/// Something the engine asks the window system to do.
public enum WindowCommand: Equatable, Sendable {
    case setFrame(WindowRef, Rect)
    /// Moves the window to its display's `parkedFrame`, at `size` when given (a hidden tab's content size), else its own.
    case park(WindowRef, displayUUID: String, size: Size? = nil)
    case focus(WindowRef)
    case raise(WindowRef)
    case setHidden(WindowRef, Bool)
    /// Presses the window's own close button, so its app may ask to save first (D-06); never a force close.
    case close(WindowRef)
    case minimize(WindowRef)
}

/// Boundary between the engine and the OS window system.
///
/// All coordinates are in the D-09 global space: top-left origin, y growing downward.
/// Commands are fire-and-forget; implementations may coalesce them (for example, keep only
/// the last `setFrame` per window). Window titles never appear in errors or logs.
/// Implemented by `AXWindowSystem` (TransomMac) and `FakeWindowSystem` (TransomTestSupport).
public protocol WindowSystem: AnyObject, Sendable {
    var events: AsyncStream<WindowEvent> { get }
    func inventory() async -> WindowInventory
    func perform(_ commands: [WindowCommand]) async
    /// The latest known info for one window. Returns nil only for a window never seen or confirmed
    /// closed by two sources; while its app is hung or the session is paused it returns the last known info.
    func windowInfo(_ window: WindowRef) async -> WindowInfo?
}

extension WindowIdentity {
    /// Start of the reserved range for synthetic fallback IDs (`syntheticIDBase | counter`).
    public static let syntheticIDBase: UInt32 = 0xF000_0000

    public var isSyntheticWindowID: Bool { windowID >= Self.syntheticIDBase }
}

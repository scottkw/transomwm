import PaneModel

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
    /// Where `park` puts a window of `size`: its top-left at the visibleFrame's bottom-right corner minus 1 pt, so
    /// macOS keeps only a sliver on screen (RESEARCH Pattern 15, AeroSpace prior art).
    public func parkedFrame(size: Size) -> Rect {
        Rect(x: visibleFrame.maxX - 1, y: visibleFrame.maxY - 1, width: size.width, height: size.height)
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
    /// `_AXUIElementGetWindow` (PanePrivate).
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
    /// The Spaces the window is on (SkyLight, D-25). Nil means no Space data; empty means the lookup reported none,
    /// as for a hidden native tab (02-14).
    public var spaces: Set<UInt64>?
    /// The green button's frame as an offset from `frame`'s top-left (`WindowSnapshot.greenButton`); nil when unknown.
    public var greenButton: Rect?

    public init(
        window: WindowRef, frame: Rect, state: WindowState, displayUUID: String?,
        kind: WindowKind = .dockable, idSource: WindowIDSource = .axPrivate, visibleMemberID: UInt32? = nil,
        tabCount: Int = 1, isExcluded: Bool = false, learnedMinimum: Size? = nil, spaces: Set<UInt64>? = nil,
        greenButton: Rect? = nil
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

    public init(
        displays: [DisplayInfo], windows: [WindowInfo], degradedPIDs: Set<Int32> = [],
        sessionPaused: Bool = false, initialRefreshComplete: Bool = false
    ) {
        self.displays = displays
        self.windows = windows
        self.degradedPIDs = degradedPIDs
        self.sessionPaused = sessionPaused
        self.initialRefreshComplete = initialRefreshComplete
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
}

/// Something the engine asks the window system to do.
public enum WindowCommand: Equatable, Sendable {
    case setFrame(WindowRef, Rect)
    case park(WindowRef, displayUUID: String)
    case focus(WindowRef)
    case raise(WindowRef)
    case setHidden(WindowRef, Bool)
}

/// Boundary between the engine and the OS window system.
///
/// All coordinates are in the D-09 global space: top-left origin, y growing downward.
/// Commands are fire-and-forget; implementations may coalesce them (for example, keep only
/// the last `setFrame` per window). Window titles never appear in errors or logs.
/// Implemented by `AXWindowSystem` (PaneMac) and `FakeWindowSystem` (PaneTestSupport).
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

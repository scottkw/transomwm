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

/// One window as the window system reports it, with its lifecycle state and the display it is on.
public struct WindowInfo: Equatable, Sendable {
    public var window: WindowRef
    public var frame: Rect
    public var state: WindowState
    public var displayUUID: String?

    public init(window: WindowRef, frame: Rect, state: WindowState, displayUUID: String?) {
        self.window = window
        self.frame = frame
        self.state = state
        self.displayUUID = displayUUID
    }
}

/// A full refresh of every display and window.
public struct WindowInventory: Equatable, Sendable {
    public var displays: [DisplayInfo]
    public var windows: [WindowInfo]

    public init(displays: [DisplayInfo], windows: [WindowInfo]) {
        self.displays = displays
        self.windows = windows
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

/// Draft boundary between the engine and the OS window system.
///
/// All coordinates are in the D-09 global space: top-left origin, y growing downward.
/// Commands are fire-and-forget; implementations may coalesce them (for example, keep only
/// the last `setFrame` per window). Phase 2 provides `MacWindowSystem` and `FakeWindowSystem`.
public protocol WindowSystem: AnyObject, Sendable {
    var events: AsyncStream<WindowEvent> { get }
    func inventory() async -> WindowInventory
    func perform(_ commands: [WindowCommand]) async
}

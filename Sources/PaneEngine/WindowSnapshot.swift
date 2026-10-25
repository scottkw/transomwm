import PaneModel

// AX facts about windows, captured live by PaneMac's AXSnapshotReader, simulated by FakeWindowSystem
// and recorded (redacted) in the classifier corpus. All frames are in the global top-left space.
// No type here carries a window title except `WindowObservation.title`, which never reaches a fixture or a log.

/// One title-bar button: whether the window has it, and whether it is enabled.
public struct ButtonFact: Codable, Equatable, Sendable {
    public var present: Bool
    public var enabled: Bool

    public init(present: Bool, enabled: Bool) {
        self.present = present
        self.enabled = enabled
    }

    public static let absent = ButtonFact(present: false, enabled: false)
    public static let enabled = ButtonFact(present: true, enabled: true)
}

/// A native tab group child (`AXTabGroup`) and its `AXTabs` count.
public struct TabGroupFact: Codable, Equatable, Sendable {
    public var tabCount: Int

    public init(tabCount: Int) {
        self.tabCount = tabCount
    }
}

/// What the CG window list says about the window.
public struct CGWindowFact: Codable, Equatable, Sendable {
    public var layer: Int
    public var onScreen: Bool
    public var alpha: Double

    public init(layer: Int, onScreen: Bool, alpha: Double) {
        self.layer = layer
        self.onScreen = onScreen
        self.alpha = alpha
    }
}

/// The AX attributes of one window, read in one batched call. A nil field means the attribute was missing.
public struct WindowSnapshot: Codable, Equatable, Sendable {
    public var schemaVersion: Int = 1
    public var role: String?
    public var subrole: String?
    public var modal: Bool?
    public var main: Bool?
    public var minimized: Bool?
    public var fullScreen: Bool?
    public var identifier: String?
    public var close: ButtonFact
    public var minimize: ButtonFact
    public var zoom: ButtonFact
    public var fullScreenButton: ButtonFact
    public var tabGroup: TabGroupFact?
    public var sheetAttached: Bool?
    public var frame: Rect?
    public var cg: CGWindowFact?

    public init(
        role: String? = nil, subrole: String? = nil, modal: Bool? = nil, main: Bool? = nil,
        minimized: Bool? = nil, fullScreen: Bool? = nil, identifier: String? = nil,
        close: ButtonFact = .absent, minimize: ButtonFact = .absent, zoom: ButtonFact = .absent,
        fullScreenButton: ButtonFact = .absent, tabGroup: TabGroupFact? = nil, sheetAttached: Bool? = nil,
        frame: Rect? = nil, cg: CGWindowFact? = nil
    ) {
        self.role = role
        self.subrole = subrole
        self.modal = modal
        self.main = main
        self.minimized = minimized
        self.fullScreen = fullScreen
        self.identifier = identifier
        self.close = close
        self.minimize = minimize
        self.zoom = zoom
        self.fullScreenButton = fullScreenButton
        self.tabGroup = tabGroup
        self.sheetAttached = sheetAttached
        self.frame = frame
        self.cg = cg
    }
}

/// An AX error, kept distinct: "element gone" (-25202) and "app did not answer" (-25204) drive
/// different close decisions (WIN-09), so they are never collapsed into nil.
public enum AXFailure: Error, Codable, Equatable, Hashable, Sendable {
    case invalidElement
    case cannotComplete
    case apiDisabled
    case attributeUnsupported
    case other(Int32)

    public init(code: Int32) {
        switch code {
        case -25202: self = .invalidElement
        case -25204: self = .cannotComplete
        case -25211: self = .apiDisabled
        case -25205: self = .attributeUnsupported
        default: self = .other(code)
        }
    }
}

/// One element of an app's `AXWindows` (or a simulated one), as read on its app thread.
public struct WindowObservation: Equatable, Sendable {
    /// nil when no window ID could be resolved (for example `_AXUIElementGetWindow` is unavailable).
    public var windowID: UInt32?
    public var idSource: WindowIDSource
    public var read: Result<WindowSnapshot, AXFailure>
    public var title: String
    public var listedInAXWindows: Bool

    public init(windowID: UInt32?, idSource: WindowIDSource, read: Result<WindowSnapshot, AXFailure>, title: String, listedInAXWindows: Bool = true) {
        self.windowID = windowID
        self.idSource = idSource
        self.read = read
        self.title = title
        self.listedInAXWindows = listedInAXWindows
    }
}

/// Everything one app answered in one refresh. `listFailure` is set when `AXWindows` itself failed.
public struct AppObservation: Equatable, Sendable {
    public var pid: Int32
    public var bundleID: String
    public var appHidden: Bool
    public var windows: [WindowObservation]
    public var listFailure: AXFailure?
    public var duration: Duration

    public init(pid: Int32, bundleID: String, appHidden: Bool = false, windows: [WindowObservation], listFailure: AXFailure? = nil, duration: Duration = .zero) {
        self.pid = pid
        self.bundleID = bundleID
        self.appHidden = appHidden
        self.windows = windows
        self.listFailure = listFailure
        self.duration = duration
    }
}

/// One entry of the CG window list, the second source for close decisions.
public struct CGWindowEntry: Codable, Equatable, Sendable {
    public var windowID: UInt32
    public var pid: Int32
    public var bounds: Rect
    public var layer: Int
    public var onScreen: Bool
    public var alpha: Double

    public init(windowID: UInt32, pid: Int32, bounds: Rect, layer: Int, onScreen: Bool, alpha: Double) {
        self.windowID = windowID
        self.pid = pid
        self.bounds = bounds
        self.layer = layer
        self.onScreen = onScreen
        self.alpha = alpha
    }
}

/// The world around one `AppObservation`: the CG list, displays, session state and the time.
public struct ObservationContext: Sendable {
    public var cgWindows: [CGWindowEntry]
    public var displays: [DisplayInfo]
    public var sessionActive: Bool
    public var initialSweep: Bool
    public var now: ContinuousClock.Instant
    /// Each CG window's Spaces (SkyLight); nil means no Space data (the Spaces capability is off or missing).
    /// A window with no Space reported maps to an empty set.
    public var windowSpaces: [UInt32: Set<UInt64>]?

    public init(
        cgWindows: [CGWindowEntry] = [], displays: [DisplayInfo] = [], sessionActive: Bool = true, initialSweep: Bool = false,
        now: ContinuousClock.Instant, windowSpaces: [UInt32: Set<UInt64>]? = nil
    ) {
        self.cgWindows = cgWindows
        self.windowSpaces = windowSpaces
        self.displays = displays
        self.sessionActive = sessionActive
        self.initialSweep = initialSweep
        self.now = now
    }
}

/// The outcome of one frame write: the requested frame and the read-back (nil when it failed).
public struct FrameWriteResult: Equatable, Sendable {
    public var window: WindowRef
    public var requested: Rect
    public var actual: Rect?
    public var failure: AXFailure?

    public init(window: WindowRef, requested: Rect, actual: Rect?, failure: AXFailure?) {
        self.window = window
        self.requested = requested
        self.actual = actual
        self.failure = failure
    }
}

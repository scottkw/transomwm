import PaneEngine
import PaneModel

/// A simulated app in `FakeWindowSystem`.
public struct FakeApp: Sendable {
    public var pid: Int32
    public var bundleID: String
    public var hung: Bool
    public var responseDelay: Duration
    public var hidden: Bool
    public var terminated: Bool

    public init(pid: Int32, bundleID: String, hung: Bool = false, responseDelay: Duration = .zero, hidden: Bool = false, terminated: Bool = false) {
        self.pid = pid
        self.bundleID = bundleID
        self.hung = hung
        self.responseDelay = responseDelay
        self.hidden = hidden
        self.terminated = terminated
    }
}

/// A simulated window in `FakeWindowSystem`. `frame` is authoritative; it replaces `snapshot.frame` on every refresh.
public struct FakeWindow: Sendable {
    public var id: UInt32
    public var pid: Int32
    public var title: String
    public var frame: Rect
    public var snapshot: WindowSnapshot
    public var hiddenMinimum: Size?
    public var axValid: Bool
    public var inCGList: Bool
    public var listedInAX: Bool
    public var cgLayer: Int
    public var onScreen: Bool

    public init(
        id: UInt32, pid: Int32, title: String, frame: Rect, snapshot: WindowSnapshot, hiddenMinimum: Size? = nil,
        axValid: Bool = true, inCGList: Bool = true, listedInAX: Bool = true, cgLayer: Int = 0, onScreen: Bool = true
    ) {
        self.id = id
        self.pid = pid
        self.title = title
        self.frame = frame
        self.snapshot = snapshot
        self.hiddenMinimum = hiddenMinimum
        self.axValid = axValid
        self.inCGList = inCGList
        self.listedInAX = listedInAX
        self.cgLayer = cgLayer
        self.onScreen = onScreen
    }

    /// An `AXStandardWindow` with all four title-bar buttons present and enabled.
    public static func standard(id: UInt32, pid: Int32, frame: Rect, title: String = "") -> FakeWindow {
        FakeWindow(
            id: id, pid: pid, title: title, frame: frame,
            snapshot: WindowSnapshot(
                role: "AXWindow", subrole: "AXStandardWindow", modal: false, main: false, minimized: false, fullScreen: false,
                close: .enabled, minimize: .enabled, zoom: .enabled, fullScreenButton: .enabled, frame: frame
            )
        )
    }
}

/// A `WindowSystem` over a simulated OS (D-14). Refreshes build `AppObservation`s from the simulation and
/// feed them through the production `WindowTracker`, so scenario tests exercise the real decisions.
public actor FakeWindowSystem: WindowSystem {
    public nonisolated let events: AsyncStream<WindowEvent>
    private let continuation: AsyncStream<WindowEvent>.Continuation
    public private(set) var apps: [Int32: FakeApp] = [:]
    public private(set) var windows: [UInt32: FakeWindow] = [:]
    public private(set) var locked = false
    public private(set) var performed: [WindowCommand] = []
    public private(set) var clock: ContinuousClock.Instant
    private var tracker = WindowTracker()

    public init(now: ContinuousClock.Instant = .now) {
        (events, continuation) = AsyncStream.makeStream(bufferingPolicy: .unbounded)
        clock = now
    }

    public func addApp(_ app: FakeApp) {}
    public func open(_ window: FakeWindow) {}
    public func update(_ id: UInt32, _ change: @Sendable (inout FakeWindow) -> Void) {}
    public func setHung(pid: Int32, _ hung: Bool) {}
    public func setLocked(_ locked: Bool) {}
    public func terminate(pid: Int32) {}
    public func advance(by duration: Duration) {}
    public func refresh(pid: Int32) {}
    public func refreshAll() {}

    public func inventory() async -> WindowInventory {
        WindowInventory(displays: [], windows: [])
    }

    public func perform(_ commands: [WindowCommand]) async {}

    public func windowInfo(_ window: WindowRef) async -> WindowInfo? {
        nil
    }
}

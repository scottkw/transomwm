import PaneModel

public enum ArrangerInput: Sendable {
    case inventory(WindowInventory)
    case event(WindowEvent)
    case command(Command, focused: WindowRef?)
    case requeried(RevivedWindows, [(WindowRef, WindowState)])
}

public enum ArrangerEffect: Equatable, Sendable {
    case perform([WindowCommand])
    case requery(RevivedWindows)
    case beep
    case announce(String)
    case fault(String)
}

public struct Arranger: Sendable {
    public private(set) var world = World()
    public private(set) var history = UndoHistory()
    public private(set) var windows: [WindowIdentity: WindowInfo] = [:]
    public private(set) var displays: [DisplayInfo] = []
    public var gap: Double

    public init(gap: Double = 8) {
        self.gap = gap
    }

    public mutating func handle(_ input: ArrangerInput, now: ContinuousClock.Instant) -> [ArrangerEffect] { [] }

    public func deskKey(of window: WindowRef) -> DeskKey? { nil }

    public func isAvailable(_ command: Command, focused: WindowRef?) -> Bool { false }
}

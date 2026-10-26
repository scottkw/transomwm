import PaneEngine
import PaneModel

@MainActor public final class ArrangeController {
    private let system: AXWindowSystem
    public var onInventory: ((WindowInventory) -> Void)?
    public private(set) var arranger = Arranger()

    public init(system: AXWindowSystem) {
        self.system = system
    }

    public func start() async {}

    public func dispatch(_ command: Command) async {}

    public func dispatch(_ command: Command, focused: PaneModel.WindowRef?) async {}
}

import AppKit
import PaneEngine

final class ConflictController {
    var setStageManagerPaused: (Bool) -> Void = { _ in }
    private(set) var active: Set<Conflict> = []
    private(set) var originals: [String: PrefValue] = [:]

    init(store: any PreferencesStore, defaults: UserDefaults = .standard, osMajor: Int = 14, readBackDelay: Duration = .seconds(1)) {}
    func poll() {}
    func turnOff(_ conflict: Conflict) async {}
}

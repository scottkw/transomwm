import Foundation
import PaneEngine

protocol PreferencesStore {
    func value(_ key: String) -> PrefValue
    func set(_ key: String, _ value: Bool?)
    func synchronize()
}

final class CFPreferencesStore: PreferencesStore {
    init(domain: String) {}
    func value(_ key: String) -> PrefValue { .absent }
    func set(_ key: String, _ value: Bool?) {}
    func synchronize() {}
}

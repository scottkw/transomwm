import Foundation
import TransomEngine

/// One preferences domain, booleans only. Tests inject an in-memory store or a test-only domain (T-03-47).
protocol PreferencesStore {
    func value(_ key: String) -> PrefValue
    /// nil deletes the key, so the system default applies again.
    func set(_ key: String, _ value: Bool?)
    func synchronize()
}

/// CFPreferences on `domain`, the current user, any host. Only TransomMacApp makes one for `ConflictPolicy.domain`.
/// It writes values and nothing else: no process is restarted or signalled (Pitfall 15).
final class CFPreferencesStore: PreferencesStore {
    private let domain: CFString

    init(domain: String) {
        self.domain = domain as CFString
    }

    func value(_ key: String) -> PrefValue {
        guard let value = CFPreferencesCopyAppValue(key as CFString, domain) else { return .absent }
        guard CFGetTypeID(value) == CFBooleanGetTypeID() else { return .other }  // a number is not a boolean
        return .bool(CFBooleanGetValue((value as! CFBoolean)))
    }

    func set(_ key: String, _ value: Bool?) {
        CFPreferencesSetAppValue(key as CFString, value.map { ($0 ? kCFBooleanTrue : kCFBooleanFalse) as CFPropertyList }, domain)
        synchronize()
    }

    /// Before reads, so another process's change is seen.
    func synchronize() {
        _ = CFPreferencesAppSynchronize(domain)
    }
}

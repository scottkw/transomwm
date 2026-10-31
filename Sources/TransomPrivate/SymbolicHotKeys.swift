import Darwin
import Foundation

/// Symbolic hotkeys (the system shortcuts in System Settings ▸ Keyboard Shortcuts) through SkyLight (private, OVER-02).
/// Reached only through `dlopen` + `dlsym`, never linked: a removed symbol leaves the table nil and the Mission Control
/// keys stay macOS's. Each `SLS*` name falls back to its older `CGS*` alias.
///
/// Provenance: getter shape and IDs from a local read-only probe on macOS 27.2 (06-RESEARCH F2, F3); setter shape
/// (hotkey, Bool) -> CGError from alt-tab-macos 848ae5f (GPL-3, facts only, no code). The enabled flag lives in
/// WindowServer, not in any preferences file, and may outlive the process that set it.
public enum SymbolicHotKeys {
    typealias IsEnabled = @convention(c) (Int32) -> Bool
    typealias SetEnabled = @convention(c) (Int32, Bool) -> Int32
    typealias GetValue = @convention(c) (Int32, UnsafeMutablePointer<UInt16>, UnsafeMutablePointer<UInt16>, UnsafeMutablePointer<UInt32>) -> Int32

    /// "Mission Control", ⌃↑ by default.
    public static let missionControl: Int32 = 32
    /// The Mission Control key (key code 160, no modifier).
    public static let missionControlKey: Int32 = 108

    /// A hotkey's chord: virtual key code and NX device-independent modifier flags (0x20000 ⇧, 0x40000 ⌃, 0x80000 ⌥,
    /// 0x100000 ⌘, 0x800000 fn).
    public struct Value: Equatable, Sendable {
        public let keyCode: UInt16
        public let modifiers: UInt32
    }

    private static let functions: (isEnabled: IsEnabled, setEnabled: SetEnabled, getValue: GetValue)? = {
        guard !Capabilities.isForcedOff(.symbolicHotKeys),
              let handle = dlopen("/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight", RTLD_LAZY),
              let isEnabled = dlsym(handle, "SLSIsSymbolicHotKeyEnabled") ?? dlsym(handle, "CGSIsSymbolicHotKeyEnabled"),
              let setEnabled = dlsym(handle, "SLSSetSymbolicHotKeyEnabled") ?? dlsym(handle, "CGSSetSymbolicHotKeyEnabled"),
              let getValue = dlsym(handle, "SLSGetSymbolicHotKeyValue") ?? dlsym(handle, "CGSGetSymbolicHotKeyValue")
        else { return nil }
        return (unsafeBitCast(isEnabled, to: IsEnabled.self), unsafeBitCast(setEnabled, to: SetEnabled.self), unsafeBitCast(getValue, to: GetValue.self))
    }()

    /// True only when all three symbols resolved and the capability was not forced off at launch.
    public static var isLoaded: Bool { functions != nil }

    /// Nil when the capability is unavailable.
    public static func isEnabled(_ id: Int32, session: CapabilitySession = Capabilities.session) -> Bool? {
        guard session.isAvailable(.symbolicHotKeys), let functions else { return nil }
        return functions.isEnabled(id)
    }

    /// True only when WindowServer answered CGError 0. Read back with `isEnabled` to be sure.
    @discardableResult
    public static func setEnabled(_ id: Int32, _ enabled: Bool, session: CapabilitySession = Capabilities.session) -> Bool {
        guard session.isAvailable(.symbolicHotKeys), let functions else { return false }
        return functions.setEnabled(id, enabled) == 0
    }

    /// The hotkey's chord, nil when unavailable or the ID has no value.
    public static func value(_ id: Int32, session: CapabilitySession = Capabilities.session) -> Value? {
        guard session.isAvailable(.symbolicHotKeys), let functions else { return nil }
        var character: UInt16 = 0, keyCode: UInt16 = 0, modifiers: UInt32 = 0
        guard functions.getValue(id, &character, &keyCode, &modifiers) == 0 else { return nil }
        return Value(keyCode: keyCode, modifiers: modifiers)
    }
}

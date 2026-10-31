import Foundation
import os

/// One private API Transom can run without. The raw value is the name used by `--disable-private=`.
public enum Capability: String, CaseIterable, Sendable {
    case axWindowID = "AXWindowID"
    case spaces = "Spaces"
    case multitouch = "Multitouch"
    case symbolicHotKeys = "SymbolicHotKeys"
    case coreDock = "CoreDock"

    /// What Transom does instead while the capability is off.
    public var fallback: String {
        switch self {
        case .axWindowID: "matching by frame"
        case .spaces: "single Space"
        case .multitouch: "trackpad gestures from system events"
        case .symbolicHotKeys, .coreDock: ""
        }
    }
}

/// Registry of private-API capabilities (D-15, SAFE-05). Each capability is either loaded or off;
/// off means only the feature built on it degrades, never the launch.
public enum Capabilities {
    static let flagPrefix = "--disable-private="
    static let logger = Logger(subsystem: "com.eightabyte.transom", category: "private")

    /// Reads every `--disable-private=<a,b>` argument. Only known capability names take effect;
    /// anything else is returned in `unknown` (T-02-04).
    public static func parseDisabled(_ arguments: [String]) -> (disabled: Set<Capability>, unknown: [String]) {
        var disabled: Set<Capability> = []
        var unknown: [String] = []
        for argument in arguments where argument.hasPrefix(flagPrefix) {
            for name in argument.dropFirst(flagPrefix.count).split(separator: ",") {
                if let capability = Capability(rawValue: String(name)) {
                    disabled.insert(capability)
                } else {
                    unknown.append(String(name))
                }
            }
        }
        return (disabled, unknown)
    }

    private static let launchFlags = parseDisabled(CommandLine.arguments)

    /// True when the launch arguments turned this capability off.
    public static func isForcedOff(_ capability: Capability) -> Bool {
        launchFlags.disabled.contains(capability)
    }

    /// Whether each capability is usable right now (session-aware).
    public static func report() -> [Capability: Bool] {
        Dictionary(uniqueKeysWithValues: Capability.allCases.map { ($0, isAvailable($0)) })
    }

    /// The process-wide session. Forced off at launch, missing, or switched off for the session all mean unavailable.
    public static let session = CapabilitySession(loaded: { capability in
        switch capability {
        case .axWindowID: AXWindowID.function != nil
        case .spaces: SkyLightSpaces.isLoaded
        case .multitouch: MultitouchSupport.isLoaded && !MultitouchCanary.tripped
        case .symbolicHotKeys, .coreDock: false
        }
    })

    public static func isAvailable(_ capability: Capability) -> Bool { session.isAvailable(capability) }

    /// An unexpected failure of the capability's private function (D-15 call-time degradation).
    public static func recordFailure(_ capability: Capability) { session.recordFailure(capability) }

    public static func recordSuccess(_ capability: Capability) { session.recordSuccess(capability) }

    public static var failureLimit: Int { CapabilitySession.failureLimit }

    /// Logs `name: available|off` per capability, and each unknown `--disable-private` name as an error.
    public static func logReport() {
        for capability in Capability.allCases {
            let state = isAvailable(capability) ? "available" : "off"
            logger.info("\(capability.rawValue, privacy: .public): \(state, privacy: .public)")
        }
        for name in launchFlags.unknown {
            logger.error("unknown --disable-private name ignored: \(name, privacy: .public)")
        }
    }
}

/// Call-time degradation (D-15): a capability whose private function exists but keeps failing is switched off for
/// the rest of the session. Safe from any AX thread; state sits behind one lock (`Mutex` needs macOS 15).
public final class CapabilitySession: Sendable {
    /// Consecutive unexpected failures that switch a capability off.
    public static let failureLimit = 5

    private struct State {
        var failures: [Capability: Int] = [:]
        var disabled: Set<Capability> = []
    }

    private let loaded: @Sendable (Capability) -> Bool
    private let state = OSAllocatedUnfairLock(initialState: State())

    /// `loaded` says whether the capability's private function resolved (and was not forced off at launch).
    public init(loaded: @escaping @Sendable (Capability) -> Bool) {
        self.loaded = loaded
    }

    public func isAvailable(_ capability: Capability) -> Bool {
        loaded(capability) && !state.withLock { $0.disabled.contains(capability) }
    }

    /// Counts one unexpected failure. Returns true only for the call that switched the capability off, which logs it.
    @discardableResult public func recordFailure(_ capability: Capability) -> Bool {
        guard loaded(capability) else { return false }
        let switchedOff = state.withLock { state -> Bool in
            guard !state.disabled.contains(capability) else { return false }
            state.failures[capability, default: 0] += 1
            guard state.failures[capability, default: 0] >= Self.failureLimit else { return false }
            state.disabled.insert(capability)
            return true
        }
        if switchedOff {
            Capabilities.logger.error(
                "\(capability.rawValue, privacy: .public) failed \(Self.failureLimit, privacy: .public) times in a row; off for this session, \(capability.fallback, privacy: .public)"
            )
        }
        return switchedOff
    }

    public func recordSuccess(_ capability: Capability) {
        state.withLock { $0.failures[capability] = 0 }
    }
}

/// Crash canary for MultitouchSupport (RESEARCH Pattern 6): its layouts are reverse-documented and can change with any
/// macOS update. `arm()` before the first risky call of a session, `clear()` only at a clean stop (zoom off,
/// quit). A canary still set at the next launch means that launch died with multitouch running: multitouch stays off
/// while the OS build and app version are the same, and is retried once either changes. Any crash or forced quit while
/// multitouch ran trips it, so the user can also turn it back on from the Debug menu (`turnBackOn`, WR-08).
public struct MultitouchCanary {
    public static let key = "privateCanary.Multitouch"

    private let defaults: UserDefaults
    private let osBuild: String
    private let appVersion: String

    public init(defaults: UserDefaults = .standard, osBuild: String = MultitouchCanary.currentOSBuild, appVersion: String = MultitouchCanary.currentAppVersion) {
        self.defaults = defaults
        self.osBuild = osBuild
        self.appVersion = appVersion
    }

    /// Decided once per launch, before any multitouch device is touched; only `turnBackOn` changes it later.
    private static let trippedState = OSAllocatedUnfairLock(initialState: MultitouchCanary().isTripped())
    public static var tripped: Bool { trippedState.withLock { $0 } }

    /// Debug ▸ Turn Multitouch Back On (WR-08): clears the canary, and multitouch is available again in this launch.
    public static func turnBackOn(_ canary: MultitouchCanary = MultitouchCanary()) {
        canary.clear()
        trippedState.withLock { $0 = false }
    }

    public func arm() {
        defaults.set(["osBuild": osBuild, "appVersion": appVersion, "started": Date()], forKey: Self.key)
    }

    public func clear() { defaults.removeObject(forKey: Self.key) }

    /// A leftover canary for this build and version trips (logged); one for another build or version is cleared.
    public func isTripped() -> Bool {
        guard let left = defaults.dictionary(forKey: Self.key) else { return false }
        let build = left["osBuild"] as? String ?? "?", version = left["appVersion"] as? String ?? "?"
        guard build == osBuild, version == appVersion else {
            clear()
            return false
        }
        Logger(subsystem: "com.eightabyte.transom", category: "gesture").error(
            "multitouch off: crash canary from last launch (build \(build, privacy: .public), version \(version, privacy: .public))")
        return true
    }

    /// `kern.osversion`, e.g. "26B123".
    public static var currentOSBuild: String {
        var size = 0
        guard sysctlbyname("kern.osversion", nil, &size, nil, 0) == 0, size > 0 else { return "?" }
        var buffer = [CChar](repeating: 0, count: size)
        guard sysctlbyname("kern.osversion", &buffer, &size, nil, 0) == 0 else { return "?" }
        return String(decoding: buffer.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self)
    }

    /// "{short version} ({build})" from the main bundle; "dev" outside an app bundle.
    public static var currentAppVersion: String {
        let info = Bundle.main.infoDictionary
        guard let short = info?["CFBundleShortVersionString"] as? String else { return "dev" }
        return "\(short) (\(info?["CFBundleVersion"] as? String ?? "?"))"
    }
}

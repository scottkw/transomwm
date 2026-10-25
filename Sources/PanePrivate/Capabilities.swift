import os

/// One private API Pane can run without. The raw value is the name used by `--disable-private=`.
public enum Capability: String, CaseIterable, Sendable {
    case axWindowID = "AXWindowID"
    case spaces = "Spaces"

    public var fallback: String { "" }
}

/// Registry of private-API capabilities (D-15, SAFE-05). Each capability is either loaded or off;
/// off means only the feature built on it degrades, never the launch.
public enum Capabilities {
    static let flagPrefix = "--disable-private="
    static let logger = Logger(subsystem: "com.eightabyte.pane", category: "private")

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
    static let session = CapabilitySession(loaded: { capability in
        switch capability {
        case .axWindowID: AXWindowID.function != nil
        case .spaces: SkyLightSpaces.isLoaded
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
                "\(capability.rawValue, privacy: .public) failed \(Self.failureLimit, privacy: .public) times in a row; off for this session, matching by frame"
            )
        }
        return switchedOff
    }

    public func recordSuccess(_ capability: Capability) {
        state.withLock { $0.failures[capability] = 0 }
    }
}

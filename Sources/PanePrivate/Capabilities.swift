import os

/// One private API Pane can run without. The raw value is the name used by `--disable-private=`.
public enum Capability: String, CaseIterable, Sendable {
    case axWindowID = "AXWindowID"
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

    /// Whether each capability is usable in this process.
    public static func report() -> [Capability: Bool] {
        Dictionary(uniqueKeysWithValues: Capability.allCases.map { ($0, isAvailable($0)) })
    }

    static func isAvailable(_ capability: Capability) -> Bool {
        switch capability {
        case .axWindowID: AXWindowID.function != nil
        }
    }

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

/// Call-time degradation state for the capabilities (stub).
public final class CapabilitySession: Sendable {
    private let loaded: @Sendable (Capability) -> Bool

    public init(loaded: @escaping @Sendable (Capability) -> Bool) {
        self.loaded = loaded
    }

    public func isAvailable(_ capability: Capability) -> Bool { loaded(capability) }

    @discardableResult public func recordFailure(_ capability: Capability) -> Bool { false }

    public func recordSuccess(_ capability: Capability) {}
}

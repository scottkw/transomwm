import Foundation

/// The `transom://` URL scheme of Phase 3 (SAFE-03, TILE-15, TILE-17, Pitfall 21, T-03-40): three parameterless commands, plus the 11 camera commands of Phase 4,
/// Show Overview (Phase 6) and the three tab commands (Phase 7).
/// Anything from any app or web page can open one, so the parser is a strict whitelist and nothing from the URL but the
/// chosen command goes anywhere.
public enum TransomURL {
    static let commands: [String: Command] = [
        "restore": .restoreAll, "toggle-desktop": .toggleDesktop, "split-finder": .finderSplit,
        // Phase 4: every camera command (04 UI-SPEC Hotkeys and URLs).
        "zoom-out": .camera(.zoomOutAll), "step-out": .camera(.stepOut), "step-in": .camera(.stepIn), "back": .camera(.back),
        "forward": .camera(.forward), "pan-left": .camera(.pan(.left)), "pan-right": .camera(.pan(.right)),
        "pan-up": .camera(.pan(.top)), "pan-down": .camera(.pan(.bottom)), "frame-window": .camera(.frameWindow),
        "frame-desktop": .camera(.frameDesktop),
        // Phase 6: toggles the overview, like its hotkey (06 UI-SPEC Surface 4).
        "overview": .camera(.overview),
        // Phase 7: the tab commands (07 UI-SPEC Surface 7).
        "next-tab": .tabs(.next), "previous-tab": .tabs(.previous), "move-out-of-group": .tabs(.moveOut),
    ]

    /// The command for `url`: exactly `scheme`, a lowercase command host, no user, password, port, query or fragment,
    /// and a path that is empty or "/". Nil for anything else.
    public static func parse(_ url: URL, scheme: String) -> Command? {
        guard let parts = URLComponents(url: url, resolvingAgainstBaseURL: false), parts.scheme == scheme,
            parts.percentEncodedUser == nil, parts.percentEncodedPassword == nil, parts.port == nil,
            parts.percentEncodedQuery == nil, parts.percentEncodedFragment == nil,
            parts.percentEncodedPath.isEmpty || parts.percentEncodedPath == "/", let host = parts.percentEncodedHost
        else { return nil }
        return commands[host]
    }
}

/// Each URL command runs at most once per second; a refused attempt does not restart the second.
public struct TransomURLRateLimiter: Sendable {
    public static let interval: Duration = .seconds(1)
    private var lastAdmitted: [Command: ContinuousClock.Instant] = [:]

    public init() {}

    public mutating func admit(_ command: Command, at now: ContinuousClock.Instant) -> Bool {
        if let last = lastAdmitted[command], now - last < Self.interval { return false }
        lastAdmitted[command] = now
        return true
    }
}

import Foundation

/// The `pane://` URL scheme of Phase 3 (SAFE-03, TILE-15, TILE-17, Pitfall 21, T-03-40): three parameterless commands.
/// Anything from any app or web page can open one, so the parser is a strict whitelist and nothing from the URL but the
/// chosen command goes anywhere.
public enum PaneURL {
    static let commands: [String: Command] = ["restore": .restoreAll, "toggle-desktop": .toggleDesktop, "split-finder": .finderSplit]

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
public struct PaneURLRateLimiter: Sendable {
    public static let interval: Duration = .seconds(1)
    private var lastAdmitted: [Command: ContinuousClock.Instant] = [:]

    public init() {}

    public mutating func admit(_ command: Command, at now: ContinuousClock.Instant) -> Bool {
        if let last = lastAdmitted[command], now - last < Self.interval { return false }
        lastAdmitted[command] = now
        return true
    }
}

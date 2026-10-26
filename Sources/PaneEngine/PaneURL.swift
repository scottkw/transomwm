import Foundation

public enum PaneURL {
    public static func parse(_ url: URL, scheme: String) -> Command? {
        nil  // RED stub
    }
}

public struct PaneURLRateLimiter: Sendable {
    public init() {}

    public mutating func admit(_ command: Command, at now: ContinuousClock.Instant) -> Bool {
        true  // RED stub
    }
}

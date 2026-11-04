import Foundation
import TransomEngine

/// The one allow-list check and rate limit for URL opens and CLI requests, so `transom://view/3` and `transom view 3` count
/// as the same command (D-06, D-07).
@MainActor final class CommandGate {
    enum Result: Equatable {
        case rejected, rateLimited
        case command(Command)
    }

    /// The scheme this build registered (`transom`, or `transom-debug` in Debug, A8); nil when run outside the app bundle.
    private let scheme: String?
    private var limiter = TransomURLRateLimiter()

    init(scheme: String?) {
        self.scheme = scheme
    }

    func admit(_ url: URL, at now: ContinuousClock.Instant) -> Result {
        guard let scheme, let command = TransomURL.parse(url, scheme: scheme) else { return .rejected }
        return limiter.admit(command, at: now) ? .command(command) : .rateLimited
    }
}

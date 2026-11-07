import Foundation
import TransomEngine

/// Asks GitHub for the latest release (gifsmith `Checker.Latest`). The request carries only Accept and a User-Agent with
/// the version: no credential, no cookie, nothing about the user or the Mac (T-09-18, RESEARCH Pitfall 3).
struct GitHubReleaseClient {
    /// A status other than 200 or 404 (rate limit, server error).
    struct HTTPStatusError: Error { let code: Int }

    private let session: URLSession
    private let userAgent: String

    /// Ephemeral with no URLCache, so Foundation never answers a 304 from its own cache and nothing is written to
    /// HTTPStorages (RESEARCH Pitfall 4).
    static func configuration() -> URLSessionConfiguration {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.urlCache = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        return configuration
    }

    init(configuration: URLSessionConfiguration, userAgent: String) {
        session = URLSession(configuration: configuration)
        self.userAgent = userAgent
    }

    /// 200 → the parsed release JSON; 404 (nothing published) → `.none`; anything else throws.
    func latest() async throws -> UpdateCheck {
        var request = URLRequest(url: UpdateFeed.latestURL)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        let (body, response) = try await session.data(for: request)
        let code = (response as? HTTPURLResponse)?.statusCode ?? 0
        switch code {
        case 200: return try UpdateFeed.parse(body)
        case 404: return .none
        default: throw HTTPStatusError(code: code)
        }
    }
}

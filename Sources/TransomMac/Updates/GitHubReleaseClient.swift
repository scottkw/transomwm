import Foundation
import TransomEngine

/// Asks GitHub for the latest release (gifsmith `Checker.Latest`). The request carries only Accept, a User-Agent with
/// the version and, after a 200, the stored ETag: no credential, no cookie, nothing about the user or the Mac (T-09-18,
/// RESEARCH Pitfall 3). A 304 costs nothing against the 60-an-hour unauthenticated limit and reuses the stored body.
final class GitHubReleaseClient {
    /// A status other than 200, 304 with a stored body, or 404 (rate limit, server error).
    struct HTTPStatusError: Error { let code: Int }

    private let session: URLSession
    private let userAgent: String
    /// From the last 200 that parsed.
    private var etag: String?
    private var body: Data?

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

    /// 200 → the parsed release JSON; 304 → the stored body; 404 (nothing published) → `.none`; anything else throws.
    func latest() async throws -> UpdateCheck {
        var request = URLRequest(url: UpdateFeed.latestURL)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        if let etag { request.setValue(etag, forHTTPHeaderField: "If-None-Match") }
        let (bytes, response) = try await session.bytes(for: request)
        let http = response as? HTTPURLResponse
        let code = http?.statusCode ?? 0
        switch code {
        case 200:
            // gifsmith's LimitReader(maxJSON + 1): an endless body is cut off, never buffered whole.
            var fresh = Data()
            for try await byte in bytes {
                fresh.append(byte)
                if fresh.count > UpdateFeed.maxJSONBytes { throw UpdateFeedError.bodyTooLarge }
            }
            let check = try UpdateFeed.parse(fresh)
            etag = http?.value(forHTTPHeaderField: "ETag")
            body = fresh
            return check
        case 304:
            guard let body else { throw HTTPStatusError(code: code) }
            return try UpdateFeed.parse(body)
        case 404: return .none
        default: throw HTTPStatusError(code: code)
        }
    }
}

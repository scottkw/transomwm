import Foundation
import TransomEngine
@testable import TransomMac
import Testing

/// Serves one canned response for every request and records the requests. Tests never reach the network: the client's
/// session has only this protocol class. Shared statics are safe because the suite is `.serialized`. Like gifsmith's
/// `serve`, a request whose If-None-Match equals `etag` gets an empty 304.
private final class StubURLProtocol: URLProtocol {
    nonisolated(unsafe) static var status = 200
    nonisolated(unsafe) static var body = Data()
    nonisolated(unsafe) static var etag: String?
    nonisolated(unsafe) static var requests: [URLRequest] = []

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        Self.requests.append(request)
        let notModified = Self.etag != nil && request.value(forHTTPHeaderField: "If-None-Match") == Self.etag
        let headers = Self.etag.map { ["ETag": $0] }
        let response = HTTPURLResponse(
            url: request.url!, statusCode: notModified ? 304 : Self.status, httpVersion: "HTTP/1.1", headerFields: headers)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        if !notModified { client?.urlProtocol(self, didLoad: Self.body) }
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

@Suite(.serialized) @MainActor struct UpdateCheckTests {
    static let digest = String(repeating: "ab", count: 32)
    /// GitHub's releases/latest shape, trimmed to the fields Transom reads plus a few it ignores.
    static let latestJSON = Data(
        """
        {
          "tag_name": "v0.9.0", "name": "Transom 0.9.0", "draft": false, "prerelease": false,
          "html_url": "https://github.com/scottkw/transomwm/releases/tag/v0.9.0",
          "assets": [
            {
              "name": "Transom-0.9.0-universal.dmg", "size": 7340032, "state": "uploaded",
              "content_type": "application/x-apple-diskimage", "digest": "sha256:\(digest)",
              "browser_download_url": "https://github.com/scottkw/transomwm/releases/download/v0.9.0/Transom-0.9.0-universal.dmg"
            }
          ]
        }
        """.utf8)

    init() {
        StubURLProtocol.status = 200
        StubURLProtocol.body = Self.latestJSON
        StubURLProtocol.etag = nil
        StubURLProtocol.requests = []
    }

    private func client(_ userAgent: String = "Transom") -> GitHubReleaseClient {
        let configuration = GitHubReleaseClient.configuration()
        configuration.protocolClasses = [StubURLProtocol.self]
        return GitHubReleaseClient(configuration: configuration, userAgent: userAgent)
    }

    /// A throwaway defaults domain, never the user's.
    private func withDefaults(_ body: (UserDefaults) throws -> Void) throws {
        let suite = "com.eightabyte.transom.tests.updates.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        try body(defaults)
    }

    private func controller(current: String, defaults: UserDefaults = UserDefaults(suiteName: "com.eightabyte.transom.tests.updates")!)
        -> UpdateController
    {
        UpdateController(client: client("Transom/\(current)"), currentVersion: current, build: "1", isEnabled: true, defaults: defaults)
    }

    @Test func aSecondCheckSendsTheETagAndReusesTheBodyOn304() async throws {
        StubURLProtocol.etag = "\"e1\""
        let releases = client()
        let first = try await releases.latest()
        guard case .release = first else { Issue.record("first check: \(first)"); return }
        let second = try await releases.latest()
        #expect(second == first)
        #expect(StubURLProtocol.requests.count == 2)
        #expect(StubURLProtocol.requests[0].value(forHTTPHeaderField: "If-None-Match") == nil)
        #expect(StubURLProtocol.requests[1].value(forHTTPHeaderField: "If-None-Match") == "\"e1\"")
    }

    @Test func a304WithNoStoredBodyIsAFailedCheck() async {
        StubURLProtocol.status = 304
        StubURLProtocol.body = Data()
        await #expect(throws: (any Error).self) { try await client().latest() }
        let updates = controller(current: "0.8.0")
        await updates.checkNow()
        #expect(updates.status == .idle)
        #expect(updates.error == .checkFailed)
    }

    @Test func rateLimitAnswersAreFailedChecks() async throws {
        for code in [403, 429, 500, 503] {
            StubURLProtocol.status = code
            await #expect(throws: (any Error).self, "\(code)") { try await client().latest() }
            let manual = controller(current: "0.8.0")
            await manual.checkNow()
            #expect(manual.status == .idle)
            #expect(manual.error == .checkFailed)
            let automatic = controller(current: "0.8.0")
            await automatic.checkNow(manual: false)
            #expect(automatic.status == .idle)
            #expect(automatic.error == nil)
        }
        StubURLProtocol.status = 404
        #expect(try await client().latest() == UpdateCheck.none)
    }

    @Test func anOversizedBodyIsAFailedCheck() async {
        StubURLProtocol.body = Self.latestJSON + Data(repeating: UInt8(ascii: " "), count: UpdateFeed.maxJSONBytes)
        await #expect(throws: (any Error).self) { try await client().latest() }
    }

    @Test func theAutomaticSwitchDefaultsOnAndPersists() throws {
        try withDefaults { defaults in
            let updates = controller(current: "0.8.0", defaults: defaults)
            #expect(UpdateController.automaticKey == "updates.automatic")
            #expect(updates.automatic)
            #expect(defaults.object(forKey: UpdateController.automaticKey) == nil)
            updates.automatic = false
            #expect(defaults.bool(forKey: UpdateController.automaticKey) == false)
            #expect(defaults.object(forKey: UpdateController.automaticKey) != nil)
            #expect(!controller(current: "0.8.0", defaults: defaults).automatic)
        }
        #expect(UpdateCopy.automaticToggle == "Check for updates automatically")
        #expect(
            UpdateCopy.automaticFooter
                == "Transom asks GitHub for the latest release when it opens and once a day. Nothing about you or your Mac is sent.")
    }

    @Test func aNewerPublishedReleaseIsAvailable() async {
        let updates = controller(current: "0.8.0")
        await updates.checkNow()
        let release = UpdateRelease(
            version: "0.9.0",
            url: URL(string: "https://github.com/scottkw/transomwm/releases/download/v0.9.0/Transom-0.9.0-universal.dmg")!,
            size: 7_340_032, sha256: Self.digest)
        #expect(updates.status == .available(release))
        #expect(release.assetName == "Transom-0.9.0-universal.dmg")
        #expect(release.notesURL.absoluteString == "https://github.com/scottkw/transomwm/releases/tag/v0.9.0")
    }

    @Test func anUninstallableReleaseIsNeverOffered() async {
        StubURLProtocol.body = Data(
            String(decoding: Self.latestJSON, as: UTF8.self)
                .replacingOccurrences(of: "0.9.0", with: "9.9.9")
                .replacingOccurrences(of: "https://github.com/scottkw/transomwm/releases/download/", with: "https://evil.example/")
                .utf8)
        let updates = controller(current: "0.8.0")
        await updates.checkNow()
        #expect(updates.status == .current("0.8.0"))
    }

    @Test func theSameVersionIsCurrent() async {
        let updates = controller(current: "0.9.0")
        await updates.checkNow()
        #expect(updates.status == .current("0.9.0"))
    }

    @Test func theRequestAsksGitHubForTheLatestReleaseJSON() async throws {
        await controller(current: "0.8.0").checkNow()
        let request = try #require(StubURLProtocol.requests.first)
        #expect(StubURLProtocol.requests.count == 1)
        #expect(request.url?.absoluteString == "https://api.github.com/repos/scottkw/transomwm/releases/latest")
        #expect(request.httpMethod == "GET")
        #expect(request.value(forHTTPHeaderField: "Accept") == "application/vnd.github+json")
        #expect(request.value(forHTTPHeaderField: "User-Agent") == "Transom/0.8.0")
        #expect(request.value(forHTTPHeaderField: "Authorization") == nil)
        #expect(request.value(forHTTPHeaderField: "Cookie") == nil)
        let configuration = GitHubReleaseClient.configuration()
        #expect(configuration.urlCache == nil)
        #expect(configuration.requestCachePolicy == .reloadIgnoringLocalCacheData)
    }

    @Test func theVersionLineAndStatusLinesAreTheUISpecCopy() {
        let release = UpdateRelease(
            version: "1.0.0", url: URL(string: "https://github.com/scottkw/transomwm/releases/download/v1.0.0/x")!, size: 1,
            sha256: Self.digest)
        #expect(UpdateCopy.versionLine("0.9.0", "1") == "Transom 0.9.0 (1)")
        #expect(UpdateCopy.statusLine(.idle, current: "0.9.0") == nil)
        #expect(UpdateCopy.statusLine(.checking, current: "0.9.0") == "Checking for updates\u{2026}")
        #expect(UpdateCopy.statusLine(.current("0.9.0"), current: "0.9.0") == "Transom 0.9.0 is up to date.")
        #expect(UpdateCopy.statusLine(.available(release), current: "0.9.0") == "Transom 1.0.0 is available. You have 0.9.0.")
        #expect(UpdateCopy.checkForUpdates == "Check for Updates")
        #expect(UpdateCopy.releaseNotes == "Release Notes")
        #expect(UpdateCopy.errorLine(.checkFailed) == "Couldn't check for updates. Check your connection, then try again.")
    }

    @Test func theUpdaterIsOffOutsideAReleaseBundle() async {
        #expect(UpdateController.isEnabled(bundleID: "com.eightabyte.transom", version: "0.9.0"))
        #expect(!UpdateController.isEnabled(bundleID: "com.eightabyte.transom.debug", version: "0.9.0"))
        #expect(!UpdateController.isEnabled(bundleID: "com.eightabyte.transom", version: nil))
        #expect(!UpdateController.isEnabled(bundleID: nil, version: "0.9.0"))
        // A disabled controller never asks GitHub.
        let configuration = GitHubReleaseClient.configuration()
        configuration.protocolClasses = [StubURLProtocol.self]
        let off = UpdateController(
            client: GitHubReleaseClient(configuration: configuration, userAgent: "Transom"), currentVersion: "dev", build: "?",
            isEnabled: false, defaults: UserDefaults(suiteName: "com.eightabyte.transom.tests.updates")!)
        await off.checkNow()
        #expect(off.status == .idle)
        #expect(StubURLProtocol.requests.isEmpty)
    }
}

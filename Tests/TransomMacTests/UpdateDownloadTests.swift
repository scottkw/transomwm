import CryptoKit
import Foundation
import TransomEngine
@testable import TransomMac
import Testing

/// Serves `body` for every request, or first a 302 to `redirect`. Tests never reach the network: the downloader's
/// session has only this protocol class. Its own statics (not `UpdateCheckTests`' stub), because suites run in parallel.
private final class DownloadStub: URLProtocol {
    nonisolated(unsafe) static var body = Data()
    nonisolated(unsafe) static var redirect: URL?
    nonisolated(unsafe) static var requests: [URL] = []

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let url = request.url!
        Self.requests.append(url)
        if let redirect = Self.redirect, url != redirect {
            let response = HTTPURLResponse(
                url: url, statusCode: 302, httpVersion: "HTTP/1.1", headerFields: ["Location": redirect.absoluteString])!
            client?.urlProtocol(self, wasRedirectedTo: URLRequest(url: redirect), redirectResponse: response)
            client?.urlProtocolDidFinishLoading(self)
            return
        }
        let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Self.body)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

/// What the fake `open` was handed (a box: the closure may not mutate a captured var).
private final class Opened { var urls: [URL] = [] }

@Suite(.serialized) @MainActor struct UpdateDownloadTests {
    static let bytes = Data("not really a disk image, but the digest is real".utf8)
    static let url = URL(string: "https://github.com/scottkw/transomwm/releases/download/v0.9.0/Transom-0.9.0-universal.dmg")!
    static let release = UpdateRelease(
        version: "0.9.0", url: url, size: Int64(bytes.count),
        sha256: SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined())

    let directory: URL

    init() throws {
        DownloadStub.body = Self.bytes
        DownloadStub.redirect = nil
        DownloadStub.requests = []
        directory = FileManager.default.temporaryDirectory.appending(path: "transom-updates-\(UUID().uuidString)")
    }

    private func downloader() -> DMGDownloader {
        let configuration = GitHubReleaseClient.configuration()
        configuration.protocolClasses = [DownloadStub.self]
        return DMGDownloader(configuration: configuration, directory: directory)
    }

    /// A controller already showing `release` as available. Never the user's defaults domain or caches folder.
    private func controller(
        _ release: UpdateRelease = release, verify: @escaping @Sendable (URL) -> OSStatus = { _ in errSecSuccess },
        opened: Opened, openResult: Bool = true
    ) async -> UpdateController {
        let feed = GitHubReleaseClient.configuration()
        feed.protocolClasses = [FeedStub.self]
        FeedStub.release = release
        let updates = UpdateController(
            client: GitHubReleaseClient(configuration: feed, userAgent: "Transom"), currentVersion: "0.8.0", build: "1",
            isEnabled: true, defaults: UserDefaults(suiteName: "com.eightabyte.transom.tests.updates")!,
            downloader: downloader(), verify: verify,
            open: { url in
                opened.urls.append(url)
                return openResult
            })
        await updates.checkNow()
        #expect(updates.status == .available(release))
        return updates
    }

    private func leftovers() -> [String] {
        (try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []
    }

    @Test func aMatchingDownloadIsVerifiedQuarantinedAndOpened() async throws {
        defer { try? FileManager.default.removeItem(at: directory) }
        let opened = Opened()
        let updates = await controller(opened: opened)
        await updates.downloadAndOpen()
        #expect(updates.status == .opened(Self.release))
        #expect(updates.error == nil)
        let file = directory.appending(path: "Transom-0.9.0-universal.dmg")
        #expect(opened.urls == [file])
        #expect(leftovers() == ["Transom-0.9.0-universal.dmg"])
        let flag = try #require(xattr(file, "com.apple.quarantine"))
        #expect(flag.hasPrefix("0081;") && flag.hasSuffix(";Transom;"))
        let mode = try FileManager.default.attributesOfItem(atPath: directory.path)[.posixPermissions] as? Int
        #expect(mode == 0o700)
        #expect(DownloadStub.requests == [Self.url])
    }

    @Test func aWrongDigestDeletesTheFileAndOpensNothing() async {
        defer { try? FileManager.default.removeItem(at: directory) }
        let opened = Opened()
        let swapped = UpdateRelease(
            version: "0.9.0", url: Self.url, size: Self.release.size, sha256: String(repeating: "0", count: 64))
        let updates = await controller(swapped, opened: opened)
        await updates.downloadAndOpen()
        #expect(updates.error == .verifyFailed)
        #expect(updates.status == .available(swapped))
        #expect(opened.urls.isEmpty)
        #expect(leftovers().isEmpty)
    }

    @Test func aShortDownloadDeletesTheFile() async {
        defer { try? FileManager.default.removeItem(at: directory) }
        // One byte short of the asset size, then one byte over it.
        for size in [Self.release.size + 1, Self.release.size - 1] {
            let opened = Opened()
            let wrongSize = UpdateRelease(version: "0.9.0", url: Self.url, size: size, sha256: Self.release.sha256)
            let updates = await controller(wrongSize, opened: opened)
            await updates.downloadAndOpen()
            #expect(updates.error == .verifyFailed, "size \(size)")
            #expect(opened.urls.isEmpty)
            #expect(leftovers().isEmpty, "size \(size)")
        }
    }

    @Test func aRedirectOffTheAllowListIsRefused() async {
        defer { try? FileManager.default.removeItem(at: directory) }
        let evil = URL(string: "https://evil.example/x.dmg")!
        DownloadStub.redirect = evil
        let opened = Opened()
        let updates = await controller(opened: opened)
        await updates.downloadAndOpen()
        #expect(updates.error == .downloadFailed(version: "0.9.0"))
        #expect(updates.status == .available(Self.release))
        #expect(!DownloadStub.requests.contains(evil))
        #expect(opened.urls.isEmpty)
        #expect(leftovers().isEmpty)
        // An allow-listed CDN redirect is followed.
        DownloadStub.redirect = URL(string: "https://release-assets.githubusercontent.com/x")!
        await updates.downloadAndOpen()
        #expect(updates.status == .opened(Self.release))
    }

    @Test func aFailedSignatureDeletesTheFileAndOpensNothing() async {
        defer { try? FileManager.default.removeItem(at: directory) }
        let opened = Opened()
        // errSecCSReqFailed: another team's signature.
        let updates = await controller(verify: { _ in -67050 }, opened: opened)
        await updates.downloadAndOpen()
        #expect(updates.error == .verifyFailed)
        #expect(updates.status == .available(Self.release))
        #expect(opened.urls.isEmpty)
        #expect(leftovers().isEmpty)
    }

    @Test func aFailedOpenGoesBackToAvailable() async {
        defer { try? FileManager.default.removeItem(at: directory) }
        let opened = Opened()
        let updates = await controller(opened: opened, openResult: false)
        await updates.downloadAndOpen()
        #expect(updates.error == .openFailed)
        #expect(updates.status == .available(Self.release))
        #expect(opened.urls.count == 1)
    }

    @Test func cleanRemovesOnlyTransomsOwnFiles() throws {
        defer { try? FileManager.default.removeItem(at: directory) }
        let files = FileManager.default
        try files.createDirectory(at: directory, withIntermediateDirectories: true)
        let own = ["Transom-0.8.0-universal.dmg", "Transom-0.9.0-universal.dmg.part"]
        let others = ["notes.txt", "Transom-0.9.0-arm64.dmg", "Gifsmith-1.0.0-arm64.dmg", "Transom.dmg"]
        for name in own + others { try Data("x".utf8).write(to: directory.appending(path: name)) }
        // A folder that matches the pattern is not a file Transom wrote.
        try files.createDirectory(at: directory.appending(path: "Transom-1.0.0-universal.dmg"), withIntermediateDirectories: false)
        try downloader().clean()
        #expect(Set(leftovers()) == Set(others + ["Transom-1.0.0-universal.dmg"]))
        // A missing folder is fine.
        try files.removeItem(at: directory)
        try downloader().clean()
    }

    @Test func homebrewIsDetectedFromEitherCaskroom() {
        #expect(InstallLocation.caskroomPaths == ["/opt/homebrew/Caskroom/transom", "/usr/local/Caskroom/transom"])
        for path in InstallLocation.caskroomPaths {
            #expect(InstallLocation.isHomebrew(exists: { $0 == path }), "\(path)")
        }
        #expect(!InstallLocation.isHomebrew(exists: { _ in false }))
        #expect(!InstallLocation.isHomebrew(exists: { $0 == "/opt/homebrew/Caskroom/transom-beta" }))
        let brew = UpdateController(
            client: GitHubReleaseClient(configuration: GitHubReleaseClient.configuration(), userAgent: "Transom"),
            currentVersion: "0.8.0", build: "1", isEnabled: false,
            defaults: UserDefaults(suiteName: "com.eightabyte.transom.tests.updates")!, downloader: downloader(),
            fileExists: { $0 == "/usr/local/Caskroom/transom" })
        #expect(brew.installedWithHomebrew)
    }

    @Test func theDownloadStatusLinesAreTheUISpecCopy() {
        let release = Self.release
        #expect(UpdateCopy.statusLine(.downloading(release, fraction: 0.42), current: "0.8.0") == "Downloading Transom 0.9.0\u{2026} 42%")
        #expect(UpdateCopy.statusLine(.downloading(release, fraction: nil), current: "0.8.0") == "Downloading Transom 0.9.0\u{2026}")
        #expect(UpdateCopy.statusLine(.verifying(release), current: "0.8.0") == "Checking the download's signature\u{2026}")
        #expect(
            UpdateCopy.statusLine(.opened(release), current: "0.8.0")
                == "The Transom 0.9.0 disk image is open. Quit Transom, then drag the new Transom to Applications and choose Replace.")
        #expect(UpdateCopy.errorLine(.downloadFailed(version: "0.9.0")) == "Couldn't download Transom 0.9.0. Check your connection, then try again.")
        #expect(UpdateCopy.errorLine(.verifyFailed) == "The download didn't pass the signature check, so Transom deleted it. Nothing was opened.")
        #expect(UpdateCopy.errorLine(.openFailed) == "Transom couldn't open the downloaded disk image. Try again.")
        #expect(UpdateCopy.downloadAndOpen == "Download and Open")
        #expect(UpdateCopy.copyCommand == "Copy Command")
        #expect(UpdateCopy.quitTransom == "Quit Transom")
        #expect(UpdateCopy.homebrewIntro == "Transom was installed with Homebrew. To update, run this in Terminal:")
        #expect(UpdateCopy.homebrewCommand == "brew upgrade --cask transom")
    }

    private func xattr(_ file: URL, _ name: String) -> String? {
        let size = getxattr(file.path, name, nil, 0, 0, 0)
        guard size > 0 else { return nil }
        var buffer = [UInt8](repeating: 0, count: size)
        guard getxattr(file.path, name, &buffer, size, 0, 0) == size else { return nil }
        return String(decoding: buffer, as: UTF8.self)
    }
}

/// releases/latest offering `release`, so the controller reaches available the way the app does.
private final class FeedStub: URLProtocol {
    nonisolated(unsafe) static var release: UpdateRelease?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let release = Self.release!
        let json = """
            {"tag_name": "v\(release.version)", "assets": [{"name": "\(release.assetName)", "size": \(release.size),
            "state": "uploaded", "digest": "sha256:\(release.sha256)", "browser_download_url": "\(release.url.absoluteString)"}]}
            """
        let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(json.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

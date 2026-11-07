import Foundation

/// MAJOR.MINOR.PATCH with an optional leading v; no pre-release, no leading zeros (gifsmith `versionRE`).
public enum UpdateVersion {
    public static func parse(_ string: String) -> (major: Int, minor: Int, patch: Int)? {
        guard let m = string.wholeMatch(of: #/v?(0|[1-9][0-9]{0,5})\.(0|[1-9][0-9]{0,5})\.(0|[1-9][0-9]{0,5})/#) else {
            return nil
        }
        // At most six digits each, so Int(_:) cannot fail.
        return (Int(m.1)!, Int(m.2)!, Int(m.3)!)
    }

    /// -1, 0 or 1 as `lhs` is older than, equal to or newer than `rhs`; nil when either is not a version.
    public static func compare(_ lhs: String, _ rhs: String) -> Int? {
        guard let a = parse(lhs), let b = parse(rhs) else { return nil }
        let left = [a.major, a.minor, a.patch]
        let right = [b.major, b.minor, b.patch]
        if left == right { return 0 }
        return left.lexicographicallyPrecedes(right) ? -1 : 1
    }
}

/// The validated DMG of a published release (SHIP-04).
public struct UpdateRelease: Equatable, Sendable {
    /// Without the leading v.
    public let version: String
    /// Built from the validated version, never read from JSON.
    public let assetName: String
    public let url: URL
    public let size: Int64
    /// Lowercase hex.
    public let sha256: String
    /// The GitHub release page, built from the version, never read from JSON.
    public let notesURL: URL

    public init(version: String, url: URL, size: Int64, sha256: String) {
        self.version = version
        assetName = UpdateFeed.assetName(version)
        self.url = url
        self.size = size
        self.sha256 = sha256
        notesURL = URL(string: "https://github.com/\(UpdateFeed.repo)/releases/tag/v\(version)")!
    }
}

/// What releases/latest says: nothing usable, a release without a valid DMG, or an installable release.
public enum UpdateCheck: Equatable, Sendable {
    case none
    case notInstallable(version: String)
    case release(UpdateRelease)
}

public enum UpdateFeedError: Error, Equatable {
    case bodyTooLarge
}

/// The GitHub Releases feed rules, ported from gifsmith `internal/update/update.go` (D-09, T-09-17).
public enum UpdateFeed {
    public static let repo = "scottkw/transomwm"
    public static let teamID = "S2K7P43927"
    public static let maxDMGBytes: Int64 = 200 << 20
    public static let maxJSONBytes = 1 << 20
    public static let latestURL = URL(string: "https://api.github.com/repos/\(repo)/releases/latest")!

    /// The only release asset Transom downloads (release.sh's DMG name).
    public static func assetName(_ version: String) -> String { "Transom-\(version)-universal.dmg" }

    /// https to this repo's release downloads or the two asset CDN hosts GitHub redirects to. Hosts are compared exactly,
    /// never by suffix.
    public static func isAllowedDownload(_ url: URL) -> Bool {
        let path = url.path(percentEncoded: false)
        guard url.scheme == "https", url.user == nil, url.password == nil, url.port == nil, !path.contains("..") else {
            return false
        }
        switch url.host(percentEncoded: false) {
        case "github.com": return path.hasPrefix("/\(repo)/releases/download/")
        case "objects.githubusercontent.com", "release-assets.githubusercontent.com": return true
        default: return false
        }
    }

    /// Draft, prerelease or a tag that is not v + MAJOR.MINOR.PATCH → `.none`. A release whose DMG asset is missing,
    /// not uploaded, out of size bounds, without a `sha256:` digest or off the allow-list → `.notInstallable`.
    public static func parse(_ body: Data) throws -> UpdateCheck {
        guard body.count <= maxJSONBytes else { throw UpdateFeedError.bodyTooLarge }
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let raw = try decoder.decode(Raw.self, from: body)
        guard raw.draft != true, raw.prerelease != true, UpdateVersion.parse(raw.tagName) != nil else { return .none }
        let version = raw.tagName.hasPrefix("v") ? String(raw.tagName.dropFirst()) : raw.tagName
        let name = assetName(version)
        guard let asset = (raw.assets ?? []).first(where: { $0.name == name }), asset.state == "uploaded",
            (1...maxDMGBytes).contains(asset.size), let hex = asset.digest.flatMap(sha256Hex),
            let url = URL(string: asset.browserDownloadUrl), isAllowedDownload(url)
        else { return .notInstallable(version: version) }
        return .release(UpdateRelease(version: version, url: url, size: asset.size, sha256: hex))
    }

    /// The hex of `sha256:` + 64 lowercase hex digits, else nil.
    static func sha256Hex(_ digest: String) -> String? {
        digest.wholeMatch(of: #/sha256:([0-9a-f]{64})/#).map { String($0.1) }
    }

    private struct Raw: Decodable {
        let tagName: String
        // Absent reads as false / empty, like Go's zero values in gifsmith.
        let draft: Bool?
        let prerelease: Bool?
        let assets: [Asset]?

        struct Asset: Decodable {
            let name: String
            let size: Int64
            let state: String
            let browserDownloadUrl: String
            let digest: String?
        }
    }
}

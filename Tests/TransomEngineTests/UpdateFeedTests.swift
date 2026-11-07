import Foundation
import TransomEngine
import Testing

/// gifsmith `internal/update/update_test.go`, ported (D-09, T-09-20). Every rule that keeps an uninstallable release
/// from being offered is pinned here.
struct UpdateFeedTests {
    static let digest = "sha256:" + "0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef"
    static let name = UpdateFeed.assetName("1.1.0")

    static func asset(_ name: String = name, _ changes: [String: Any] = [:]) -> [String: Any] {
        var asset: [String: Any] = [
            "name": name, "size": 1234, "state": "uploaded", "digest": digest,
            "browser_download_url": "https://github.com/scottkw/transomwm/releases/download/v1.1.0/\(name)",
        ]
        asset.merge(changes) { _, new in new }
        return asset
    }

    static func release(_ tag: String = "v1.1.0", assets: [[String: Any]]? = nil, changes: [String: Any] = [:]) -> Data {
        let version = tag.hasPrefix("v") ? String(tag.dropFirst()) : tag
        var json: [String: Any] = [
            "tag_name": tag, "draft": false, "prerelease": false, "assets": assets ?? [asset(UpdateFeed.assetName(version))],
        ]
        json.merge(changes) { _, new in new }
        return try! JSONSerialization.data(withJSONObject: json)
    }

    @Test func versionsCompareLikeGifsmith() {
        let rows: [(String, String, Int)] = [
            ("1.0.0", "1.0.1", -1), ("1.0.1", "1.1.0", -1), ("1.1.0", "2.0.0", -1),
            ("1.10.0", "1.9.0", 1), ("v1.2.3", "1.2.3", 0), ("2.0.0", "1.99.99", 1),
        ]
        for (a, b, want) in rows {
            #expect(UpdateVersion.compare(a, b) == want, "\(a) vs \(b)")
        }
        #expect(UpdateVersion.compare("1.0", "1.0.0") == nil)
    }

    @Test func versionParsingRefusesLeadingZerosAndExtraParts() {
        let parsed = UpdateVersion.parse("v1.10.3")
        #expect(parsed?.major == 1 && parsed?.minor == 10 && parsed?.patch == 3)
        #expect(UpdateVersion.parse("v1.0.0") != nil)
        #expect(UpdateVersion.parse("999999.0.0") != nil)
        let refused = [
            "", "v", "1.2", "1.0", "1.2.3.4", "1.2.3-beta.1", "1.0.0-beta", "1.2.x", " 1.2.3", "01.2.3", "01.0.0",
            "1234567.0.0", "1.0.1234567", "V1.0.0",
        ]
        for string in refused {
            #expect(UpdateVersion.parse(string) == nil, "\(string) accepted")
        }
    }

    @Test func theAssetNameIsBuiltFromTheVersion() {
        #expect(UpdateFeed.assetName("1.1.0") == "Transom-1.1.0-universal.dmg")
    }

    @Test func aPublishedReleaseWithAValidDMGIsInstallable() throws {
        let url = URL(string: "https://github.com/scottkw/transomwm/releases/download/v1.1.0/\(Self.name)")!
        let want = UpdateRelease(version: "1.1.0", url: url, size: 1234, sha256: String(Self.digest.dropFirst(7)))
        #expect(try UpdateFeed.parse(Self.release()) == .release(want))
    }

    @Test func aDraftAPrereleaseOrABadTagIsNoRelease() throws {
        #expect(try UpdateFeed.parse(Self.release(changes: ["draft": true])) == UpdateCheck.none)
        #expect(try UpdateFeed.parse(Self.release(changes: ["prerelease": true])) == UpdateCheck.none)
        #expect(try UpdateFeed.parse(Self.release("v1.1")) == UpdateCheck.none)
        #expect(try UpdateFeed.parse(Self.release("latest")) == UpdateCheck.none)
        #expect(try UpdateFeed.parse(Self.release("v1.1.0-beta.1")) == UpdateCheck.none)
    }

    @Test func aMissingNotUploadedOrOversizedAssetIsNotInstallable() throws {
        let cases: [String: [[String: Any]]] = [
            "missing": [Self.asset("Transom-1.1.0-arm64.dmg")],
            "traversal": [Self.asset("../" + Self.name)],
            "zip": [Self.asset(Self.name + ".zip")],
            "starter": [Self.asset(Self.name, ["state": "starter"])],
            "size 0": [Self.asset(Self.name, ["size": 0])],
            "too large": [Self.asset(Self.name, ["size": UpdateFeed.maxDMGBytes + 1])],
            "empty asset": [],
        ]
        for (label, assets) in cases {
            #expect(try UpdateFeed.parse(Self.release(assets: assets)) == .notInstallable(version: "1.1.0"), "\(label)")
        }
        // gifsmith's bodies leave out draft and prerelease: absent reads as false, not as bad JSON.
        let bare = try JSONSerialization.data(withJSONObject: ["tag_name": "v1.1.0"])
        #expect(try UpdateFeed.parse(bare) == .notInstallable(version: "1.1.0"))
        #expect(try UpdateFeed.parse(Self.release(assets: [Self.asset(Self.name, ["size": UpdateFeed.maxDMGBytes])])) != .notInstallable(version: "1.1.0"))
    }

    @Test func aMissingOrMalformedDigestIsNotInstallable() throws {
        var noKey = Self.asset()
        noKey["digest"] = nil
        let cases: [String: [String: Any]] = [
            "no key": noKey,
            "empty": Self.asset(Self.name, ["digest": ""]),
            "null": Self.asset(Self.name, ["digest": NSNull()]),
            "sha1": Self.asset(Self.name, ["digest": "sha1:0123456789abcdef0123456789abcdef01234567"]),
            "bad hex": Self.asset(Self.name, ["digest": "sha256:XYZ"]),
            "upper hex": Self.asset(Self.name, ["digest": Self.digest.uppercased()]),
            "short": Self.asset(Self.name, ["digest": String(Self.digest.dropLast())]),
        ]
        for (label, asset) in cases {
            #expect(try UpdateFeed.parse(Self.release(assets: [asset])) == .notInstallable(version: "1.1.0"), "\(label)")
        }
    }

    @Test func aReleaseOnAHostOutsideTheAllowListIsNotInstallable() throws {
        let rows: [String: Bool] = [
            "https://github.com/scottkw/transomwm/releases/download/v1.1.0/Transom-1.1.0-universal.dmg": true,
            "https://objects.githubusercontent.com/x": true,
            "https://release-assets.githubusercontent.com/x": true,
            "https://github.com/other/repo/releases/download/v1.1.0/x.dmg": false,
            "https://github.com/scottkw/transomwm-evil/releases/download/v1.1.0/x.dmg": false,
            "http://github.com/scottkw/transomwm/releases/download/v1.1.0/x.dmg": false,
            "http://objects.githubusercontent.com/x": false,
            "https://user@github.com/scottkw/transomwm/releases/download/v1.1.0/x.dmg": false,
            "https://user:pw@objects.githubusercontent.com/x": false,
            "https://github.com/scottkw/transomwm/releases/download/../../other/repo/x.dmg": false,
            "https://github.com/scottkw/transomwm/releases/download/%2E%2E/%2E%2E/other/repo/x.dmg": false,
            "https://github.com:8443/scottkw/transomwm/releases/download/v1.1.0/x.dmg": false,
            "https://evil-github.com/scottkw/transomwm/releases/download/v1.1.0/x.dmg": false,
            "https://github.com.evil.com/scottkw/transomwm/releases/download/v1.1.0/x.dmg": false,
            "https://github.com.evil.example/scottkw/transomwm/releases/download/v1.1.0/x.dmg": false,
            "https://evil.githubusercontent.com/x": false,
            "https://objects.githubusercontent.com.evil/x": false,
            "https://evil.example/Transom-1.1.0-universal.dmg": false,
            "file:///tmp/Transom-1.1.0-universal.dmg": false,
        ]
        for (raw, want) in rows {
            let url = try #require(URL(string: raw))
            #expect(UpdateFeed.isAllowedDownload(url) == want, "\(raw)")
        }
        for raw in rows.keys where rows[raw] == false {
            let assets = [Self.asset(Self.name, ["browser_download_url": raw])]
            #expect(try UpdateFeed.parse(Self.release(assets: assets)) == .notInstallable(version: "1.1.0"), "\(raw)")
        }
        let unparseable = [Self.asset(Self.name, ["browser_download_url": "https://exa mple.com/x"])]
        #expect(try UpdateFeed.parse(Self.release(assets: unparseable)) == .notInstallable(version: "1.1.0"))
    }

    @Test func aBodyOverOneMebibyteIsRefused() throws {
        let big = Data(#"{"tag_name":"v1.1.0","body":""#.utf8) + Data(repeating: UInt8(ascii: "x"), count: 1 << 20)
            + Data(#""}"#.utf8)
        #expect(throws: UpdateFeedError.bodyTooLarge) { try UpdateFeed.parse(big) }
        // Just under the cap is read.
        var padded = Self.release()
        padded.append(Data(repeating: UInt8(ascii: " "), count: UpdateFeed.maxJSONBytes - padded.count))
        #expect(padded.count == UpdateFeed.maxJSONBytes)
        #expect(try UpdateFeed.parse(padded) != UpdateCheck.none)
        #expect(throws: (any Error).self) { try UpdateFeed.parse(Data("not json".utf8)) }
    }
}

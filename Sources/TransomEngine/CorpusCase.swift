import Foundation

/// One recorded window of a real app, labelled by a person (D-07). Written by `transom-dump`, read by the corpus test.
/// It never holds a title, path, URL or account name: the title is kept only as its length (T-02-08).
public struct CorpusCase: Codable, Equatable, Sendable {
    public struct CapturedOn: Codable, Equatable, Sendable {
        public var macOS: String
        public var appVersion: String
        public var date: String

        public init(macOS: String, appVersion: String, date: String) {
            self.macOS = macOS
            self.appVersion = appVersion
            self.date = date
        }
    }

    public struct App: Codable, Equatable, Sendable {
        public var bundleID: String
        /// native | electron | java | office
        public var family: String
        public var activationPolicy: String
        public var hidden: Bool

        public init(bundleID: String, family: String, activationPolicy: String, hidden: Bool) {
            self.bundleID = bundleID
            self.family = family
            self.activationPolicy = activationPolicy
            self.hidden = hidden
        }
    }

    public struct Title: Codable, Equatable, Sendable {
        public var redacted: Bool
        public var length: Int

        public init(redacted: Bool, length: Int) {
            self.redacted = redacted
            self.length = length
        }
    }

    /// The label. Set by the person capturing the case, never from the classifier's output (Pitfall 6).
    public struct Expected: Codable, Equatable, Sendable {
        /// dockable | neverDock | notAWindow
        public var kind: String
        /// A `NeverDockReason` raw value, or nil when the label does not name one.
        public var reason: String?
        /// "executor-proposed" until the developer reviews the case and sets "developer".
        public var confirmedBy: String

        public init(kind: String, reason: String?, confirmedBy: String) {
            self.kind = kind
            self.reason = reason
            self.confirmedBy = confirmedBy
        }
    }

    public static let currentSchemaVersion = 1
    public static let maxEncodedBytes = 64 * 1024

    public var schemaVersion: Int
    public var caseName: String
    public var capturedOn: CapturedOn
    public var app: App
    public var window: WindowSnapshot
    public var title: Title
    public var expected: Expected

    enum CodingKeys: String, CodingKey {
        case schemaVersion, capturedOn, app, window, title, expected
        case caseName = "case"
    }

    public init(caseName: String, capturedOn: CapturedOn, app: App, window: WindowSnapshot, title: Title, expected: Expected) {
        schemaVersion = Self.currentSchemaVersion
        self.caseName = caseName
        self.capturedOn = capturedOn
        self.app = app
        self.window = window
        self.title = title
        self.expected = expected
    }

    public enum DecodeError: Error, Equatable {
        case tooLarge(bytes: Int)
        case newerVersion(found: Int)
        case corrupt(String)
    }

    /// Size-capped, schema-probed decode (same order as `World.decode`, T-02-10).
    public static func decode(_ data: Data) throws(DecodeError) -> CorpusCase {
        guard data.count <= maxEncodedBytes else { throw .tooLarge(bytes: data.count) }
        struct VersionProbe: Decodable { let schemaVersion: Int }
        let decoder = JSONDecoder()
        do {
            let version = try decoder.decode(VersionProbe.self, from: data).schemaVersion
            guard version <= currentSchemaVersion else { throw DecodeError.newerVersion(found: version) }
            return try decoder.decode(CorpusCase.self, from: data)
        } catch let error as DecodeError {
            throw error
        } catch {
            throw .corrupt(String(describing: error))
        }
    }
}

import Foundation

public enum PersistenceError: Error, Equatable, Sendable {
    case corrupt(String)
    case newerVersion(found: Int, supported: Int)
    case missingMigration(from: Int)
    case invalidLayout(LayoutError)
    case tooLarge(bytes: Int, limit: Int)
    case encodingFailed(String)
}

extension World {
    /// JSON with sorted keys; World and LayoutTree sort their arrays, so equal worlds give equal bytes.
    public func encoded() throws(PersistenceError) -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        do {
            return try encoder.encode(self)
        } catch {
            throw PersistenceError.encodingFailed(String(describing: error))
        }
    }

    /// Largest file `decode` will parse (threat T-01-09).
    public static let maxEncodedBytes = 16 * 1024 * 1024

    public static func decode(from data: Data) throws(PersistenceError) -> World {
        try decode(from: data, migrations: .standard)
    }

    /// Decodes a saved World. Throws `.newerVersion` for a file written by a newer Transom: the caller
    /// should tell the user it was "saved by a newer version of Transom" and must not overwrite the file
    /// (threat T-01-10). Files older than schema 1, the oldest `World.init(from:)` reads itself (as legacy, dropping the
    /// old Desktop node), are upgraded through `migrations` to schema 1 one version at a time.
    public static func decode(from data: Data, migrations: MigrationChain) throws(PersistenceError) -> World {
        guard data.count <= maxEncodedBytes else { throw .tooLarge(bytes: data.count, limit: maxEncodedBytes) }
        struct VersionProbe: Decodable { let schemaVersion: Int }
        let decoder = JSONDecoder()
        let version: Int
        do {
            version = try decoder.decode(VersionProbe.self, from: data).schemaVersion
        } catch {
            throw PersistenceError.corrupt(String(describing: error))
        }
        if version > currentSchemaVersion {
            throw PersistenceError.newerVersion(found: version, supported: currentSchemaVersion)
        }
        var current = data
        if version < 1 {
            // JSONSerialization goes through NSNumber and may not keep integers above 2^53 exact
            // (IDSource, creationOrder); future migration steps must keep that in mind.
            guard var object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
                throw PersistenceError.corrupt("schema \(version) file is not a JSON object")
            }
            try migrations.migrate(&object, from: version, to: 1)
            // data(withJSONObject:) raises an NSException, which Swift cannot catch, for a non-JSON value.
            guard JSONSerialization.isValidJSONObject(object) else {
                throw PersistenceError.corrupt("migration to schema 1 produced a non-JSON value")
            }
            do {
                current = try JSONSerialization.data(withJSONObject: object)
            } catch {
                throw PersistenceError.corrupt(String(describing: error))
            }
        }
        do {
            return try decoder.decode(World.self, from: current)
        } catch {
            if case let DecodingError.dataCorrupted(context) = error, let layout = context.underlyingError as? LayoutError {
                throw PersistenceError.invalidLayout(layout)
            }
            throw PersistenceError.corrupt(String(describing: error))
        }
    }
}

/// Upgrades a parsed file one schema version at a time. Steps are keyed by the version they
/// upgrade from; schema 1 is the first version, so `standard` has none yet.
public struct MigrationChain: Sendable {
    public typealias Step = @Sendable (inout [String: Any]) throws -> Void

    private let steps: [Int: Step]

    public init(steps: [Int: Step]) {
        self.steps = steps
    }

    public static let standard = MigrationChain(steps: [:])

    /// Runs the steps for `from`, `from + 1`, ... `to - 1` in order, setting `schemaVersion` after
    /// each. Commits to `object` only if every step succeeds.
    public func migrate(_ object: inout [String: Any], from: Int, to: Int) throws(PersistenceError) {
        var working = object
        var version = from
        while version < to {
            guard let step = steps[version] else { throw .missingMigration(from: version) }
            do {
                try step(&working)
            } catch {
                throw .corrupt("migration from schema \(version) failed: \(error)")
            }
            version += 1
            working["schemaVersion"] = version
        }
        object = working
    }
}

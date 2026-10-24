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

    public static func decode(from data: Data) throws(PersistenceError) -> World {
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
        if version < currentSchemaVersion {
            throw PersistenceError.missingMigration(from: version)  // Plan 01-04 adds the migration chain
        }
        do {
            return try decoder.decode(World.self, from: data)
        } catch {
            if case let DecodingError.dataCorrupted(context) = error, let layout = context.underlyingError as? LayoutError {
                throw PersistenceError.invalidLayout(layout)
            }
            throw PersistenceError.corrupt(String(describing: error))
        }
    }
}

public struct MigrationChain: Sendable {
    public typealias Step = @Sendable (inout [String: Any]) throws -> Void

    public init(steps: [Int: Step]) {}

    public static let standard = MigrationChain(steps: [:])

    public func migrate(_ object: inout [String: Any], from: Int, to: Int) throws(PersistenceError) {}
}

extension World {
    public static let maxEncodedBytes = 16 * 1024 * 1024

    public static func decode(from data: Data, migrations: MigrationChain) throws(PersistenceError) -> World {
        try decode(from: data)
    }
}

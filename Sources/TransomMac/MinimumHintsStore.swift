import Foundation
import TransomModel
import os

public enum HintsError: Error, Equatable {
    case tooLarge(Int), newerVersion(Int), corrupt(String), invalidEntry(String), writeFailed(String)
}

/// Learned per-bundle minimum sizes (D-13), kept as `{schemaVersion, hints: [{bundleID, width, height}]}` in
/// min-size-hints.json. Only bundle IDs and sizes are stored, never titles or anything per window (T-02-36).
///
/// The file is user-writable (T-02-35), so `load` rejects it whole on any doubt: over `maxBytes`, a newer schema,
/// malformed JSON, or an invalid or duplicate entry. It logs why, moves the file aside as `.corrupt` and starts empty.
@MainActor public final class MinimumHintsStore {
    nonisolated public static let fileName = "min-size-hints.json"
    nonisolated public static let maxBytes = 65_536
    nonisolated public static let schemaVersion = 1
    /// `~/Library/Application Support/Transom`.
    nonisolated public static var defaultDirectory: URL {
        URL.applicationSupportDirectory.appending(path: "Transom", directoryHint: .isDirectory)
    }

    public private(set) var hints: [String: Size] = [:]
    /// Why the last `load` rejected the file; nil when it loaded or there was none.
    public private(set) var loadError: HintsError?
    private let directory: URL
    private static let logger = Logger(subsystem: "com.eightabyte.transom", category: "hints")

    private struct Entry: Codable {
        var bundleID: String
        var width: Double
        var height: Double
    }

    private struct Contents: Codable {
        var schemaVersion: Int
        var hints: [Entry]
    }

    public init(directory: URL) {
        self.directory = directory
    }

    private var file: URL { directory.appending(path: Self.fileName) }

    /// Replaces `hints` with the file's. No file: empty, no error.
    public func load() {
        hints = [:]
        loadError = nil
        guard FileManager.default.fileExists(atPath: file.path) else { return }
        do {
            hints = try Self.decode(file)
        } catch {
            loadError = error
            Self.logger.error("rejected \(Self.fileName, privacy: .public): \(String(describing: error), privacy: .public); starting with no hints")
            setAside()
        }
    }

    /// Raises the stored hint per axis; false when nothing changed or the key or size is invalid (`unbundled:` keys never qualify).
    public func record(bundleID: String, minimum: Size) -> Bool {
        guard ExclusionStore.isValid(bundleID), Self.isValid(minimum) else { return false }
        let old = hints[bundleID]
        let new = Size(width: max(old?.width ?? 0, minimum.width), height: max(old?.height ?? 0, minimum.height))
        guard new != old else { return false }
        hints[bundleID] = new
        return true
    }

    /// Writes every hint, sorted by bundle ID, atomically; creates the directory if needed.
    public func save() throws(HintsError) {
        let contents = Contents(
            schemaVersion: Self.schemaVersion,
            hints: hints.sorted { $0.key < $1.key }.map { Entry(bundleID: $0.key, width: $0.value.width, height: $0.value.height) }
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .prettyPrinted]
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try encoder.encode(contents).write(to: file, options: .atomic)
        } catch {
            throw .writeFailed(String(describing: error))
        }
    }

    /// Size cap, then a version probe, then the full decode, then every entry (Persistence.swift's order).
    private static func decode(_ url: URL) throws(HintsError) -> [String: Size] {
        // No typed throw inside a do/catch: on the CI runner (Swift 6.3, release) that shape crashed the test process.
        let fileSize: Int?
        do {
            fileSize = try FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int
        } catch {
            throw .corrupt("unreadable: \(error.localizedDescription)")
        }
        if let fileSize, fileSize > maxBytes { throw .tooLarge(fileSize) }
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            throw .corrupt("unreadable: \(error.localizedDescription)")
        }
        guard data.count <= maxBytes else { throw .tooLarge(data.count) }
        struct VersionProbe: Decodable { let schemaVersion: Int }
        let decoder = JSONDecoder()
        let version: Int
        do {
            version = try decoder.decode(VersionProbe.self, from: data).schemaVersion
        } catch {
            throw .corrupt("no schemaVersion: \(error)")
        }
        guard version <= schemaVersion else { throw .newerVersion(version) }
        guard version == schemaVersion else { throw .corrupt("unknown schemaVersion \(version)") }
        let contents: Contents
        do {
            contents = try decoder.decode(Contents.self, from: data)
        } catch {
            throw .corrupt(String(describing: error))
        }
        var hints: [String: Size] = [:]
        for (index, entry) in contents.hints.enumerated() {
            let size = Size(width: entry.width, height: entry.height)
            guard ExclusionStore.isValid(entry.bundleID) else { throw .invalidEntry("entry \(index): invalid bundle ID") }
            guard isValid(size) else { throw .invalidEntry("entry \(index): size not finite or outside 0...\(Geometry.maxCoordinate)") }
            guard hints.updateValue(size, forKey: entry.bundleID) == nil else { throw .invalidEntry("entry \(index): duplicate bundle ID") }
        }
        return hints
    }

    private static func isValid(_ size: Size) -> Bool {
        [size.width, size.height].allSatisfy { $0.isFinite && $0 >= 0 && $0 <= Geometry.maxCoordinate }
    }

    /// Moves the rejected file to `<name>.corrupt`, replacing an older one, so the next save cannot destroy it.
    private func setAside() {
        let corrupt = directory.appending(path: Self.fileName + ".corrupt")
        do {
            if FileManager.default.fileExists(atPath: corrupt.path) { try FileManager.default.removeItem(at: corrupt) }
            try FileManager.default.moveItem(at: file, to: corrupt)
        } catch {
            Self.logger.error("could not move the rejected \(Self.fileName, privacy: .public) aside: \(error.localizedDescription, privacy: .public)")
        }
    }
}

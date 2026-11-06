import Foundation
import TransomEngine
import TransomModel
import os

public enum LayoutStoreError: Error, Equatable {
    case tooLarge(Int), newerVersion(Int), corrupt(String), invalidEntry(String), writeFailed(String)
}

/// layout.json: the World, the home frames and the session record in one file (D-16, RESEARCH Pattern 10), in the
/// shape of `MinimumHintsStore`. Window titles are written so windows can be re-matched after a relaunch (D-10, which
/// supersedes T-03-17), so the file is owner-only.
///
/// The file is user-writable and decides where windows go (T-03-15), so `load` rejects it whole on any doubt: over
/// `World.maxEncodedBytes`, malformed JSON, an invalid World, an invalid or duplicate home frame, an incomplete session
/// record. It logs why, moves the file aside as `.corrupt-<unix seconds>` and starts empty. A file from a newer schema is
/// the exception (T-03-18): it is left in place and nothing is saved this session, so a downgrade never destroys it.
@MainActor public final class LayoutStore {
    nonisolated public static let fileName = "layout.json"

    /// What the last `load` read; nil when there was no file or it was rejected.
    public private(set) var contents: LayoutFile?
    /// Why the last `load` rejected the file; nil when it loaded or there was none.
    public private(set) var loadError: LayoutStoreError?
    /// Set by a newer-schema file, or a rejected one that could not be moved aside: every `save` this session is a no-op.
    public private(set) var savingDisabled = false
    private let directory: URL
    /// `World.maxEncodedBytes`; a test lowers it, as encoding that much would hold the main actor for seconds.
    private let saveLimit: Int
    private static let logger = Logger(subsystem: "com.eightabyte.transom", category: "persist")

    public init(directory: URL, saveLimit: Int = World.maxEncodedBytes) {
        self.directory = directory
        self.saveLimit = saveLimit
    }

    private var file: URL { directory.appending(path: Self.fileName) }

    /// Replaces `contents` with the file's. No file: nil, no error.
    public func load() {
        contents = nil
        loadError = nil
        guard FileManager.default.fileExists(atPath: file.path) else { return }
        do {
            contents = try Self.decode(file)
        } catch {
            loadError = error
            if case .newerVersion(let version) = error {
                savingDisabled = true
                Self.logger.error("\(Self.fileName, privacy: .public) was saved by a newer Transom (schema \(version)); leaving it untouched and not saving layouts this session")
                return
            }
            Self.logger.error("rejected \(Self.fileName, privacy: .public): \(String(describing: error), privacy: .public); starting empty")
            setAside()
        }
    }

    /// Writes `contents`, window titles included, atomically and owner-only (0600); creates the directory if needed.
    /// Returns false, writing nothing, when saving is disabled. Over `World.maxEncodedBytes` it throws and keeps the last
    /// good file, since `load` would reject this one whole.
    @discardableResult
    public func save(_ contents: LayoutFile) throws(LayoutStoreError) -> Bool {
        guard !savingDisabled else { return false }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .prettyPrinted]
        let data: Data
        do {
            data = try encoder.encode(contents)
        } catch {
            throw .writeFailed(String(describing: error))
        }
        guard data.count <= saveLimit else { throw .tooLarge(data.count) }
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try data.write(to: file, options: .atomic)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
        } catch {
            throw .writeFailed(String(describing: error))
        }
        return true
    }

    /// Copies layout.json to `layout.json.<label>-<unix seconds>` (owner-only, as the original), so desks the next save
    /// drops can still be recovered by hand (WR-04). A timestamp per copy, so no earlier backup is replaced. False when
    /// there is no file or the copy failed (logged).
    @discardableResult
    public func backUp(_ label: String, at date: Date = .now) -> Bool {
        let copy = directory.appending(path: "\(Self.fileName).\(label)-\(Int(date.timeIntervalSince1970))")
        do {
            try FileManager.default.copyItem(at: file, to: copy)
            Self.logger.notice("backed up \(Self.fileName, privacy: .public) to \(copy.lastPathComponent, privacy: .public)")
            return true
        } catch {
            Self.logger.error("could not back up \(Self.fileName, privacy: .public): \(error.localizedDescription, privacy: .public)")
            return false
        }
    }

    /// Size cap on the whole file, then a version probe, then the full decode (schema 1 through `LayoutFileV1`, each
    /// World's own validation), then `LayoutFile.validate()`, then every home frame and wanted frame (Persistence.swift's
    /// order). The session record has no field to check beyond its decode.
    private static func decode(_ url: URL) throws(LayoutStoreError) -> LayoutFile {
        let data: Data
        do {
            if let size = try FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int, size > World.maxEncodedBytes {
                throw LayoutStoreError.tooLarge(size)
            }
            data = try Data(contentsOf: url)
        } catch let error as LayoutStoreError {
            throw error
        } catch {
            throw .corrupt("unreadable: \(error.localizedDescription)")
        }
        guard data.count <= World.maxEncodedBytes else { throw .tooLarge(data.count) }
        struct VersionProbe: Decodable { let schemaVersion: Int }
        let decoder = JSONDecoder()
        let version: Int
        do {
            version = try decoder.decode(VersionProbe.self, from: data).schemaVersion
        } catch {
            throw .corrupt("no schemaVersion: \(error)")
        }
        guard version <= LayoutFile.schemaVersion else { throw .newerVersion(version) }
        var contents: LayoutFile
        do {
            switch version {
            // Every user's file at the upgrade: migrated in memory, saved as the current schema (RESEARCH Pitfall 1).
            case 1: contents = try decoder.decode(LayoutFileV1.self, from: data).migrated()
            // Schemas 2 and 3 have schema 4's shape; their Worlds drop the Desktop tile on decode (World schema 1).
            // The next save writes schema 4.
            case 2, 3, LayoutFile.schemaVersion:
                contents = try decoder.decode(LayoutFile.self, from: data)
                contents.schemaVersion = LayoutFile.schemaVersion
            default: throw LayoutStoreError.corrupt("unknown schemaVersion \(version)")
            }
        } catch let error as LayoutStoreError {
            throw error
        } catch {
            throw .corrupt(String(describing: error))
        }
        do {
            try contents.validate()
        } catch {
            throw .invalidEntry(error.reason)
        }
        var seen: Set<WindowIdentity> = []
        for (index, home) in contents.homeFrames.enumerated() {
            guard home.frame.isValidGeometry else { throw .invalidEntry("home frame \(index): not finite or out of range") }
            guard seen.insert(home.window).inserted else { throw .invalidEntry("home frame \(index): duplicate window") }
        }
        seen = []
        for (index, wanted) in contents.wantedFrames.enumerated() {
            guard wanted.frame.isValidGeometry else { throw .invalidEntry("wanted frame \(index): not finite or out of range") }
            guard seen.insert(wanted.window).inserted else { throw .invalidEntry("wanted frame \(index): duplicate window") }
        }
        return contents
    }

    /// Moves the rejected file to `<name>.corrupt-<unix seconds>`, as `backUp` names its copies, so no earlier one is
    /// replaced and the next save cannot destroy it. If it won't move, no save this session can either.
    private func setAside() {
        let corrupt = directory.appending(path: "\(Self.fileName).corrupt-\(Int(Date.now.timeIntervalSince1970))")
        do {
            try FileManager.default.moveItem(at: file, to: corrupt)
        } catch {
            savingDisabled = true
            Self.logger.error("could not move the rejected \(Self.fileName, privacy: .public) aside, so not saving layouts this session: \(error.localizedDescription, privacy: .public)")
        }
    }
}

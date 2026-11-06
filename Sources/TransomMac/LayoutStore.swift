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
            let (decoded, version) = try Self.decode(file)
            contents = decoded
            if let line = Self.migrationLine(fromSchema: version, contents: decoded) {
                Self.logger.info("\(line, privacy: .public)")
                // The next save overwrites it one way, so a downgrade can restore this copy by hand (WR-04); a failure is logged.
                backUp("schema-\(version)")
            }
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

    /// The one log line for a file older than the current schema (8.1.1 D-15), nil for a current one. Counts only, never
    /// a window, title or path (T-08.1.1-03). Every legacy desk held one Desktop tile (RESEARCH A5); the windows brought
    /// back are `world`'s floaters with a home frame, which the Arranger's restore returns from the park rect.
    public static func migrationLine(fromSchema version: Int, contents: LayoutFile) -> String? {
        guard version != LayoutFile.schemaVersion else { return nil }
        let desks = contents.world.desks.count + contents.layoutSets.reduce(0) { $0 + $1.world.desks.count }
        let homes = Set(contents.homeFrames.map(\.window))
        let parked = contents.world.desks.values.reduce(0) { count, desk in
            count + desk.desktop.windows.filter { homes.contains($0.window.identity) }.count
        }
        return "migrated layout.json schema \(version) to \(LayoutFile.schemaVersion): dropped \(desks) Desktop tiles, brought back \(parked) parked windows"
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
    /// Returns the schema version the file was written in, too.
    private static func decode(_ url: URL) throws(LayoutStoreError) -> (LayoutFile, Int) {
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
        // A hidden legacy Desktop left its floaters' stored frames at the park rect; the home frame is where each belongs, so
        // it comes back even when it shows up after launch (8.1.1 D-02, WR-01).
        if version < LayoutFile.schemaVersion {
            for (index, home) in contents.homeFrames.enumerated() {
                let window = WindowRef(identity: home.window)
                do throws(LayoutError) {
                    if contents.world.desks.values.contains(where: { $0.desktop.contains(window) }) {
                        try contents.world.recordFloatingFrame(home.frame, for: window)
                    }
                    for i in contents.layoutSets.indices where contents.layoutSets[i].world.desks.values.contains(where: { $0.desktop.contains(window) }) {
                        try contents.layoutSets[i].world.recordFloatingFrame(home.frame, for: window)
                    }
                } catch {
                    throw .invalidEntry("home frame \(index): \(error)")
                }
            }
        }
        seen = []
        for (index, wanted) in contents.wantedFrames.enumerated() {
            guard wanted.frame.isValidGeometry else { throw .invalidEntry("wanted frame \(index): not finite or out of range") }
            guard seen.insert(wanted.window).inserted else { throw .invalidEntry("wanted frame \(index): duplicate window") }
        }
        return (contents, version)
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

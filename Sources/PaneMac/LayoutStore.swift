import Foundation
import PaneEngine
import PaneModel
import os

public enum LayoutStoreError: Error, Equatable {
    case tooLarge(Int), newerVersion(Int), corrupt(String), invalidEntry(String), writeFailed(String)
}

/// layout.json: the World, the home frames and the session record in one file (D-16, RESEARCH Pattern 10),
/// in the shape of `MinimumHintsStore`.
@MainActor public final class LayoutStore {
    nonisolated public static let fileName = "layout.json"

    /// What the last `load` read; nil when there was no file or it was rejected.
    public private(set) var contents: LayoutFile?
    /// Why the last `load` rejected the file; nil when it loaded or there was none.
    public private(set) var loadError: LayoutStoreError?
    public private(set) var savingDisabled = false
    private let directory: URL
    private static let logger = Logger(subsystem: "com.eightabyte.pane", category: "persist")

    public init(directory: URL) {
        self.directory = directory
    }

    private var file: URL { directory.appending(path: Self.fileName) }

    /// Replaces `contents` with the file's. No file: nil, no error.
    public func load() {
        contents = nil
        loadError = nil
        guard FileManager.default.fileExists(atPath: file.path) else { return }
        do {
            contents = try JSONDecoder().decode(LayoutFile.self, from: Data(contentsOf: file))
        } catch {
            loadError = .corrupt(String(describing: error))
            Self.logger.error("rejected \(Self.fileName, privacy: .public): \(String(describing: error), privacy: .public); starting empty")
        }
    }

    /// Writes `file` atomically, creating the directory if needed. Returns whether anything was written.
    @discardableResult
    public func save(_ contents: LayoutFile) throws(LayoutStoreError) -> Bool {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .prettyPrinted]
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try encoder.encode(contents).write(to: file, options: .atomic)
        } catch {
            throw .writeFailed(String(describing: error))
        }
        return true
    }
}

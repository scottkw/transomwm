import Foundation
import PaneModel
import os

public enum HintsError: Error, Equatable {
    case tooLarge(Int), newerVersion(Int), corrupt(String), invalidEntry(String), writeFailed(String)
}

/// Learned per-bundle minimum sizes (D-13), kept in min-size-hints.json.
@MainActor public final class MinimumHintsStore {
    nonisolated public static let fileName = "min-size-hints.json"
    nonisolated public static let maxBytes = 65_536
    nonisolated public static let schemaVersion = 1
    public private(set) var hints: [String: Size] = [:]
    public private(set) var loadError: HintsError?
    private let directory: URL

    public init(directory: URL) {
        self.directory = directory
    }

    public func load() {}

    public func record(bundleID: String, minimum: Size) -> Bool { false }

    public func save() throws(HintsError) {}
}

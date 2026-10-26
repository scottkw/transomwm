import Foundation
import PaneEngine
import PaneModel
import os

public enum LayoutStoreError: Error, Equatable {
    case tooLarge(Int), newerVersion(Int), corrupt(String), invalidEntry(String), writeFailed(String)
}

/// layout.json (RED stub).
@MainActor public final class LayoutStore {
    nonisolated public static let fileName = "layout.json"

    public private(set) var contents: LayoutFile?
    public private(set) var loadError: LayoutStoreError?
    public private(set) var savingDisabled = false
    private let directory: URL

    public init(directory: URL) {
        self.directory = directory
    }

    public func load() {}

    @discardableResult
    public func save(_ file: LayoutFile) throws(LayoutStoreError) -> Bool { false }
}

import Combine
import Foundation
import os

public enum ExclusionError: Error, Equatable {
    case invalidBundleID
}

/// Bundle IDs Pane never arranges (D-12, WIN-08), kept in UserDefaults. Starts empty: no built-in entries.
@MainActor public final class ExclusionStore: ObservableObject {
    public static let key = "excludedBundleIDs"
    @Published public private(set) var bundleIDs: [String] = []
    /// Fires after every successful mutation.
    public var onChange: (() -> Void)?

    public init(defaults: UserDefaults = .standard) {}

    public static func isValid(_ bundleID: String) -> Bool { false }

    public func contains(_ bundleID: String) -> Bool { false }

    public func add(_ bundleID: String) throws(ExclusionError) {}

    public func remove(_ bundleID: String) {}

    public func toggle(_ bundleID: String) throws(ExclusionError) {}

    public func sortedEntries(displayNames: [String: String]) -> [(bundleID: String, title: String)] { [] }
}

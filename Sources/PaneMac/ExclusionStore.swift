import Combine
import Foundation
import os

public enum ExclusionError: Error, Equatable {
    case invalidBundleID
}

/// Bundle IDs Pane never arranges (D-12, WIN-08), kept in UserDefaults. Starts empty: no built-in entries.
/// Matching is case-insensitive and exact; storage keeps the casing as added.
@MainActor public final class ExclusionStore: ObservableObject {
    public static let key = "excludedBundleIDs"
    @Published public private(set) var bundleIDs: [String]
    /// Fires after every successful mutation.
    public var onChange: (() -> Void)?
    private let defaults: UserDefaults
    private static let logger = Logger(subsystem: "com.eightabyte.pane", category: "exclusions")

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        var loaded: [String] = []
        // The plist is user-writable (T-02-22): keep only valid, unique entries and log the rest.
        for entry in defaults.stringArray(forKey: Self.key) ?? [] {
            let id = entry.trimmingCharacters(in: .whitespaces)
            guard Self.isValid(id) else {
                Self.logger.error("dropped an invalid excluded bundle ID (\(entry.count, privacy: .public) characters)")
                continue
            }
            if !loaded.contains(where: { Self.same($0, id) }) { loaded.append(id) }
        }
        bundleIDs = loaded
    }

    /// 1...255 characters of ASCII letters, digits, `.` and `-` (so `unbundled:` keys never qualify).
    public static func isValid(_ bundleID: String) -> Bool {
        (1...255).contains(bundleID.utf8.count)
            && bundleID.unicodeScalars.allSatisfy { $0.isASCII && (CharacterSet.alphanumerics.contains($0) || $0 == "." || $0 == "-") }
    }

    public func contains(_ bundleID: String) -> Bool {
        bundleIDs.contains { Self.same($0, bundleID) }
    }

    public func add(_ bundleID: String) throws(ExclusionError) {
        let id = bundleID.trimmingCharacters(in: .whitespaces)
        guard Self.isValid(id) else { throw .invalidBundleID }
        guard !contains(id) else { return }
        save(bundleIDs + [id])
    }

    public func remove(_ bundleID: String) {
        guard contains(bundleID) else { return }
        save(bundleIDs.filter { !Self.same($0, bundleID) })
    }

    public func toggle(_ bundleID: String) throws(ExclusionError) {
        if contains(bundleID) { remove(bundleID) } else { try add(bundleID) }
    }

    /// Display name (case-insensitive), then bundle ID; an ID without a name shows as itself.
    public func sortedEntries(displayNames: [String: String]) -> [(bundleID: String, title: String)] {
        bundleIDs.map { (bundleID: $0, title: displayNames[$0] ?? $0) }.sorted {
            switch $0.title.compare($1.title, options: .caseInsensitive) {
            case .orderedAscending: true
            case .orderedDescending: false
            case .orderedSame: $0.bundleID.compare($1.bundleID, options: .caseInsensitive) == .orderedAscending
            }
        }
    }

    private func save(_ ids: [String]) {
        bundleIDs = ids
        defaults.set(ids, forKey: Self.key)
        onChange?()
    }

    private static func same(_ a: String, _ b: String) -> Bool {
        a.caseInsensitiveCompare(b) == .orderedSame
    }
}

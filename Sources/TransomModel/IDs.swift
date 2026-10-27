import Foundation

/// A tree node's identity: a monotonic counter value from `IDSource`, readable in logs as `n<raw>`.
/// Encodes as a bare JSON number, and as a decimal string when used as a dictionary key.
public struct NodeID: Hashable, Comparable, Codable, Sendable, CodingKeyRepresentable, CustomStringConvertible {
    public let raw: UInt64

    public init(raw: UInt64) {
        self.raw = raw
    }

    public init(from decoder: any Decoder) throws {
        raw = try decoder.singleValueContainer().decode(UInt64.self)
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(raw)
    }

    public static func < (lhs: NodeID, rhs: NodeID) -> Bool { lhs.raw < rhs.raw }

    private struct Key: CodingKey {
        let stringValue: String
        var intValue: Int? { nil }
        init(stringValue: String) { self.stringValue = stringValue }
        init?(intValue: Int) { nil }
    }

    public var codingKey: any CodingKey { Key(stringValue: String(raw)) }

    public init?<T: CodingKey>(codingKey: T) {
        // Canonical decimal only, so "01" and "1" cannot both decode to the same key.
        guard let raw = UInt64(codingKey.stringValue), String(raw) == codingKey.stringValue else { return nil }
        self.raw = raw
    }

    public var description: String { "n\(raw)" }
}

extension NodeID {
    /// The Desktop tile's reserved ID (D-24). `IDSource` starts at 1 and `World` requires that, so this
    /// ID is never minted and a desk can hold at most one Desktop tile by construction.
    public static let desktop = NodeID(raw: 0)
}

public struct IDSource: Codable, Equatable, Sendable {
    public private(set) var next: UInt64

    public init(next: UInt64 = 1) {
        self.next = next
    }

    /// Throws rather than traps: `next` can come from an untrusted file.
    public mutating func make() throws(LayoutError) -> NodeID {
        guard next < UInt64.max else { throw .invariantViolated("ID source exhausted") }
        defer { next += 1 }
        return NodeID(raw: next)
    }
}

/// The runtime identity of a window. Two refs with the same identity are the same window.
public struct WindowIdentity: Hashable, Comparable, Codable, Sendable {
    public var windowID: UInt32
    public var pid: Int32
    public var bundleID: String

    public init(windowID: UInt32, pid: Int32, bundleID: String) {
        self.windowID = windowID
        self.pid = pid
        self.bundleID = bundleID
    }

    public static func < (lhs: WindowIdentity, rhs: WindowIdentity) -> Bool {
        (lhs.pid, lhs.windowID, lhs.bundleID) < (rhs.pid, rhs.windowID, rhs.bundleID)
    }
}

/// A window as the model sees it: runtime identity plus persisted hints used to re-match the
/// window after a relaunch.
///
/// Equality and hashing use `identity` only, so a title change never makes the same window look
/// like a different one. `description` never includes `titleHint`, so logs cannot leak document names.
public struct WindowRef: Codable, Sendable, Hashable, CustomStringConvertible, CustomDebugStringConvertible {
    public let identity: WindowIdentity
    public var titleHint: String
    public var axIdentifier: String?
    public var creationOrder: UInt64

    public init(identity: WindowIdentity, titleHint: String = "", axIdentifier: String? = nil, creationOrder: UInt64 = 0) {
        self.identity = identity
        self.titleHint = titleHint
        self.axIdentifier = axIdentifier
        self.creationOrder = creationOrder
    }

    public var windowID: UInt32 { identity.windowID }
    public var pid: Int32 { identity.pid }
    public var bundleID: String { identity.bundleID }

    public static func == (lhs: WindowRef, rhs: WindowRef) -> Bool { lhs.identity == rhs.identity }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(identity)
    }

    public var description: String { "window \(windowID) pid \(pid) \(bundleID)" }

    // String(describing:) of an error payload prefers debugDescription; keep the title out of it too.
    public var debugDescription: String { description }
}

/// `closed` is a transition request ("remove this window's slot") and is never stored in a tree.
public enum WindowState: String, Codable, Sendable, CaseIterable {
    case present, absent, fullscreen, closed
}

/// A desk is one display, optionally narrowed to one Space. `spaceID == nil` means one desk per display.
public struct DeskKey: Hashable, Comparable, Codable, Sendable {
    public let displayUUID: String
    public let spaceID: UInt64?

    public init(displayUUID: String, spaceID: UInt64?) {
        self.displayUUID = displayUUID
        self.spaceID = spaceID
    }

    public static func < (lhs: DeskKey, rhs: DeskKey) -> Bool {
        if lhs.displayUUID != rhs.displayUUID { return lhs.displayUUID < rhs.displayUUID }
        switch (lhs.spaceID, rhs.spaceID) {
        case let (l?, r?): return l < r
        case (nil, _?): return true
        case (_, nil): return false
        }
    }
}

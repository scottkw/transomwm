import Foundation

/// What a Space shows: an ordinary desktop, or one app's native full-screen window.
public enum SpaceKind: String, Equatable, Sendable {
    case desktop
    case fullScreen
}

/// One Space as macOS lists it (D-12, D-13). `uuid` is durable across logins; `id` is the runtime number every other
/// SkyLight call answers with. `index` is the 1-based "Desktop n" position among the display's desktops, 0 for a
/// full-screen Space.
public struct SpaceInfo: Equatable, Sendable {
    public let id: UInt64
    public let uuid: String
    public let kind: SpaceKind
    public let displayUUID: String
    public let index: Int
}

/// One display's Spaces in macOS's order, and the Space it shows now (nil when unknown).
public struct DisplaySpaces: Equatable, Sendable {
    public let displayUUID: String
    public let current: UInt64?
    public let spaces: [SpaceInfo]
}

/// Every display's Spaces, parsed from SkyLight's managed-display dictionaries (06-RESEARCH F1, Pattern 1).
public struct SpacesSnapshot: Equatable, Sendable {
    /// Caps on untrusted private data (T-06-06).
    public static let maxSpacesPerDisplay = 16
    public static let maxDisplays = 32

    public let displays: [DisplaySpaces]
    /// "Displays have separate Spaces"; false means one Space list spans every display (it sits on the main display).
    public let separateSpaces: Bool
    /// Space entries dropped for an unknown `type` or a malformed field.
    public let skipped: Int

    public var spaceCount: Int { displays.reduce(0) { $0 + $1.spaces.count } }

    public var uuidByID: [UInt64: String] {
        Dictionary(displays.flatMap(\.spaces).map { ($0.id, $0.uuid) }, uniquingKeysWith: { first, _ in first })
    }

    public var idByUUID: [String: UInt64] {
        Dictionary(displays.flatMap(\.spaces).map { ($0.uuid, $0.id) }, uniquingKeysWith: { first, _ in first })
    }

    /// A Space belongs to the display dictionary whose "Spaces" array lists it; a per-Space display key names where
    /// the Space wants to return, not where it is, so it is never read. A display identifier of "Main" (spans mode)
    /// is `mainDisplayUUID`; an empty Space uuid becomes "default:<displayUUID>". Type 2 (system) Spaces are skipped.
    public static func parse(_ raw: [[String: Any]], mainDisplayUUID: String, separateSpaces: Bool) -> SpacesSnapshot {
        var displays: [DisplaySpaces] = []
        var skipped = 0
        for display in raw {
            guard displays.count < maxDisplays else { break }
            let identifier = display["Display Identifier"] as? String ?? ""
            // Spans mode has one list, and it belongs to the main display.
            let displayUUID = !separateSpaces || identifier == "Main" ? mainDisplayUUID : identifier
            guard !displayUUID.isEmpty, !displays.contains(where: { $0.displayUUID == displayUUID }) else { continue }
            var spaces: [SpaceInfo] = []
            var desktops = 0
            for space in display["Spaces"] as? [[String: Any]] ?? [] {
                guard spaces.count < maxSpacesPerDisplay else { break }
                guard let id = spaceID(space), let type = space["type"] as? Int, let uuid = space["uuid"] as? String else {
                    skipped += 1
                    continue
                }
                let kind: SpaceKind
                switch type {
                case 0: kind = .desktop
                case 4: kind = .fullScreen
                case 2: continue
                default:
                    skipped += 1
                    continue
                }
                if kind == .desktop { desktops += 1 }
                spaces.append(SpaceInfo(
                    id: id, uuid: uuid.isEmpty ? "default:\(displayUUID)" : uuid, kind: kind, displayUUID: displayUUID,
                    index: kind == .desktop ? desktops : 0
                ))
            }
            let current = (display["Current Space"] as? [String: Any]).flatMap(spaceID)
            displays.append(DisplaySpaces(displayUUID: displayUUID, current: current, spaces: spaces))
        }
        return SpacesSnapshot(displays: displays, separateSpaces: separateSpaces, skipped: skipped)
    }

    /// `ManagedSpaceID`, else `id64`; only a positive number counts (a string or 0 is malformed).
    private static func spaceID(_ space: [String: Any]) -> UInt64? {
        for key in ["ManagedSpaceID", "id64"] {
            if let number = space[key] as? NSNumber, CFGetTypeID(number) == CFNumberGetTypeID(), number.int64Value > 0 {
                return UInt64(number.int64Value)
            }
        }
        return nil
    }
}

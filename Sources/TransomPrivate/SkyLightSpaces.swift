import CoreFoundation
import Darwin
import Foundation

/// Read-only per-window and per-display Space lookup through SkyLight (private, D-15). Reached only through `dlopen` + `dlsym`,
/// never linked, so a removed symbol leaves the lookup nil and Transom runs single-Space behaviour (only tab grouping
/// falls back). WindowServer IPC, not AX: safe to call on main.
public enum SkyLightSpaces {
    typealias MainConnectionID = @convention(c) () -> Int32
    /// (connection, selector, CFArray of window-ID CFNumbers) -> +1 CFArray of Space-ID CFNumbers, or NULL.
    typealias CopySpacesForWindows = @convention(c) (Int32, Int32, CFArray) -> Unmanaged<CFArray>?

    /// Every Space a window is on, not only the current one.
    static let allSpaces: Int32 = 0x7
    /// A window on more Spaces than this has the rest ignored (T-02-38).
    static let maxSpacesPerWindow = 16

    /// (connection, display UUID) -> the display's current Space ID, 0 when unknown. The signature is prior art
    /// (yabai's `SLSManagedDisplayGetCurrentSpace(int cid, CFStringRef uuid)`), cross-checked only by a probe on
    /// macOS 27.0.1 that returned the Space `SLSCopyManagedDisplaySpaces` called current (03-RESEARCH).
    typealias CurrentSpace = @convention(c) (Int32, CFString) -> UInt64
    /// (connection) -> +1 CFArray of display dictionaries, each with "Display Identifier", "Current Space" and an
    /// ordered "Spaces" array (06-RESEARCH F1, local probe on 27.2).
    typealias CopyManagedDisplaySpaces = @convention(c) (Int32) -> Unmanaged<CFArray>?
    /// (connection) -> 1 while "Displays have separate Spaces" is on (06-RESEARCH F4).
    typealias GetSpaceManagementMode = @convention(c) (Int32) -> Int32

    /// `currentSpace`, `copyManagedDisplaySpaces` and `managementMode` are optional on their own, so a missing symbol
    /// never turns off the per-window lookup.
    private static let functions: (
        connection: Int32, copySpaces: CopySpacesForWindows, currentSpace: CurrentSpace?,
        copyManagedDisplaySpaces: CopyManagedDisplaySpaces?, managementMode: GetSpaceManagementMode?
    )? = {
        guard !Capabilities.isForcedOff(.spaces),
              let handle = dlopen("/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight", RTLD_LAZY),
              let main = dlsym(handle, "SLSMainConnectionID"),
              let copy = dlsym(handle, "SLSCopySpacesForWindows")
        else { return nil }
        let current = dlsym(handle, "SLSManagedDisplayGetCurrentSpace").map { unsafeBitCast($0, to: CurrentSpace.self) }
        let managed = dlsym(handle, "SLSCopyManagedDisplaySpaces").map { unsafeBitCast($0, to: CopyManagedDisplaySpaces.self) }
        let mode = dlsym(handle, "SLSGetSpaceManagementMode").map { unsafeBitCast($0, to: GetSpaceManagementMode.self) }
        return (
            unsafeBitCast(main, to: MainConnectionID.self)(), unsafeBitCast(copy, to: CopySpacesForWindows.self), current,
            managed, mode
        )
    }()

    /// True only when both symbols resolved and the capability was not forced off at launch.
    public static var isLoaded: Bool { functions != nil }

    /// Each window's Space IDs; a window with no Space reported maps to an empty set, and one whose call returned
    /// NULL is left out. Nil when the capability is unavailable or every call in a non-empty batch failed.
    public static func spaces(of windowIDs: [UInt32]) -> [UInt32: Set<UInt64>]? {
        guard Capabilities.isAvailable(.spaces), let functions else { return nil }
        guard !windowIDs.isEmpty else { return [:] }
        var result: [UInt32: Set<UInt64>] = [:]
        // One call per window: a call answers with the union of Spaces over its whole list.
        for windowID in windowIDs {
            let ids = [NSNumber(value: windowID)] as CFArray
            guard let array = functions.copySpaces(functions.connection, allSpaces, ids)?.takeRetainedValue() else { continue }
            result[windowID] = spaceIDs(in: array)
        }
        guard !result.isEmpty else {
            Capabilities.recordFailure(.spaces)
            return nil
        }
        Capabilities.recordSuccess(.spaces)
        return result
    }

    /// The Space shown on `displayUUID` right now (D-25). Nil when the capability is off in `session`, the symbol did
    /// not resolve, or SkyLight answers 0 (unknown).
    public static func currentSpace(displayUUID: String, session: CapabilitySession = Capabilities.session) -> UInt64? {
        guard session.isAvailable(.spaces), let functions, let currentSpace = functions.currentSpace else { return nil }
        let space = currentSpace(functions.connection, displayUUID as CFString)
        return space == 0 ? nil : space
    }

    /// Every display's Spaces as SkyLight reports them (raw property-list values; `SpacesSnapshot.parse` reads them).
    /// Nil when the capability is off in `session`, the symbol did not resolve, or the answer is not an array of
    /// dictionaries.
    public static func managedDisplaySpaces(session: CapabilitySession = Capabilities.session) -> [[String: Any]]? {
        guard session.isAvailable(.spaces), let functions, let copy = functions.copyManagedDisplaySpaces else { return nil }
        guard let array = copy(functions.connection)?.takeRetainedValue() as? [[String: Any]] else {
            session.recordFailure(.spaces)
            return nil
        }
        session.recordSuccess(.spaces)
        return array
    }

    /// The raw Space management mode (1 = separate Spaces per display), nil when unavailable.
    public static func managementMode(session: CapabilitySession = Capabilities.session) -> Int32? {
        guard session.isAvailable(.spaces), let functions, let mode = functions.managementMode else { return nil }
        return mode(functions.connection)
    }

    /// Only CFNumber elements count; 0 and anything past `maxSpacesPerWindow` are dropped (T-02-38).
    static func spaceIDs(in array: CFArray) -> Set<UInt64> {
        var spaces: Set<UInt64> = []
        for element in array as [AnyObject] where CFGetTypeID(element) == CFNumberGetTypeID() {
            var value: Int64 = 0
            guard CFNumberGetValue((element as! CFNumber), .sInt64Type, &value), value != 0 else { continue }
            spaces.insert(UInt64(bitPattern: value))
            if spaces.count == maxSpacesPerWindow { break }
        }
        return spaces
    }
}

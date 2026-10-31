/// One synthetic key chord: a virtual key code and the CGEventFlags raw value posted with both its keyDown and keyUp.
public struct Chord: Equatable, Sendable {
    public let keyCode: UInt16
    public let flags: UInt64

    public init(keyCode: UInt16, flags: UInt64) {
        self.keyCode = keyCode
        self.flags = flags
    }
}

/// Which Mission Control chords take a display from one Space to another (06-RESEARCH Pattern 3, 06-SPIKE "Switch
/// method"). Pure: the shell reads the hotkeys and posts the chords.
public enum SpaceSwitchPlan {
    /// The fn bit. Posted switch chords keep it: without it macOS 15.7.7 switches nothing (06-SPIKE "Switch method",
    /// which overrides RESEARCH Pattern 3's "drop fn").
    static let fn: UInt32 = 0x80_0000
    /// ⇧ ⌃ ⌥ ⌘ and fn: the NX device-independent bits a hotkey's chord is made of, posted as the same CGEventFlags bits.
    static let chordBits: UInt32 = 0x2_0000 | 0x4_0000 | 0x8_0000 | 0x10_0000 | fn
    /// ⌃← and ⌃→ with fn: macOS's default "Move left/right a space", used when the getter is missing or the user turned
    /// those hotkeys off.
    public static let moveLeft = Chord(keyCode: 123, flags: 0x84_0000)
    public static let moveRight = Chord(keyCode: 124, flags: 0x84_0000)
    /// Symbolic hotkey IDs: "Move left a space", "Move right a space", "Switch to Desktop 1" (n is 118 + n − 1).
    public static let moveLeftID: Int32 = 79
    public static let moveRightID: Int32 = 81
    public static let switchToDesktop1ID: Int32 = 118
    /// "Switch to Desktop n" exists for n ≤ 16.
    static let maxSwitchToDesktop = 16

    /// A symbolic hotkey as the getter reports it.
    public typealias HotKey = (enabled: Bool, keyCode: UInt16, modifiers: UInt32)

    /// The chords that go from index `from` to index `to` in the display's ordered Spaces list (none when equal): the
    /// user's enabled "Switch to Desktop n" once for a desktop with n ≤ 16, else "Move left/right a space" |Δ| times.
    public static func plan(from: Int, to: Int, target: SpaceInfo, hotkeys: (Int32) -> HotKey?) -> [Chord] {
        let delta = to - from
        guard delta != 0 else { return [] }
        if target.kind == .desktop, (1...maxSwitchToDesktop).contains(target.index),
            let direct = chord(hotkeys(switchToDesktop1ID + Int32(target.index - 1)))
        {
            return [direct]
        }
        let move = delta > 0 ? chord(hotkeys(moveRightID)) ?? moveRight : chord(hotkeys(moveLeftID)) ?? moveLeft
        return Array(repeating: move, count: abs(delta))
    }

    /// The NX modifiers as CGEventFlags: the chord bits kept, fn included; everything else dropped.
    public static func cgFlags(nx: UInt32) -> UInt64 { UInt64(nx & chordBits) }

    private static func chord(_ hotkey: HotKey?) -> Chord? {
        guard let hotkey, hotkey.enabled else { return nil }
        return Chord(keyCode: hotkey.keyCode, flags: cgFlags(nx: hotkey.modifiers))
    }
}

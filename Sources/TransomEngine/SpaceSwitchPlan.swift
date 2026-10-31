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
    /// The fn bit. Posted switch chords need it: without it macOS 15.7.7 switches nothing (06-SPIKE "Switch method").
    static let fn: UInt32 = 0x80_0000
    /// ⌃← and ⌃→ with fn: macOS's default "Move left/right a space".
    public static let moveLeft = Chord(keyCode: 123, flags: 0x84_0000)
    public static let moveRight = Chord(keyCode: 124, flags: 0x84_0000)

    /// A symbolic hotkey as the getter reports it.
    public typealias HotKey = (enabled: Bool, keyCode: UInt16, modifiers: UInt32)

    /// The chords that go from index `from` to index `to` in the display's ordered Spaces list. None when they are equal.
    public static func plan(from: Int, to: Int, target: SpaceInfo, hotkeys: (Int32) -> HotKey?) -> [Chord] {
        let delta = to - from
        return Array(repeating: delta > 0 ? moveRight : moveLeft, count: abs(delta))
    }
}

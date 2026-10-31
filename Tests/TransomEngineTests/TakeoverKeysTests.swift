import TransomEngine
import Testing

/// The NX → Carbon modifier mapping for the freed chords (values from 06-SPIKE "hotkeys").
@Suite struct TakeoverKeysTests {
    @Test(arguments: [
        (UInt32(0x840000), 0x1000),  // ⌃↑ (32)
        (0x860000, 0x1200),  // ⌃⇧↑ (34)
        (0x960000, 0x1300),  // ⌘⌃⇧ + fn
        (0x180000, 0x900),  // ⌥⌘
        (0x820000, 0x200),  // ⇧F3 (113)
        (0x800000, 0),  // fn alone: F3 (108)
        (0, 0),
    ])
    func nxFlagsMapToCarbonModifiers(nx: UInt32, carbon: Int) {
        #expect(TakeoverKeys.carbonModifiers(nx: nx) == carbon)
    }

    @Test func theMissionControlKeyIs160() {
        #expect(TakeoverKeys.missionControlKeyCode == 160)
    }
}

@testable import TransomEngine
import Testing

private func desktop(_ n: Int) -> SpaceInfo { SpaceInfo(id: UInt64(n), uuid: "S\(n)", kind: .desktop, displayUUID: "D", index: n) }
private let fullScreen = SpaceInfo(id: 99, uuid: "F", kind: .fullScreen, displayUUID: "D", index: 0)

/// The getter as a table: id → (enabled, key code, NX modifiers). Missing IDs answer nil.
private func table(_ entries: [Int32: SpaceSwitchPlan.HotKey]) -> (Int32) -> SpaceSwitchPlan.HotKey? { { entries[$0] } }

private let ctrlFn: UInt64 = 0x84_0000

/// 06-RESEARCH Pattern 3 steps 1 and 3, with 06-SPIKE "Switch method": posted chords keep the hotkey's fn flag.
struct SpaceSwitchPlanTests {
    @Test func moveRightTwiceUsesTheUsersChordWithItsFnFlag() {
        let chords = SpaceSwitchPlan.plan(from: 0, to: 2, target: desktop(3), hotkeys: table([81: (true, 124, 0x84_0000)]))
        #expect(chords == [Chord(keyCode: 124, flags: ctrlFn), Chord(keyCode: 124, flags: ctrlFn)])
        #expect(chords.allSatisfy { $0.flags & 0x80_0000 != 0 && $0.flags & 0x4_0000 != 0 })
    }

    @Test func moveLeftOnceUsesHotkey79() {
        let chords = SpaceSwitchPlan.plan(from: 1, to: 0, target: desktop(1), hotkeys: table([79: (true, 123, 0x84_0000)]))
        #expect(chords == [Chord(keyCode: 123, flags: ctrlFn)])
    }

    @Test func aCustomisedMoveChordIsPostedAsTheUserSetIt() {
        // ⌥→ with fn: the user's own chord, not ⌃→.
        let chords = SpaceSwitchPlan.plan(from: 0, to: 1, target: desktop(2), hotkeys: table([81: (true, 124, 0x88_0000)]))
        #expect(chords == [Chord(keyCode: 124, flags: 0x88_0000)])
    }

    @Test func anEnabledSwitchToDesktopNIsOneChord() {
        let chords = SpaceSwitchPlan.plan(
            from: 0, to: 2, target: desktop(3), hotkeys: table([120: (true, 20, 0x4_0000), 81: (true, 124, 0x84_0000)]))
        #expect(chords == [Chord(keyCode: 20, flags: 0x4_0000)])
    }

    @Test func aDisabledSwitchToDesktopNFallsBackToMoves() {
        let chords = SpaceSwitchPlan.plan(
            from: 0, to: 2, target: desktop(3), hotkeys: table([120: (false, 20, 0x4_0000), 81: (true, 124, 0x84_0000)]))
        #expect(chords == Array(repeating: Chord(keyCode: 124, flags: ctrlFn), count: 2))
    }

    @Test func aFullScreenTargetAlwaysMoves() {
        let chords = SpaceSwitchPlan.plan(from: 0, to: 1, target: fullScreen, hotkeys: table([118: (true, 18, 0x4_0000)]))
        #expect(chords == [SpaceSwitchPlan.moveRight])
    }

    @Test func desktopsPast16NeverUseSwitchToDesktop() {
        let seventeenth = SpaceSwitchPlan.plan(from: 15, to: 16, target: desktop(17), hotkeys: table([134: (true, 18, 0x4_0000)]))
        #expect(seventeenth == [SpaceSwitchPlan.moveRight])
    }

    @Test func noGetterMeansTheDefaultChords() {
        let none = table([:])
        #expect(SpaceSwitchPlan.plan(from: 0, to: 1, target: desktop(2), hotkeys: none) == [Chord(keyCode: 124, flags: ctrlFn)])
        #expect(SpaceSwitchPlan.plan(from: 2, to: 0, target: desktop(1), hotkeys: none) == Array(repeating: Chord(keyCode: 123, flags: ctrlFn), count: 2))
    }

    /// WR-07: macOS ignores a disabled hotkey's chord (06-SPIKE), so a posted ⌃→ would only reach the frontmost app.
    @Test func disabledMoveHotkeysMeanNoRoute() {
        let off = table([79: (false, 0, 0x8_0000), 81: (false, 0, 0x8_0000)])
        #expect(SpaceSwitchPlan.plan(from: 0, to: 1, target: desktop(2), hotkeys: off).isEmpty)
        #expect(SpaceSwitchPlan.plan(from: 1, to: 0, target: desktop(1), hotkeys: off).isEmpty)
    }

    @Test func noDeltaNoChords() {
        #expect(SpaceSwitchPlan.plan(from: 1, to: 1, target: desktop(2), hotkeys: table([119: (true, 19, 0x4_0000)])).isEmpty)
    }

    @Test func cgFlagsKeepModifiersAndFnAndDropEverythingElse() {
        #expect(SpaceSwitchPlan.cgFlags(nx: 0x96_0000) == 0x96_0000)  // ⌘⌃⇧ + fn, as the getter reports it
        #expect(SpaceSwitchPlan.cgFlags(nx: 0x86_0000) == 0x86_0000)  // ⌃⇧ + fn
        #expect(SpaceSwitchPlan.cgFlags(nx: 0xA5_0000) == 0x84_0000)  // caps lock and numeric pad dropped
        #expect(SpaceSwitchPlan.cgFlags(nx: 0x4_00FF) == 0x4_0000)  // device-dependent bits dropped
    }
}

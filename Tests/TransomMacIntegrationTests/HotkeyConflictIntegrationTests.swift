import AppKit
import KeyboardShortcuts
@testable import TransomMac
import Testing

/// 08.1.1 UI-SPEC "default chords vs macOS shortcuts": the ten halves-and-thirds chords against this macOS's own symbolic
/// hotkeys (`isTakenBySystem`). VM only, so each OS version in the matrix answers for itself.
@Suite(
    .serialized, .enabled(if: IntegrationEnv.trusted, "needs a process with the Accessibility grant"),
    .enabled(if: IntegrationEnv.inVM, "reads the VM's own shortcuts; VM only"))
@MainActor struct HotkeyConflictIntegrationTests {
    init() { _ = NSApplication.shared }

    @Test
    func theTenDockChordsAreFreeOnThisMacOS() {
        let dock: [KeyboardShortcuts.Name] = [
            .dockLeftHalf, .dockRightHalf, .dockTopHalf, .dockBottomHalf, .dockLeftThird, .dockCenterThird, .dockRightThird,
            .dockTopThird, .dockMiddleThird, .dockBottomThird,
        ]
        let taken = Hotkeys.systemConflictNames()
        print("systemConflictNames on macOS \(ProcessInfo.processInfo.operatingSystemVersionString): \(taken)")
        #expect(dock.count == 10)
        #expect(Set(dock.map(\.rawValue)).isDisjoint(with: taken), "macOS takes \(dock.map(\.rawValue).filter(taken.contains))")
    }
}

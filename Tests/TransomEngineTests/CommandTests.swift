import TransomEngine
import TransomModel
import Testing

private let pid: Int32 = 900
private let bundleID = "com.example.command"
private let visible = Rect(x: 0, y: 25, width: 1440, height: 875)
private let display = DisplayInfo(uuid: "main", frame: Rect(x: 0, y: 0, width: 1440, height: 900), visibleFrame: visible, currentSpaceID: nil)

private func ref(_ id: UInt32) -> WindowRef {
    WindowRef(identity: WindowIdentity(windowID: id, pid: pid, bundleID: bundleID))
}

private let w1 = ref(1), w2 = ref(2)

private func window(_ id: UInt32, x: Double) -> WindowInfo {
    WindowInfo(window: ref(id), frame: Rect(x: x, y: 80, width: 300, height: 200), state: .present, displayUUID: "main", kind: .dockable)
}

/// w1 and w2 floating on the main display.
private func started() -> Arranger {
    var arranger = Arranger()
    _ = arranger.handle(.inventory(WindowInventory(displays: [display], windows: [window(1, x: 40), window(2, x: 800)])), now: .now)
    return arranger
}

private let arrangeCommands: [Command] = [.dock, .float, .undo, .focus(.left), .finderSplit]

/// UI-SPEC Surface 1 disabled-state rules: the one rule that greys menu items and makes a refused hotkey beep.
@Suite struct CommandTests {
    @Test func withNoFocusedWindowTheWindowScopedItemsAreOff() {
        var arranger = started()
        _ = arranger.handle(.command(.dock, focused: w1), now: .now)
        let none = CommandContext(focused: nil, ready: true)
        #expect(!arranger.availability(.dock, context: none))
        #expect(!arranger.availability(.float, context: none))
        #expect(!arranger.availability(.focus(.right), context: none))
    }

    @Test func whileNotReadyEveryArrangeItemIsOff() {
        var arranger = started()
        _ = arranger.handle(.command(.dock, focused: w1), now: .now)
        let ready = CommandContext(focused: w2, ready: true), notReady = CommandContext(focused: w2, ready: false)
        #expect(arranger.availability(.dock, context: ready))
        for command in arrangeCommands {
            #expect(!arranger.availability(command, context: notReady), "\(command) is on while not ready")
        }
    }

    @Test func isAvailableIsTheReadyCaseOfTheSameRule() {
        var arranger = started()
        _ = arranger.handle(.command(.dock, focused: w1), now: .now)
        for command in arrangeCommands {
            for focused in [w1, w2, nil] as [WindowRef?] {
                #expect(arranger.isAvailable(command, focused: focused) == arranger.availability(command, context: CommandContext(focused: focused, ready: true)))
            }
        }
    }
}

import AppKit
import KeyboardShortcuts
import TransomEngine
import os

// These raw names are a persistent contract (Pitfall 13): KeyboardShortcuts stores each binding under
// `KeyboardShortcuts_<name>`, so the Phase 4 recorder reuses them. Never rename one.
// Retired raw values, never to be reused for another command (a user's old binding is stored under them):
// toggleDesktop (8.1.1 D-09), frameDesktop (8.1.1 D-13).
extension KeyboardShortcuts.Name {
    static let dock = Self("dock", initial: .init(.d, modifiers: [.control, .option, .command]))
    static let float = Self("float", initial: .init(.f, modifiers: [.control, .option, .command]))
    static let undo = Self("undo", initial: .init(.z, modifiers: [.control, .option, .command]))
    static let focusLeft = Self("focusLeft", initial: .init(.leftArrow, modifiers: [.control, .option, .command]))
    static let focusRight = Self("focusRight", initial: .init(.rightArrow, modifiers: [.control, .option, .command]))
    static let focusUp = Self("focusUp", initial: .init(.upArrow, modifiers: [.control, .option, .command]))
    static let focusDown = Self("focusDown", initial: .init(.downArrow, modifiers: [.control, .option, .command]))
    static let finderSplit = Self("finderSplit", initial: .init(.n, modifiers: [.control, .option, .command]))
    static let togglePause = Self("togglePause", initial: .init(.p, modifiers: [.control, .option, .command]))
    static let toggleExcludeFrontmost = Self("toggleExcludeFrontmost", initial: .init(.e, modifiers: [.control, .option, .command]))
    static let moveLeft = Self("moveLeft", initial: .init(.leftArrow, modifiers: [.control, .option, .command, .shift]))
    static let moveRight = Self("moveRight", initial: .init(.rightArrow, modifiers: [.control, .option, .command, .shift]))
    static let moveUp = Self("moveUp", initial: .init(.upArrow, modifiers: [.control, .option, .command, .shift]))
    static let moveDown = Self("moveDown", initial: .init(.downArrow, modifiers: [.control, .option, .command, .shift]))
    static let swapPrevious = Self("swapPrevious", initial: .init(.s, modifiers: [.control, .option, .command]))
    static let growTile = Self("growTile", initial: .init(.equal, modifiers: [.control, .option, .command]))
    static let shrinkTile = Self("shrinkTile", initial: .init(.minus, modifiers: [.control, .option, .command]))
    static let balanceSplit = Self("balanceSplit", initial: .init(.b, modifiers: [.control, .option, .command]))
    static let rotateSplit = Self("rotateSplit", initial: .init(.r, modifiers: [.control, .option, .command]))
    static let flipSplit = Self("flipSplit", initial: .init(.x, modifiers: [.control, .option, .command]))
    static let snapLeftThird = Self("snapLeftThird", initial: .init(.one, modifiers: [.control, .option, .command]))
    static let snapCenterThird = Self("snapCenterThird", initial: .init(.two, modifiers: [.control, .option, .command]))
    static let snapRightThird = Self("snapRightThird", initial: .init(.three, modifiers: [.control, .option, .command]))
    static let snapTopLeft = Self("snapTopLeft", initial: .init(.u, modifiers: [.control, .option, .command]))
    static let snapTopRight = Self("snapTopRight", initial: .init(.i, modifiers: [.control, .option, .command]))
    static let snapBottomLeft = Self("snapBottomLeft", initial: .init(.j, modifiers: [.control, .option, .command]))
    static let snapBottomRight = Self("snapBottomRight", initial: .init(.k, modifiers: [.control, .option, .command]))
    static let snapMaximize = Self("snapMaximize", initial: .init(.return, modifiers: [.control, .option, .command]))
    static let snapCenter = Self("snapCenter", initial: .init(.c, modifiers: [.control, .option, .command]))
    static let arrangeAll = Self("arrangeAll", initial: .init(.d, modifiers: [.control, .option, .command, .shift]))
    static let floatAll = Self("floatAll", initial: .init(.f, modifiers: [.control, .option, .command, .shift]))
    static let restoreAll = Self("restoreAll", initial: .init(.zero, modifiers: [.control, .option, .command]))
    // Zoom (04 UI-SPEC Hotkeys and URLs).
    static let zoomOutAll = Self("zoomOutAll", initial: .init(.o, modifiers: [.control, .option, .command]))
    static let stepOut = Self("stepOut", initial: .init(.comma, modifiers: [.control, .option, .command]))
    static let stepIn = Self("stepIn", initial: .init(.period, modifiers: [.control, .option, .command]))
    static let zoomBack = Self("zoomBack", initial: .init(.leftBracket, modifiers: [.control, .option, .command]))
    static let zoomForward = Self("zoomForward", initial: .init(.rightBracket, modifiers: [.control, .option, .command]))
    static let panLeft = Self("panLeft", initial: .init(.home, modifiers: [.control, .option, .command]))
    static let panRight = Self("panRight", initial: .init(.end, modifiers: [.control, .option, .command]))
    static let panUp = Self("panUp", initial: .init(.pageUp, modifiers: [.control, .option, .command]))
    static let panDown = Self("panDown", initial: .init(.pageDown, modifiers: [.control, .option, .command]))
    static let frameWindow = Self("frameWindow", initial: .init(.m, modifiers: [.control, .option, .command]))
    // Overview (06 UI-SPEC Surface 4).
    static let showOverview = Self("showOverview", initial: .init(.a, modifiers: [.control, .option, .command]))
    // Tabs (07 UI-SPEC Surface 7): not zoom names, so they stay enabled with zoom off.
    static let nextTab = Self("nextTab", initial: .init(.t, modifiers: [.control, .option, .command]))
    static let previousTab = Self("previousTab", initial: .init(.t, modifiers: [.control, .option, .command, .shift]))
    static let moveOutOfGroup = Self("moveOutOfGroup", initial: .init(.l, modifiers: [.control, .option, .command]))
    // Saved views (08 UI-SPEC Surface 3): zoom names, bound by key position. KeyboardShortcuts writes `initial` into
    // UserDefaults on first construction, so the OS-version rule is decided once; only Restore Defaults re-evaluates it
    // (RESEARCH Pitfall 6). Never set these shortcuts programmatically.
    static let view1 = Self("view1", initial: ViewChords.shortcut(1, save: false))
    static let view2 = Self("view2", initial: ViewChords.shortcut(2, save: false))
    static let view3 = Self("view3", initial: ViewChords.shortcut(3, save: false))
    static let view4 = Self("view4", initial: ViewChords.shortcut(4, save: false))
    static let view5 = Self("view5", initial: ViewChords.shortcut(5, save: false))
    static let view6 = Self("view6", initial: ViewChords.shortcut(6, save: false))
    static let view7 = Self("view7", initial: ViewChords.shortcut(7, save: false))
    static let view8 = Self("view8", initial: ViewChords.shortcut(8, save: false))
    static let view9 = Self("view9", initial: ViewChords.shortcut(9, save: false))
    static let saveView1 = Self("saveView1", initial: ViewChords.shortcut(1, save: true))
    static let saveView2 = Self("saveView2", initial: ViewChords.shortcut(2, save: true))
    static let saveView3 = Self("saveView3", initial: ViewChords.shortcut(3, save: true))
    static let saveView4 = Self("saveView4", initial: ViewChords.shortcut(4, save: true))
    static let saveView5 = Self("saveView5", initial: ViewChords.shortcut(5, save: true))
    static let saveView6 = Self("saveView6", initial: ViewChords.shortcut(6, save: true))
    static let saveView7 = Self("saveView7", initial: ViewChords.shortcut(7, save: true))
    static let saveView8 = Self("saveView8", initial: ViewChords.shortcut(8, save: true))
    static let saveView9 = Self("saveView9", initial: ViewChords.shortcut(9, save: true))
    // Halves and thirds (08.1.1 UI-SPEC Surface 4): not zoom names, so they stay enabled with zoom off. Bound by key position.
    static let dockLeftHalf = Self("dockLeftHalf", initial: .init(.y, modifiers: [.control, .option, .command, .shift]))
    static let dockRightHalf = Self("dockRightHalf", initial: .init(.u, modifiers: [.control, .option, .command, .shift]))
    static let dockTopHalf = Self("dockTopHalf", initial: .init(.h, modifiers: [.control, .option, .command, .shift]))
    static let dockBottomHalf = Self("dockBottomHalf", initial: .init(.j, modifiers: [.control, .option, .command, .shift]))
    static let dockLeftThird = Self("dockLeftThird", initial: .init(.i, modifiers: [.control, .option, .command, .shift]))
    static let dockCenterThird = Self("dockCenterThird", initial: .init(.o, modifiers: [.control, .option, .command, .shift]))
    static let dockRightThird = Self("dockRightThird", initial: .init(.p, modifiers: [.control, .option, .command, .shift]))
    static let dockTopThird = Self("dockTopThird", initial: .init(.k, modifiers: [.control, .option, .command, .shift]))
    static let dockMiddleThird = Self("dockMiddleThird", initial: .init(.l, modifiers: [.control, .option, .command, .shift]))
    static let dockBottomThird = Self("dockBottomThird", initial: .init(.semicolon, modifiers: [.control, .option, .command, .shift]))
    // Fourths (08.1 UI-SPEC Surface 4): not zoom names, so they stay enabled with zoom off. Bound by key position.
    static let dockColumn1 = Self("dockColumn1", initial: .init(.one, modifiers: [.control, .option, .command, .shift]))
    static let dockColumn2 = Self("dockColumn2", initial: .init(.two, modifiers: [.control, .option, .command, .shift]))
    static let dockColumn3 = Self("dockColumn3", initial: .init(.three, modifiers: [.control, .option, .command, .shift]))
    static let dockColumn4 = Self("dockColumn4", initial: .init(.four, modifiers: [.control, .option, .command, .shift]))
    static let dockColumnMiddle = Self("dockColumnMiddle", initial: .init(.five, modifiers: [.control, .option, .command, .shift]))
    static let dockRow1 = Self("dockRow1", initial: .init(.six, modifiers: [.control, .option, .command, .shift]))
    static let dockRow2 = Self("dockRow2", initial: .init(.seven, modifiers: [.control, .option, .command, .shift]))
    static let dockRow3 = Self("dockRow3", initial: .init(.eight, modifiers: [.control, .option, .command, .shift]))
    static let dockRow4 = Self("dockRow4", initial: .init(.nine, modifiers: [.control, .option, .command, .shift]))
    static let dockRowMiddle = Self("dockRowMiddle", initial: .init(.zero, modifiers: [.control, .option, .command, .shift]))
}

/// The saved-view defaults (D-01): ⌥1–9 and ⇧⌥1–9, or ⌃⌥ / ⇧⌃⌥ on macOS 15.0 and 15.1, which refuse Option-only and
/// Option+Shift-only hotkeys.
enum ViewChords {
    static func modifiers(save: Bool, os: OperatingSystemVersion = ProcessInfo.processInfo.operatingSystemVersion) -> NSEvent.ModifierFlags {
        var flags: NSEvent.ModifierFlags = os.majorVersion == 15 && os.minorVersion <= 1 ? [.control, .option] : [.option]
        if save { flags.insert(.shift) }
        return flags
    }

    /// The digit-row keys 1–9 (ANSI key codes, so the physical keys on any layout).
    static let digits: [KeyboardShortcuts.Key] = [.one, .two, .three, .four, .five, .six, .seven, .eight, .nine]

    static func shortcut(_ number: Int, save: Bool) -> KeyboardShortcuts.Shortcut {
        .init(digits[number - 1], modifiers: modifiers(save: save))
    }
}

/// The hotkey table (UI-SPEC Surface 6): fixed ⌃⌥⌘ defaults, each running the same dispatch as every other route.
enum Hotkeys {
    static let entries: [(name: KeyboardShortcuts.Name, command: Command)] = [
        (.dock, .dock),
        (.float, .float),
        (.undo, .undo),
        (.focusLeft, .focus(.left)),
        (.focusRight, .focus(.right)),
        (.focusUp, .focus(.top)),
        (.focusDown, .focus(.bottom)),
        (.finderSplit, .finderSplit),
        (.togglePause, .togglePause),
        (.toggleExcludeFrontmost, .toggleExcludeFrontmost),
        (.moveLeft, .moveOrSnap(.left)),
        (.moveRight, .moveOrSnap(.right)),
        (.moveUp, .moveOrSnap(.top)),
        (.moveDown, .moveOrSnap(.bottom)),
        (.swapPrevious, .swapPrevious),
        (.growTile, .growTile),
        (.shrinkTile, .shrinkTile),
        (.balanceSplit, .balanceSplit),
        (.rotateSplit, .rotateSplit),
        (.flipSplit, .flipSplit),
        (.snapLeftThird, .snap(.leftThird)),
        (.snapCenterThird, .snap(.centerThird)),
        (.snapRightThird, .snap(.rightThird)),
        (.snapTopLeft, .snap(.topLeft)),
        (.snapTopRight, .snap(.topRight)),
        (.snapBottomLeft, .snap(.bottomLeft)),
        (.snapBottomRight, .snap(.bottomRight)),
        (.snapMaximize, .snap(.maximize)),
        (.snapCenter, .snap(.center)),
        (.arrangeAll, .arrangeAll),
        (.floatAll, .floatAll),
        (.restoreAll, .restoreAll),
        (.zoomOutAll, .camera(.zoomOutAll)),
        (.stepOut, .camera(.stepOut)),
        (.stepIn, .camera(.stepIn)),
        (.zoomBack, .camera(.back)),
        (.zoomForward, .camera(.forward)),
        (.panLeft, .camera(.pan(.left))),
        (.panRight, .camera(.pan(.right))),
        (.panUp, .camera(.pan(.top))),
        (.panDown, .camera(.pan(.bottom))),
        (.frameWindow, .camera(.frameWindow)),
        (.showOverview, .camera(.overview)),
        (.nextTab, .tabs(.next)),
        (.previousTab, .tabs(.previous)),
        (.moveOutOfGroup, .tabs(.moveOut)),
        (.view1, .camera(.view(ViewSlot(1)!))),
        (.view2, .camera(.view(ViewSlot(2)!))),
        (.view3, .camera(.view(ViewSlot(3)!))),
        (.view4, .camera(.view(ViewSlot(4)!))),
        (.view5, .camera(.view(ViewSlot(5)!))),
        (.view6, .camera(.view(ViewSlot(6)!))),
        (.view7, .camera(.view(ViewSlot(7)!))),
        (.view8, .camera(.view(ViewSlot(8)!))),
        (.view9, .camera(.view(ViewSlot(9)!))),
        (.saveView1, .camera(.saveView(ViewSlot(1)!))),
        (.saveView2, .camera(.saveView(ViewSlot(2)!))),
        (.saveView3, .camera(.saveView(ViewSlot(3)!))),
        (.saveView4, .camera(.saveView(ViewSlot(4)!))),
        (.saveView5, .camera(.saveView(ViewSlot(5)!))),
        (.saveView6, .camera(.saveView(ViewSlot(6)!))),
        (.saveView7, .camera(.saveView(ViewSlot(7)!))),
        (.saveView8, .camera(.saveView(ViewSlot(8)!))),
        (.saveView9, .camera(.saveView(ViewSlot(9)!))),
        (.dockLeftHalf, .dockFourth(.firstHalf, .horizontal)),
        (.dockRightHalf, .dockFourth(.secondHalf, .horizontal)),
        (.dockTopHalf, .dockFourth(.firstHalf, .vertical)),
        (.dockBottomHalf, .dockFourth(.secondHalf, .vertical)),
        (.dockLeftThird, .dockFourth(.firstThird, .horizontal)),
        (.dockCenterThird, .dockFourth(.middleThird, .horizontal)),
        (.dockRightThird, .dockFourth(.lastThird, .horizontal)),
        (.dockTopThird, .dockFourth(.firstThird, .vertical)),
        (.dockMiddleThird, .dockFourth(.middleThird, .vertical)),
        (.dockBottomThird, .dockFourth(.lastThird, .vertical)),
        (.dockColumn1, .dockFourth(.first, .horizontal)),
        (.dockColumn2, .dockFourth(.second, .horizontal)),
        (.dockColumn3, .dockFourth(.third, .horizontal)),
        (.dockColumn4, .dockFourth(.fourth, .horizontal)),
        (.dockColumnMiddle, .dockFourth(.middle, .horizontal)),
        (.dockRow1, .dockFourth(.first, .vertical)),
        (.dockRow2, .dockFourth(.second, .vertical)),
        (.dockRow3, .dockFourth(.third, .vertical)),
        (.dockRow4, .dockFourth(.fourth, .vertical)),
        (.dockRowMiddle, .dockFourth(.middle, .vertical)),
    ]

    /// The camera hotkeys: disabled while zoom is off, so their chords reach apps as in Phase 3 (D-D).
    static let zoomNames: [KeyboardShortcuts.Name] = entries.compactMap { if case .camera = $0.command { $0.name } else { nil } }

    /// The docking-position hotkeys (halves, thirds, fourths). They aren't `.camera` commands, so they stay enabled with zoom off (TILE-10).
    static let fourthNames: [KeyboardShortcuts.Name] = entries.compactMap { if case .dockFourth = $0.command { $0.name } else { nil } }

    private static let logger = Logger(subsystem: "com.eightabyte.transom", category: "zoomInput")

    /// Installs a key-down handler per entry. Call once.
    static func register(_ dispatch: @escaping @MainActor (Command) -> Void) {
        for entry in entries {
            KeyboardShortcuts.onKeyDown(for: entry.name) { dispatch(entry.command) }
        }
    }

    static func setZoomHotkeys(enabled: Bool) {
        if enabled { KeyboardShortcuts.enable(zoomNames) } else { KeyboardShortcuts.disable(zoomNames) }
    }

    /// The zoom and docking-position defaults macOS also uses (⌃⌥⌘, and ⌃⌥⌘. when the contrast shortcuts are on); macOS takes them.
    static func logSystemConflicts() {
        let taken = Set(systemConflictNames())
        for name in zoomNames + fourthNames where taken.contains(name.rawValue) {
            guard let chord = name.initialShortcut else { continue }
            logger.info("hotkey \(name.rawValue, privacy: .public) \(chord.description, privacy: .public) is also a macOS shortcut; macOS takes it")
        }
    }

    /// The raw names among the zoom and docking-position hotkeys whose default chord macOS also uses (the VM check reads this).
    static func systemConflictNames() -> [String] {
        (zoomNames + fourthNames).filter { $0.initialShortcut?.isTakenBySystem == true }.map(\.rawValue)
    }
}

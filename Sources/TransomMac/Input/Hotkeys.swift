import KeyboardShortcuts
import TransomEngine
import os

// These raw names are a persistent contract (Pitfall 13): KeyboardShortcuts stores each binding under
// `KeyboardShortcuts_<name>`, so the Phase 4 recorder reuses them. Never rename one.
extension KeyboardShortcuts.Name {
    static let dock = Self("dock", initial: .init(.d, modifiers: [.control, .option, .command]))
    static let float = Self("float", initial: .init(.f, modifiers: [.control, .option, .command]))
    static let undo = Self("undo", initial: .init(.z, modifiers: [.control, .option, .command]))
    static let toggleDesktop = Self("toggleDesktop", initial: .init(.h, modifiers: [.control, .option, .command]))
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
    static let frameDesktop = Self("frameDesktop", initial: .init(.g, modifiers: [.control, .option, .command]))
    // Overview (06 UI-SPEC Surface 4).
    static let showOverview = Self("showOverview", initial: .init(.a, modifiers: [.control, .option, .command]))
}

/// The hotkey table (UI-SPEC Surface 6): fixed ⌃⌥⌘ defaults, each running the same dispatch as every other route.
enum Hotkeys {
    static let entries: [(name: KeyboardShortcuts.Name, command: Command)] = [
        (.dock, .dock),
        (.float, .float),
        (.undo, .undo),
        (.toggleDesktop, .toggleDesktop),
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
        (.frameDesktop, .camera(.frameDesktop)),
        (.showOverview, .camera(.overview)),
    ]

    /// The camera hotkeys: disabled while zoom is off, so their chords reach apps as in Phase 3 (D-D).
    static let zoomNames: [KeyboardShortcuts.Name] = entries.compactMap { if case .camera = $0.command { $0.name } else { nil } }

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

    /// The zoom defaults macOS also uses (⌃⌥⌘, and ⌃⌥⌘. when the contrast shortcuts are on); macOS takes them.
    static func logSystemConflicts() {
        for name in zoomNames {
            guard let chord = name.initialShortcut, chord.isTakenBySystem else { continue }
            logger.info("hotkey \(name.rawValue, privacy: .public) \(chord.description, privacy: .public) is also a macOS shortcut; macOS takes it")
        }
    }
}

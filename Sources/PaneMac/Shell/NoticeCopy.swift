import PaneEngine
import PaneModel

/// Toast copy from UI-SPEC Surface 4. Pure strings, no AppKit types. `appName` gives a window's app name; it is
/// passed through `MenuCopy.truncatedAppName` here. Window titles never appear (T-03-14).
nonisolated public enum NoticeCopy {
    public static func text(for notice: Notice, appName: (WindowRef) -> String) -> String {
        switch notice {
        case .lostRoom(let windows):
            if windows.count == 1, let window = windows.first {
                "A \u{201C}\(MenuCopy.truncatedAppName(appName(window)))\u{201D} window no longer fits its tile, so it's floating on the Desktop."
            } else {
                "\(windows.count) windows no longer fit their tiles, so they're floating on the Desktop."
            }
        case .finderNoWindow:
            "Finder didn't open a new window."
        case .floatedAll(let count):
            "Floated \(count == 1 ? "1 window" : "\(count) windows"). Undo with \u{2303}\u{2325}\u{2318}Z."
        case .arrangeLeftovers(let count):
            count == 1
                ? "1 window didn't fit, so it stays floating on the Desktop."
                : "\(count) windows didn't fit, so they stay floating on the Desktop."
        case .crashLoop:
            "Pane quit unexpectedly twice in a minute, so arranging is paused. Your windows are on screen. Choose Resume Arranging from the Pane menu when you're ready."
        case .crashRecovered(let unplaced):
            "Pane quit unexpectedly. Your windows are back on screen and your layout is restored."
                + (unplaced == 0 ? ""
                    : unplaced == 1 ? " 1 window couldn't be placed and is floating on the Desktop."
                    : " \(unplaced) windows couldn't be placed and are floating on the Desktop.")
        }
    }

    /// The SF Symbol shown before the text.
    public static func glyph(for notice: Notice) -> String {
        switch notice {
        case .lostRoom, .floatedAll, .arrangeLeftovers: "macwindow"
        case .finderNoWindow: "info.circle"
        case .crashRecovered, .crashLoop: "lifepreserver"
        }
    }
}

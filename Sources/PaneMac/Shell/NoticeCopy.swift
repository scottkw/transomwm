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
        }
    }

    /// The SF Symbol shown before the text.
    public static func glyph(for notice: Notice) -> String {
        switch notice {
        case .lostRoom: "macwindow"
        case .finderNoWindow: "info.circle"
        }
    }
}

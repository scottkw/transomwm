import TransomEngine
import TransomModel

/// Toast copy from UI-SPEC Surface 4. Pure strings, no AppKit types. `appName` gives a window's app name; it is
/// passed through `MenuCopy.truncatedAppName` here. Window titles never appear (T-03-14).
nonisolated public enum NoticeCopy {
    public static func text(for notice: Notice, appName: (WindowRef) -> String) -> String {
        switch notice {
        case .lostRoom(let windows):
            if windows.count == 1, let window = windows.first {
                "A \u{201C}\(MenuCopy.truncatedAppName(appName(window)))\u{201D} window no longer fits its tile, so it's floating."
            } else {
                "\(windows.count) windows no longer fit their tiles, so they're floating."
            }
        case .finderNoWindow:
            "Finder didn't open a new window."
        case .floatedAll(let count):
            "Floated \(count == 1 ? "1 window" : "\(count) windows"). Undo with \u{2303}\u{2325}\u{2318}Z."
        case .arrangeLeftovers(let count):
            count == 1
                ? "1 window didn't fit, so it stays floating."
                : "\(count) windows didn't fit, so they stay floating."
        case .restored(let count):
            count == 0 ? "All windows were already on screen." : "Moved \(count == 1 ? "1 window" : "\(count) windows") back on screen."
        case .crashLoop:
            "Transom quit unexpectedly twice in a minute, so arranging is paused. Your windows are on screen. Choose Resume Arranging from the Transom menu when you're ready."
        case .turnOffFailed(let conflict):
            "Couldn't turn off \(ConflictCopy.featureName(conflict)). Turn it off here in Desktop & Dock."
        case .settingsRestored:
            "macOS window settings restored."
        case .displaysDisconnected(let names, let count):
            if names.count == 1 {
                "\u{201C}\(MenuCopy.truncatedAppName(names[0]))\u{201D} was disconnected, so "
                    + (count == 1 ? "1 window from it is" : "\(count) windows from it are") + " floating here until you reconnect it."
            } else {
                "\(names.count) displays were disconnected, so "
                    + (count == 1 ? "1 window from them is" : "\(count) windows from them are") + " floating here until you reconnect them."
            }
        case .takeoverCrashed:
            "Transom quit unexpectedly, so Mission Control has its keys back. Turn on Settings ▸ Zoom & Gestures ▸ Use the Mission Control keys for the overview to use them again."
        case .takeoverApplyFailed:
            "Couldn't take over Mission Control's keys, so Mission Control works as before."
        case .crashRecovered(let unplaced):
            "Transom quit unexpectedly. Your windows are back on screen and your layout is restored."
                + (unplaced == 0 ? ""
                    : unplaced == 1 ? " 1 window couldn't be placed and is floating."
                    : " \(unplaced) windows couldn't be placed and are floating.")
        // Saved views (08 UI-SPEC View toasts): N13–N16 are short labels, N17–N19 sentences.
        case .viewSaved(let slot, let replaced, _): replaced ? "Replaced view \(slot.number)" : "Saved view \(slot.number)"
        case .viewShown(let slot, _): "View \(slot.number)"
        case .viewEmpty(let slot, _): "No view in slot \(slot.number)"
        case .viewWindowsClosed(let slot, _): "The windows in view \(slot.number) have closed. Showing all windows."
        case .viewDisplayGone(let slot, _): "View \(slot.number) is on a display that isn't connected."
        case .viewNothingToSave: "There are no windows in this view to save."
        }
    }

    /// The SF Symbol shown before the text.
    public static func glyph(for notice: Notice) -> String {
        switch notice {
        case .lostRoom, .floatedAll, .arrangeLeftovers: "macwindow"
        case .finderNoWindow: "info.circle"
        case .crashRecovered, .crashLoop, .takeoverCrashed: "lifepreserver"
        case .restored, .settingsRestored: "checkmark.circle"
        case .turnOffFailed, .takeoverApplyFailed: "exclamationmark.triangle.fill"
        case .displaysDisconnected, .viewDisplayGone: "display"
        case .viewSaved: "bookmark"
        case .viewShown, .viewEmpty: "viewfinder"
        case .viewWindowsClosed, .viewNothingToSave: "info.circle"
        }
    }

    /// N7 and N11 (a macOS setting change that failed on read-back) use systemOrange; every other glyph is secondary.
    public static func isWarning(_ notice: Notice) -> Bool {
        switch notice {
        case .turnOffFailed, .takeoverApplyFailed: true
        default: false
        }
    }
}

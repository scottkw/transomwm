import TransomEngine
import TransomModel

/// Phase 7 tab-group copy from the UI-SPEC (Copywriting Contract, Accessibility). Pure strings, no AppKit types.
nonisolated public enum TabCopy {
    /// What VoiceOver says for a tab-group change. `appName` names a window's app; it is truncated here
    /// (`MenuCopy.truncatedAppName`).
    public static func announcement(_ announcement: TabAnnouncement, appName: (WindowRef) -> String) -> String {
        switch announcement {
        case .grouped(let tabs): "Grouped as tabs, \(count(tabs))"
        case .added(let tabs): "Added as a tab, \(count(tabs))"
        case .selected(let index, let count): "Tab \(index) of \(count)"
        case .couldNotShow(let window): "Couldn't show \u{201C}\(MenuCopy.truncatedAppName(appName(window)))\u{201D}"
        case .refused(.notInGroup): "The focused window isn't in a tab group"
        case .refused(.paused): "Arranging is paused"
        case .refused(.notReady): OverviewCopy.refusedNotReady
        }
    }

    private static func count(_ tabs: Int) -> String { tabs == 1 ? "1 tab" : "\(tabs) tabs" }
}

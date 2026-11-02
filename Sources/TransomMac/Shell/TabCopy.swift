import TransomEngine
import TransomModel

/// Phase 7 tab-group copy from the UI-SPEC (Copywriting Contract, Accessibility). Pure strings, no AppKit types.
nonisolated public enum TabCopy {
    /// What VoiceOver says for a tab-group change. `appName` names a window's app (pass it through
    /// `MenuCopy.truncatedAppName`).
    public static func announcement(_ announcement: TabAnnouncement, appName: (WindowRef) -> String) -> String {
        switch announcement {
        case .grouped(let tabs): "Grouped as tabs, \(count(tabs))"
        case .added(let tabs): "Added as a tab, \(count(tabs))"
        case .couldNotShow, .selected, .refused: ""  // stand-in until 07-02 Task 3
        }
    }

    private static func count(_ tabs: Int) -> String { tabs == 1 ? "1 tab" : "\(tabs) tabs" }
}

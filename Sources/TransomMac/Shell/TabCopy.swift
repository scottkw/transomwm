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

    /// The strip's accessibility label (UI-SPEC Accessibility); `count` is always 2 or more.
    public static func stripLabel(count: Int) -> String { "Tab group, \(count) windows" }

    /// A tab's accessibility label: "“{App}”, {title}", the app name only when untitled.
    public static func tabLabel(app: String, title: String) -> String {
        let name = "\u{201C}\(MenuCopy.truncatedAppName(app))\u{201D}"
        return title.isEmpty ? name : "\(name), \(title)"
    }

    public static func tabHelp(index: Int, count: Int) -> String { "Tab \(index) of \(count)" }

    /// The overflow button's tooltip and label.
    public static let moreTabs = "More Tabs"

    public static func moreTabsHelp(_ hidden: Int) -> String { hidden == 1 ? "1 more tab" : "\(hidden) more tabs" }

    /// A tab's tooltip and overflow item: its title, else its app name.
    public static func titleOrApp(title: String, app: String) -> String { title.isEmpty ? MenuCopy.truncatedAppName(app) : title }

    private static func count(_ tabs: Int) -> String { tabs == 1 ? "1 tab" : "\(tabs) tabs" }
}

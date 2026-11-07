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
        case .didNotClose(let window): "\u{201C}\(MenuCopy.truncatedAppName(appName(window)))\u{201D} didn't close"
        case .ended: "Tab group ended"
        case .movedOut(let dissolved): dissolved ? "Moved out of the tab group. Tab group ended." : "Moved out of the tab group"
        case .tearOffCanceled: "Tab move canceled"
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

    /// A collapsed group's block (UI-SPEC Surface 6): "Tab group, {n} windows, collapsed: “{App}”, {title}".
    public static func collapsedGroupLabel(count: Int, app: String, title: String) -> String {
        "\(stripLabel(count: count)), collapsed: \(tabLabel(app: app, title: title))"
    }

    /// A collapsed block's label card, line 2 (UI-SPEC Surface 7): one window, or a tab group of `n`.
    public static let collapsed = "Collapsed"
    public static func collapsedWindows(_ n: Int) -> String { "\(n) windows, collapsed" }

    /// Added to an overview group tile's selection announcement (UI-SPEC Surface 6).
    public static func overviewTabSuffix(index: Int, count: Int) -> String { ", tab \(index) of \(count)" }

    /// The group buttons' tooltips and labels (UI-SPEC Surface 4).
    public static let closeGroup = "Close Group"
    public static let minimizeGroup = "Minimize Group"
    public static let floatGroup = "Float Group"
    public static let dockGroup = "Dock Group"

    /// The tab context menu's items and VoiceOver custom actions (UI-SPEC Surface 4).
    public static let closeTab = "Close Tab"
    public static let moveOut = "Move Out of Group"

    /// The Arrange ▸ Tabs submenu and Shortcuts section (UI-SPEC Surface 7); Move Out of Group is `moveOut`.
    public static let tabsMenu = "Tabs"
    public static let nextTab = "Next Tab"
    public static let previousTab = "Previous Tab"

    /// Close Group's confirmation alert (UI-SPEC Surface 4); `count` is always 2 or more.
    public static func closeGroupAlertMessage(_ count: Int) -> String { "Close all \(count) windows in this tab group?" }
    public static let closeGroupAlertInformative = "Apps may ask to save changes before their windows close."
    public static let closeGroupAlertCancel = "Cancel"
    public static let doNotShowAgain = "Do not show this again"

    /// Close Group's accessibility help.
    public static func closeGroupHelp(_ count: Int) -> String { "Closes all \(count) windows in this tab group" }

    /// The overflow button's tooltip and label.
    public static let moreTabs = "More Tabs"

    public static func moreTabsHelp(_ hidden: Int) -> String { hidden == 1 ? "1 more tab" : "\(hidden) more tabs" }

    /// A tab's tooltip and overflow item: its title, else its app name.
    public static func titleOrApp(title: String, app: String) -> String { title.isEmpty ? MenuCopy.truncatedAppName(app) : title }

    /// The Debug submenu's line; a group always has 2 or more tabs, so "tabs" needs no singular branch.
    public static func debugLine(groups: Int, tabs: Int) -> String {
        switch groups {
        case 0: "Tab groups: none"
        case 1: "Tab groups: 1 group, \(tabs) tabs"
        default: "Tab groups: \(groups) groups, \(tabs) tabs"
        }
    }

    private static func count(_ tabs: Int) -> String { tabs == 1 ? "1 tab" : "\(tabs) tabs" }
}

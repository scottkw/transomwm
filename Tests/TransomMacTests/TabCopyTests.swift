import TransomEngine
import TransomMac
import TransomModel
import Testing

/// UI-SPEC Copywriting Contract and Accessibility: the tab-group announcements.
@Suite struct TabCopyTests {
    private func spoken(_ announcement: TabAnnouncement) -> String {
        TabCopy.announcement(announcement, appName: { _ in "Safari" })
    }

    @Test(arguments: [
        (TabAnnouncement.grouped(tabs: 2), "Grouped as tabs, 2 tabs"),
        (.added(tabs: 3), "Added as a tab, 3 tabs"),
        (.added(tabs: 1), "Added as a tab, 1 tab"),
    ])
    func theAnnouncementsMatchTheContract(announcement: TabAnnouncement, expected: String) {
        #expect(spoken(announcement) == expected)
    }

    private static let textEdit = WindowRef(identity: WindowIdentity(windowID: 7, pid: 70, bundleID: "com.apple.TextEdit"))
    private static let long = String(repeating: "A", count: 40)

    @Test(arguments: [
        (TabAnnouncement.selected(index: 2, count: 3), "TextEdit", "Tab 2 of 3"),
        (.selected(index: 1, count: 1), "TextEdit", "Tab 1 of 1"),
        (.couldNotShow(textEdit), "TextEdit", "Couldn't show \u{201C}TextEdit\u{201D}"),
        (.couldNotShow(textEdit), long, "Couldn't show \u{201C}\(String(repeating: "A", count: 32))\u{2026}\u{201D}"),
        (.refused(.notInGroup), "TextEdit", "The focused window isn't in a tab group"),
        (.refused(.paused), "TextEdit", "Arranging is paused"),
        (.refused(.notReady), "TextEdit", "Transom needs Accessibility access"),
        (.didNotClose(textEdit), "TextEdit", "\u{201C}TextEdit\u{201D} didn't close"),
        (.didNotClose(textEdit), long, "\u{201C}\(String(repeating: "A", count: 32))\u{2026}\u{201D} didn't close"),
        (.ended, "TextEdit", "Tab group ended"),
        (.movedOut(dissolved: false), "TextEdit", "Moved out of the tab group"),
        (.movedOut(dissolved: true), "TextEdit", "Moved out of the tab group. Tab group ended."),
        (.tearOffCanceled, "TextEdit", "Tab move canceled"),
    ])
    func selectionAndRefusalsMatchTheContract(announcement: TabAnnouncement, app: String, expected: String) {
        #expect(TabCopy.announcement(announcement, appName: { _ in app }) == expected)
    }

    @Test func theStripReadsAsATabGroup() {
        #expect(TabCopy.stripLabel(count: 2) == "Tab group, 2 windows")
        #expect(TabCopy.tabLabel(app: "Notes", title: "") == "\u{201C}Notes\u{201D}")
        #expect(TabCopy.tabLabel(app: "Notes", title: "List") == "\u{201C}Notes\u{201D}, List")
        #expect(TabCopy.tabHelp(index: 2, count: 3) == "Tab 2 of 3")
        #expect(TabCopy.moreTabs == "More Tabs")
        #expect(TabCopy.moreTabsHelp(1) == "1 more tab")
        #expect(TabCopy.moreTabsHelp(3) == "3 more tabs")
        #expect(TabCopy.titleOrApp(title: "", app: "Notes") == "Notes")
        #expect(TabCopy.titleOrApp(title: "List", app: "Notes") == "List")
    }

    @Test func theGroupButtonsMatchTheContract() {
        #expect(TabCopy.closeGroup == "Close Group")
        #expect(TabCopy.minimizeGroup == "Minimize Group")
        #expect(TabCopy.floatGroup == "Float Group" && TabCopy.dockGroup == "Dock Group")
        #expect(TabCopy.closeGroupHelp(3) == "Closes all 3 windows in this tab group")
        #expect(TabCopy.closeTab == "Close Tab" && TabCopy.moveOut == "Move Out of Group")
    }

    /// UI-SPEC Surface 7 Debug line and the Tabs submenu copy.
    @Test func theDebugLineHasExplicitGroupBranches() {
        #expect(TabCopy.debugLine(groups: 0, tabs: 0) == "Tab groups: none")
        #expect(TabCopy.debugLine(groups: 1, tabs: 3) == "Tab groups: 1 group, 3 tabs")
        #expect(TabCopy.debugLine(groups: 2, tabs: 5) == "Tab groups: 2 groups, 5 tabs")
        #expect(TabCopy.tabsMenu == "Tabs" && TabCopy.nextTab == "Next Tab" && TabCopy.previousTab == "Previous Tab")
    }
}

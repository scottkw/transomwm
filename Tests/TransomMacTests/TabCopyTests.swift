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
    ])
    func selectionAndRefusalsMatchTheContract(announcement: TabAnnouncement, app: String, expected: String) {
        #expect(TabCopy.announcement(announcement, appName: { _ in app }) == expected)
    }
}

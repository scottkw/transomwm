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
}

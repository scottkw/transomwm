import PaneMac
import Testing

@Suite struct MenuCopyTests {
    @Test(arguments: [
        (0, 0, "No windows to track"),
        (1, 1, "Tracking 1 window in 1 app"),
        (2, 1, "Tracking 2 windows in 1 app"),
        (12, 5, "Tracking 12 windows in 5 apps"),
    ])
    func headerIsPluralCorrect(windows: Int, apps: Int, expected: String) {
        #expect(MenuCopy.header(windows: windows, apps: apps) == expected)
    }

    @Test func degradedLineIsAbsentAtZeroAndPluralCorrect() {
        #expect(MenuCopy.degradedLine(count: 0) == nil)
        #expect(MenuCopy.degradedLine(count: 1) == "1 app not responding")
        #expect(MenuCopy.degradedLine(count: 3) == "3 apps not responding")
    }

    @Test func capabilityItemNamesTheWindowIDLookupState() {
        #expect(MenuCopy.capabilityItem(windowIDLookupAvailable: true) == "Window ID lookup: available")
        #expect(MenuCopy.capabilityItem(windowIDLookupAvailable: false) == "Window ID lookup: off, matching by frame")
    }

    @Test func appNamesUpToTheLimitAreUnchanged() {
        let name = String(repeating: "a", count: MenuCopy.maxAppNameLength)
        #expect(MenuCopy.maxAppNameLength == 32)
        #expect(MenuCopy.truncatedAppName(name) == name)
        #expect(MenuCopy.truncatedAppName("") == "")
    }

    @Test func longAppNamesAreCutToTheLimitPlusAnEllipsis() {
        let name = String(repeating: "b", count: 32) + "c"
        #expect(MenuCopy.truncatedAppName(name) == String(repeating: "b", count: 32) + "\u{2026}")
    }

    @Test func truncationCountsGraphemesNotScalars() {
        // Each family emoji is one grapheme made of several scalars.
        let family = "👨‍👩‍👧‍👦"
        let name = String(repeating: family, count: 33)
        let cut = MenuCopy.truncatedAppName(name)
        #expect(cut == String(repeating: family, count: 32) + "\u{2026}")
        #expect(cut.count == 33)
    }
}

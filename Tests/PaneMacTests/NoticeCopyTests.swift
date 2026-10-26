import PaneEngine
import PaneMac
import PaneModel
import Testing

private func ref(_ id: UInt32) -> WindowRef {
    WindowRef(identity: WindowIdentity(windowID: id, pid: 42, bundleID: "com.example.notice"))
}

/// N1 copy from UI-SPEC Surface 4, with explicit singular and plural branches.
@Suite struct NoticeCopyTests {
    @Test func oneWindowThatLostItsRoomIsNamedByItsApp() {
        #expect(NoticeCopy.text(for: .lostRoom([ref(1)]), appName: { _ in "Safari" })
            == "A \u{201C}Safari\u{201D} window no longer fits its tile, so it's floating on the Desktop.")
    }

    @Test func severalWindowsThatLostTheirRoomAreCounted() {
        #expect(NoticeCopy.text(for: .lostRoom([ref(1), ref(2)]), appName: { _ in "Safari" })
            == "2 windows no longer fit their tiles, so they're floating on the Desktop.")
    }

    @Test func aLongAppNameIsTruncatedTo32Characters() {
        let name = String(repeating: "x", count: 40)
        #expect(NoticeCopy.text(for: .lostRoom([ref(1)]), appName: { _ in name })
            == "A \u{201C}\(MenuCopy.truncatedAppName(name))\u{201D} window no longer fits its tile, so it's floating on the Desktop.")
    }

    @Test func theLostRoomGlyphIsMacwindow() {
        #expect(NoticeCopy.glyph(for: .lostRoom([ref(1)])) == "macwindow")
    }
}

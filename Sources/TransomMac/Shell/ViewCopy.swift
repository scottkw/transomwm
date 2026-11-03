/// Phase 8 saved-view copy from the UI-SPEC (Surface 3, Debug lines, Announcements). Pure strings, no AppKit types; the toasts are in `NoticeCopy`.
nonisolated public enum ViewCopy {
    /// The Shortcuts window section right after Zoom.
    public static let savedViewsSection = "Saved Views"
    public static let shortcutsFooter = "Saved views work while zoom is on. If \u{2325} with a number types a character you need, choose another shortcut here."

    /// The Debug submenu's line.
    public static func savedViewsLine(slots: [Int]) -> String {
        let list = slots.map(String.init).joined(separator: ", ")
        return switch slots.count {
        case 0: "Saved views: none"
        case 1: "Saved views: 1 slot (\(list))"
        default: "Saved views: \(slots.count) slots (\(list))"
        }
    }

    /// One line for VoiceOver when going to a view moves the camera: the view, then the Phase 4 reveal.
    public static func joinedAnnouncement(slot: Int, reveal: String) -> String { "View \(slot). \(reveal)" }
}

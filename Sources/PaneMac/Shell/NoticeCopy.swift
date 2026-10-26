import PaneEngine
import PaneModel

/// Toast copy from UI-SPEC Surface 4. Pure strings, no AppKit types.
nonisolated public enum NoticeCopy {
    public static func text(for notice: Notice, appName: (WindowRef) -> String) -> String {
        ""
    }

    /// The SF Symbol shown before the text.
    public static func glyph(for notice: Notice) -> String {
        ""
    }
}

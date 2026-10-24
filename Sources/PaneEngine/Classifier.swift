/// What the classifier decided about one AX element.
public enum Classification: Equatable, Sendable {
    /// Not a window at all (Finder's desktop `AXScrollArea`); never tracked.
    case notAWindow
    /// A window and its kind. `reliable` is false when the snapshot was taken minimised, hidden or under a sheet.
    case window(WindowKind, reliable: Bool)
}

/// Per-bundle and per-identifier exceptions to the classifier rules. These are classifier corrections,
/// not user exclusions: D-12's "no hard-coded default exclusions" is untouched.
public struct ClassifierOverrides: Equatable, Sendable {
    /// Apps whose main windows lack an enabled fullscreen button but are still meant to be big.
    public var fullscreenButtonOptional: Set<String>
    /// `AXIdentifier`s of standard-looking windows that are really transient panels.
    public var neverDockIdentifiers: Set<String>

    public init(fullscreenButtonOptional: Set<String>, neverDockIdentifiers: Set<String>) {
        self.fullscreenButtonOptional = fullscreenButtonOptional
        self.neverDockIdentifiers = neverDockIdentifiers
    }

    // Source: RESEARCH Pattern 2 table (AeroSpace AxUiElementWindowType.swift), re-checked by the corpus.
    public static let standard = ClassifierOverrides(
        fullscreenButtonOptional: [
            "com.googlecode.iterm2",  // hides decorations
            "org.alacritty",  // hides decorations
            "net.kovidgoyal.kitty",  // hides decorations
            "com.github.wez.wezterm",  // hides decorations
            "org.gnu.Emacs",  // hides decorations
            "com.microsoft.VSCode",  // nativeFullScreen:false drops the button
            "com.apple.ActivityMonitor",  // no fullscreen button on its main window
            "com.valvesoftware.steam",  // custom chrome
            "com.google.Chrome",  // button missing during tab drag-out
        ],
        neverDockIdentifiers: [
            "com.mitchellh.ghostty.quickTerminal",  // Ghostty's drop-down terminal
            "open_quickly",  // Xcode Open Quickly
        ]
    )
}

/// Decides whether a window may ever be docked (D-06, WIN-05). Pure; rule order is RESEARCH Pattern 2.
public enum Classifier {
    public static func classify(
        _ snapshot: WindowSnapshot, bundleID: String, appHidden: Bool, overrides: ClassifierOverrides = .standard
    ) -> Classification {
        guard snapshot.role == "AXWindow" else { return .notAWindow }
        // Subrole and buttons lie while minimised, hidden or under a sheet (Pitfall 3), so don't judge them then.
        let reliable = !(snapshot.minimized == true || appHidden || snapshot.sheetAttached == true)
        func window(_ kind: WindowKind) -> Classification { .window(kind, reliable: reliable) }

        if let layer = snapshot.cg?.layer, layer != 0 { return window(.neverDock(.floatingLevel)) }
        if let id = snapshot.identifier, overrides.neverDockIdentifiers.contains(id) { return window(.neverDock(.subrole)) }
        guard reliable else { return window(.dockable) }
        if snapshot.subrole != "AXStandardWindow" { return window(.neverDock(.subrole)) }
        if snapshot.modal == true { return window(.neverDock(.modal)) }
        if !snapshot.close.present { return window(.neverDock(.noCloseButton)) }
        let fullscreen = snapshot.fullScreenButton
        if !(fullscreen.present && fullscreen.enabled), !overrides.fullscreenButtonOptional.contains(bundleID) {
            return window(.neverDock(.noFullscreenButton))
        }
        return window(.dockable)
    }
}

/// What the classifier decided about one AX element.
public enum Classification: Equatable, Sendable {
    /// Not a window at all (Finder's desktop `AXScrollArea`); never tracked.
    case notAWindow
    /// A window and its kind. `reliable` is false when the snapshot was taken minimised, hidden or under a sheet.
    case window(WindowKind, reliable: Bool)
}

/// Per-bundle and per-identifier exceptions to the classifier rules. These are not user exclusions (D-12).
public struct ClassifierOverrides: Equatable, Sendable {
    public var fullscreenButtonOptional: Set<String>
    public var neverDockIdentifiers: Set<String>

    public init(fullscreenButtonOptional: Set<String>, neverDockIdentifiers: Set<String>) {
        self.fullscreenButtonOptional = fullscreenButtonOptional
        self.neverDockIdentifiers = neverDockIdentifiers
    }

    public static let standard = ClassifierOverrides(fullscreenButtonOptional: [], neverDockIdentifiers: [])
}

public enum Classifier {
    public static func classify(
        _ snapshot: WindowSnapshot, bundleID: String, appHidden: Bool, overrides: ClassifierOverrides = .standard
    ) -> Classification {
        .notAWindow
    }
}

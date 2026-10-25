import PaneModel

/// The outcome of matching one AX window to the CG window list without `_AXUIElementGetWindow`.
public enum FallbackMatch: Equatable, Sendable {
    case cg(UInt32), ambiguous, none
}

/// Window identity when the private window-ID lookup is unavailable (D-15, SAFE-05).
public enum FallbackMatcher {
    public static let boundsTolerance: Double = 1.0

    public static func match(
        pid: Int32, frame: Rect, title: String, cgWindows: [CGWindowEntry], cgNames: [UInt32: String], excluding: Set<UInt32>
    ) -> FallbackMatch {
        .none
    }

    public static func syntheticPresence(_ tracked: [(identity: WindowIdentity, frame: Rect)], cgWindows: [CGWindowEntry]) -> [CGWindowEntry] {
        []
    }
}

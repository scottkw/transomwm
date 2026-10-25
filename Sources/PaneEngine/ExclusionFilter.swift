import PaneModel

/// Keeps commands away from apps on the user's exclusion list (D-12, WIN-08). Pure, so `AXWindowSystem` and
/// `FakeWindowSystem` run the same check before routing anything.
public enum ExclusionFilter {
    public static func isExcluded(_ bundleID: String, in excluded: Set<String>) -> Bool {
        false
    }

    public static func admit(_ commands: [WindowCommand], excluded: Set<String>) -> (admitted: [WindowCommand], dropped: [WindowCommand]) {
        (commands, [])
    }
}

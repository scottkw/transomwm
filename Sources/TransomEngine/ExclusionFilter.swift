import TransomModel

/// Keeps commands away from apps on the user's exclusion list (D-12, WIN-08). Pure, so `AXWindowSystem` and
/// `FakeWindowSystem` run the same check before routing anything. Matching is case-insensitive and exact:
/// "com.apple.Safari" never excludes "com.apple.SafariTechnologyPreview".
public enum ExclusionFilter {
    public static func isExcluded(_ bundleID: String, in excluded: Set<String>) -> Bool {
        let id = bundleID.lowercased()
        return excluded.contains { $0.lowercased() == id }
    }

    /// Splits `commands` by their window's bundle ID, keeping each side's order.
    public static func admit(_ commands: [WindowCommand], excluded: Set<String>) -> (admitted: [WindowCommand], dropped: [WindowCommand]) {
        guard !excluded.isEmpty else { return (commands, []) }
        let lowered = Set(excluded.map { $0.lowercased() })
        var split: (admitted: [WindowCommand], dropped: [WindowCommand]) = ([], [])
        for command in commands {
            if lowered.contains(command.window.bundleID.lowercased()) { split.dropped.append(command) } else { split.admitted.append(command) }
        }
        return split
    }
}

extension WindowCommand {
    /// The window the command addresses.
    public var window: WindowRef {
        switch self {
        case .setFrame(let ref, _), .park(let ref, _, _), .focus(let ref), .raise(let ref), .setHidden(let ref, _): ref
        }
    }
}

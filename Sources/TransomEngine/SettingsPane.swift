/// The Settings window's tabs in toolbar order (D-01). The raw values are the stored last pane and the `pane=` value a
/// URL or the CLI names (D-04).
public enum SettingsPane: String, CaseIterable, Sendable, Hashable {
    case general, arranging, zoom, shortcuts, exclusions, menubar, updates
}

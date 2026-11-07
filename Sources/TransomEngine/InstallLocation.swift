/// Where the running Transom was installed from (D-10). 09-22 adds `classify`.
public enum InstallLocation {
    public static let caskroomPaths = ["/opt/homebrew/Caskroom/transom", "/usr/local/Caskroom/transom"]

    /// True when either Caskroom folder exists (09 UI-SPEC Surface 3 Homebrew detection).
    public static func isHomebrew(exists: (String) -> Bool) -> Bool { caskroomPaths.contains(where: exists) }
}

/// Where the running Transom was installed from (D-10). 09-22 adds `classify`.
public enum InstallLocation {
    public static let caskroomPaths = ["/opt/homebrew/Caskroom/transom", "/usr/local/Caskroom/transom"]

    public static func isHomebrew(exists: (String) -> Bool) -> Bool { false }
}

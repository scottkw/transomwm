/// Where the running Transom was installed from (D-08, D-10).
public enum InstallLocation {
    public static let caskroomPaths = ["/opt/homebrew/Caskroom/transom", "/usr/local/Caskroom/transom"]

    /// True when either Caskroom folder exists (09 UI-SPEC Surface 3 Homebrew detection).
    public static func isHomebrew(exists: (String) -> Bool) -> Bool { caskroomPaths.contains(where: exists) }

    public enum Place: Equatable, Sendable { case applications, translocated, diskImage, downloads, other }

    /// Where `bundlePath` is (RESEARCH Pattern 6). There is no supported API for a translocated app's original path,
    /// so the path itself is all there is to go on.
    public static func classify(bundlePath: String, home: String) -> Place {
        if bundlePath.contains("/AppTranslocation/") { return .translocated }
        if bundlePath.hasPrefix("/Volumes/") { return .diskImage }
        if bundlePath.hasPrefix(home + "/Downloads/") { return .downloads }
        if bundlePath.hasPrefix("/Applications/") { return .applications }
        return .other
    }

    /// The running bundle's place for Move. Anything but the release bundle is `.other`: Move always targets
    /// /Applications/Transom.app, so a Debug build would trash the release copy and take its name (WR-02).
    public static func classify(bundleID: String?, bundlePath: String, home: String) -> Place {
        bundleID == "com.eightabyte.transom" ? classify(bundlePath: bundlePath, home: home) : .other
    }

    /// Places where macOS may forget permissions, so setup offers Move to Applications first (D-08). A build folder doesn't.
    public static func needsMove(_ place: Place) -> Bool { [.translocated, .diskImage, .downloads].contains(place) }
}

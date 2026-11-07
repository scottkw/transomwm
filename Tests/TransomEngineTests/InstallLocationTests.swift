import TransomEngine
import Testing

/// D-08: which launch places offer Move to Applications.
@Suite struct InstallLocationTests {
    let home = "/Users/someone"

    @Test func aTranslocatedPathIsTranslocated() {
        let path = "/private/var/folders/xy/T/AppTranslocation/1234-ABCD/d/Transom.app"
        #expect(InstallLocation.classify(bundlePath: path, home: home) == .translocated)
        #expect(InstallLocation.needsMove(.translocated))
    }

    @Test func aVolumesPathIsADiskImage() {
        #expect(InstallLocation.classify(bundlePath: "/Volumes/Transom 0.9.0/Transom.app", home: home) == .diskImage)
        #expect(InstallLocation.needsMove(.diskImage))
    }

    @Test func downloadsIsDownloads() {
        #expect(InstallLocation.classify(bundlePath: "/Users/someone/Downloads/Transom.app", home: home) == .downloads)
        #expect(InstallLocation.needsMove(.downloads))
        // Someone else's Downloads, or a folder merely named like it, isn't this user's.
        #expect(InstallLocation.classify(bundlePath: "/Users/other/Downloads/Transom.app", home: home) == .other)
        #expect(InstallLocation.classify(bundlePath: "/Users/someone/Downloads2/Transom.app", home: home) == .other)
    }

    @Test func applicationsAndBuildFoldersNeedNoMove() {
        #expect(InstallLocation.classify(bundlePath: "/Applications/Transom.app", home: home) == .applications)
        #expect(InstallLocation.classify(bundlePath: "/Users/someone/dev/transomwm/build/Transom.app", home: home) == .other)
        #expect(!InstallLocation.needsMove(.applications))
        #expect(!InstallLocation.needsMove(.other))
    }
}

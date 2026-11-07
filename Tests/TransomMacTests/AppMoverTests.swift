import Foundation
import TransomEngine
@testable import TransomMac
import Testing

/// D-08, T-09-47..49: the Move to Applications copy and relaunch, in temporary directories with a fake trash. Nothing
/// here touches /Applications or launches a process.
@Suite @MainActor struct AppMoverTests {
    private func tempDir() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("AppMoverTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    /// A tiny bundle with quarantine on the bundle and on a nested file.
    private func quarantinedBundle(in dir: URL) throws -> URL {
        let bundle = dir.appendingPathComponent("Source/Transom.app")
        let macOS = bundle.appendingPathComponent("Contents/MacOS")
        try FileManager.default.createDirectory(at: macOS, withIntermediateDirectories: true)
        try Data("binary".utf8).write(to: macOS.appendingPathComponent("Transom"))
        let value = Array("0083;00000000;Safari;".utf8)
        for path in [bundle.path, macOS.appendingPathComponent("Transom").path] {
            #expect(setxattr(path, "com.apple.quarantine", value, value.count, 0, 0) == 0)
        }
        return bundle
    }

    private func quarantined(_ path: String) -> Bool { getxattr(path, "com.apple.quarantine", nil, 0, 0, 0) >= 0 }

    @Test func theCopyLandsWithoutQuarantine() throws {
        let dir = try tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let source = try quarantinedBundle(in: dir)
        let destination = dir.appendingPathComponent("Transom.app")
        try AppMover.copy(from: source, to: destination, trash: { (_: URL) throws -> Void in Issue.record("nothing to trash") })
        let binary = destination.appendingPathComponent("Contents/MacOS/Transom").path
        #expect(FileManager.default.fileExists(atPath: binary))
        #expect(!quarantined(destination.path))
        #expect(!quarantined(binary))
        #expect(quarantined(source.path), "the source keeps its quarantine")
    }

    @Test func anExistingCopyGoesToTheTrashNotAway() throws {
        let dir = try tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let source = try quarantinedBundle(in: dir)
        let destination = dir.appendingPathComponent("Transom.app")
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        let fakeTrash = dir.appendingPathComponent("Trash")
        var trashed: [URL] = []
        try AppMover.copy(from: source, to: destination, trash: { (url: URL) throws -> Void in
            trashed.append(url)
            try FileManager.default.moveItem(at: url, to: fakeTrash)
        })
        #expect(trashed == [destination])
        #expect(FileManager.default.fileExists(atPath: fakeTrash.path))
        #expect(FileManager.default.fileExists(atPath: destination.appendingPathComponent("Contents/MacOS/Transom").path))
    }

    @Test func theRelaunchPassesPidAndPathAsArguments() {
        let path = "/Applications/My \"Odd\" $(rm) Transom.app"
        let arguments = AppMover.relaunchArguments(pid: 4242, path: path)
        #expect(arguments.count == 5)
        #expect(arguments[0] == "-c")
        #expect(arguments[2] == "sh")
        #expect(arguments[3] == "4242")
        #expect(arguments[4] == path)
        #expect(!arguments[1].contains("4242"))
        #expect(!arguments[1].contains("Odd"))
        #expect(arguments[1].contains("\"$1\"") && arguments[1].contains("\"$2\""))
    }

    @Test func theMoveBodyNamesThePlace() {
        #expect(OnboardingCopy.moveBody(.diskImage).contains("a disk image"))
        #expect(OnboardingCopy.moveBody(.downloads).contains("your Downloads folder"))
        #expect(OnboardingCopy.moveBody(.translocated).contains("a temporary folder"))
        #expect(
            OnboardingCopy.moveBody(.diskImage)
                == "Transom is running from a disk image. macOS can forget the permissions you give it there, so move it to the Applications folder first.")
    }

    @Test func aFailedCopyKeepsTheStepWithTheFailureText() {
        struct DiskFull: Error {}
        let model = OnboardingModel(steps: [.move, .welcome])
        #expect(!model.copyForMove({ () throws -> Void in throw DiskFull() }))
        #expect(model.current == .move)
        #expect(model.moveFailure == "Couldn't move Transom. Drag it to the Applications folder yourself, then open it from there.")
        #expect(model.copyForMove({ () throws -> Void in }))
        #expect(model.moveFailure == nil)
    }
}

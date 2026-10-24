import Foundation
import Testing

/// Runs scripts/check-no-appkit.sh inside `swift test`, so a UI-framework import in PaneModel or
/// PaneEngine fails every local test run as well as CI (D-23).
@Suite struct NoAppKitTests {
    /// Tests/PaneModelTests/NoAppKitTests.swift -> repo root.
    static let repoRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()

    func runCheck(_ arguments: [String] = []) throws -> Int32 {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = ["scripts/check-no-appkit.sh"] + arguments
        process.currentDirectoryURL = Self.repoRoot
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        process.waitUntilExit()
        return process.terminationStatus
    }

    /// Writes `line` as V.swift in a fresh temp directory and returns the script's exit status for it.
    func check(line: String) throws -> Int32 {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("no-appkit-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        try (line + "\n").write(to: dir.appendingPathComponent("V.swift"), atomically: true, encoding: .utf8)
        return try runCheck([dir.path])
    }

    @Test func realSourcesAreClean() throws {
        #expect(try runCheck() == 0)
    }

    @Test func testSupportAndPrivateAreClean() throws {
        #expect(try runCheck(["Sources/PaneTestSupport", "Sources/PanePrivate"]) == 0)
    }

    @Test(arguments: [
        "import AppKit",
        "@preconcurrency import SwiftUI",
        "import struct Cocoa.NSRect",
        "   @_exported import AppKit",
        "import AppKit;",
        "@_spi(Private) import AppKit",
        "import Foundation; import AppKit",
        "import AppKit.NSView",
        "import WebKit",
        "import Quartz",
        "import Carbon",
    ])
    func violationFails(line: String) throws {
        #expect(try check(line: line) == 1)
    }

    @Test(arguments: [
        "// import AppKit",
        "import Foundation",
        "import AppKitty",
        "import Foundation; import Dispatch",
        "let x = 1 // not an import AppKit",
    ])
    func cleanLinePasses(line: String) throws {
        #expect(try check(line: line) == 0)
    }

    /// The edits' invariant checks differ between debug and release (`assertValid`), so CI runs both.
    @Test func ciBuildsAndTestsInReleaseToo() throws {
        let workflow = try String(contentsOf: Self.repoRoot.appendingPathComponent(".github/workflows/ci.yml"), encoding: .utf8)
        #expect(workflow.contains("run: swift build -c release"))
        #expect(workflow.contains("run: swift test -c release -Xswiftc -enable-testing"))
    }

    @Test func missingDirectoryIsAnError() throws {
        #expect(try runCheck(["Sources/DoesNotExist-\(UUID().uuidString)"]) == 2)
    }
}

import Foundation
import Testing

/// TILE-10: tiling never needs Screen Recording, so only the zoom snapshot file may capture the screen (D-B), and no file
/// may use the deprecated CGWindowListCreateImage.
@Suite struct NoScreenCaptureTests {
    /// Tests/TransomMacTests/NoScreenCaptureTests.swift -> repo root.
    static let repoRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()

    static let forbidden = [
        "import ScreenCaptureKit", "SCShareableContent", "SCScreenshotManager", "CGWindowListCreateImage",
        "CGPreflightScreenCaptureAccess", "CGRequestScreenCaptureAccess",
    ]
    static let allowed = "Sources/TransomMac/Zoom/SnapshotCapture.swift"

    @Test func noSourceFileUsesScreenCapture() throws {
        let sources = Self.repoRoot.appendingPathComponent("Sources")
        let files = try #require(FileManager.default.enumerator(at: sources, includingPropertiesForKeys: nil))
            .compactMap { $0 as? URL }.filter { $0.pathExtension == "swift" }
        #expect(files.count > 10, "found only \(files.count) source files under \(sources.path)")
        for file in files {
            let text = try String(contentsOf: file, encoding: .utf8)
            let isAllowed = file.path.hasSuffix("/" + Self.allowed)
            for literal in Self.forbidden where text.contains(literal) && (!isAllowed || literal == "CGWindowListCreateImage") {
                Issue.record("\(file.path) contains \(literal)")
            }
        }
    }

    /// The allow-list names a real file, so a rename cannot silently turn the guard off.
    @Test func theAllowedCaptureFileExists() {
        #expect(FileManager.default.fileExists(atPath: Self.repoRoot.appendingPathComponent(Self.allowed).path))
    }
}

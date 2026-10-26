import Foundation
import Testing

/// TILE-10: tiling never needs Screen Recording, so no source file may capture the screen.
@Suite struct NoScreenCaptureTests {
    /// Tests/PaneMacTests/NoScreenCaptureTests.swift -> repo root.
    static let repoRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()

    static let forbidden = ["import ScreenCaptureKit", "SCShareableContent", "CGWindowListCreateImage"]

    @Test func noSourceFileUsesScreenCapture() throws {
        let sources = Self.repoRoot.appendingPathComponent("Sources")
        let files = try #require(FileManager.default.enumerator(at: sources, includingPropertiesForKeys: nil))
            .compactMap { $0 as? URL }.filter { $0.pathExtension == "swift" }
        #expect(files.count > 10, "found only \(files.count) source files under \(sources.path)")
        for file in files {
            let text = try String(contentsOf: file, encoding: .utf8)
            for literal in Self.forbidden where text.contains(literal) {
                Issue.record("\(file.path) contains \(literal)")
            }
        }
    }
}

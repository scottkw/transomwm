import Foundation
import Security
@testable import TransomMac
import Testing

/// gifsmith `real_darwin_test.go`: the real notarised release DMG passes and a byte-flipped copy fails. Needs the DMG
/// (`UPDATE_REAL_DMG=<path>`, not in git or CI) and the network (the `notarized` requirement may ask Apple), so it is
/// skipped unless the variable is set.
@Suite(.enabled(if: ProcessInfo.processInfo.environment["UPDATE_REAL_DMG"] != nil))
struct UpdateRealDMGTests {
    let dmg = URL(filePath: ProcessInfo.processInfo.environment["UPDATE_REAL_DMG"] ?? "")

    @Test func theRealReleaseDMGPassesTeamAndNotarization() {
        #expect(DMGVerifier.check(dmg) == errSecSuccess)
    }

    @Test func anotherTeamsRequirementFails() {
        let other = DMGVerifier.requirement.replacingOccurrences(of: "S2K7P43927", with: "ABCDE12345")
        #expect(other != DMGVerifier.requirement)
        #expect(DMGVerifier.check(dmg, requirement: other) != errSecSuccess)
    }

    @Test func aByteFlippedCopyFails() throws {
        // Never modify the given file: flip a byte in a copy.
        let folder = FileManager.default.temporaryDirectory.appending(path: "transom-real-dmg-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        var bytes = try Data(contentsOf: dmg)
        bytes[bytes.count / 2] ^= 0xFF
        let copy = folder.appending(path: "Transom-0.3.0.dmg")
        try bytes.write(to: copy)
        #expect(DMGVerifier.check(copy) != errSecSuccess)
    }
}

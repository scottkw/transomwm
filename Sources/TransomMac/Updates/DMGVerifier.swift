import Foundation
import Security
import TransomEngine

/// gifsmith `update.Verify` in-process (D-10): signature, Team ID and notarisation through the Security framework, no
/// subprocess (RESEARCH Pattern 4: 0 for the real DMG, -67050 wrong team, -67061 corrupted).
nonisolated enum DMGVerifier {
    static let requirement =
        "anchor apple generic and certificate leaf[subject.OU] = \"\(UpdateFeed.teamID)\" and notarized"

    /// errSecSuccess or the Security status; the caller treats any non-zero as "didn't pass".
    static func check(_ url: URL, requirement: String = DMGVerifier.requirement) -> OSStatus {
        var code: SecStaticCode?
        var status = SecStaticCodeCreateWithPath(url as CFURL, [], &code)
        guard status == errSecSuccess, let code else { return status }
        var compiled: SecRequirement?
        status = SecRequirementCreateWithString(requirement as CFString, [], &compiled)
        guard status == errSecSuccess, let compiled else { return status }
        return SecStaticCodeCheckValidity(
            code, SecCSFlags(rawValue: kSecCSStrictValidate | kSecCSCheckAllArchitectures), compiled)
    }

    /// Flags the file like a browser download (gifsmith `0081;%x;Gifsmith;`), so Gatekeeper assesses the app inside.
    static func quarantine(_ url: URL) -> Bool {
        let value = String(format: "0081;%llx;Transom;", UInt64(Date().timeIntervalSince1970))
        return url.withUnsafeFileSystemRepresentation { path in
            guard let path else { return false }
            return value.withCString { setxattr(path, "com.apple.quarantine", $0, strlen($0), 0, 0) } == 0
        }
    }
}

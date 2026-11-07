import Combine
import TransomEngine
import os

/// Owns the update status (SHIP-04, D-09), ported from gifsmith `UpdateService.Check`. One check at a time; a failed
/// check restores the previous status (`UpdateMachine`).
@MainActor final class UpdateController: ObservableObject {
    @Published private(set) var machine = UpdateMachine()
    var status: UpdateStatus { machine.status }
    var error: UpdateError? { machine.error }
    let currentVersion: String
    let build: String
    /// False outside a Release bundle: the tab shows the version line and a disabled Check for Updates.
    let isEnabled: Bool
    private let client: GitHubReleaseClient
    private let logger = Logger(subsystem: "com.eightabyte.transom", category: "update")

    init(client: GitHubReleaseClient, currentVersion: String, build: String, isEnabled: Bool) {
        self.client = client
        self.currentVersion = currentVersion
        self.build = build
        self.isEnabled = isEnabled
    }

    /// On only in a Release bundle with a version (Debug is `….debug`; `swift run` has no Info.plist), so a dev build
    /// never updates itself (T-09-19). A Release bundle with a malformed version is a broken build: crash.
    static func isEnabled(bundleID: String?, version: String?) -> Bool {
        guard bundleID == "com.eightabyte.transom", let version else { return false }
        precondition(UpdateVersion.parse(version) != nil, "Release bundle with a malformed version: \(version)")
        return true
    }

    /// `manual` is a Check for Updates click: only its failure is shown. An automatic check's failure is only logged.
    func checkNow(manual: Bool = true) async {
        guard isEnabled, machine.begin(.check) else { return }
        let check: UpdateCheck
        do {
            check = try await client.latest()
        } catch let error as GitHubReleaseClient.HTTPStatusError {
            logger.error("check failed: \(error.code, privacy: .public)")
            machine.fail(.checkFailed, manual: manual)
            return
        } catch {
            logger.error("check failed: \(error.localizedDescription)")
            machine.fail(.checkFailed, manual: manual)
            return
        }
        switch check {
        case .release(let release) where UpdateVersion.compare(release.version, currentVersion) == 1:
            logger.info("check: \(release.version, privacy: .public) available")
            machine.succeed(.available(release))
            return
        case .release:
            break
        case .notInstallable(let version):
            // gifsmith: a release without a valid DMG reads as current.
            logger.error("check: release \(version, privacy: .public) not installable")
        case .none:
            logger.info("check: no published release")
        }
        logger.info("check: up to date \(self.currentVersion, privacy: .public)")
        machine.succeed(.current(currentVersion))
    }
}

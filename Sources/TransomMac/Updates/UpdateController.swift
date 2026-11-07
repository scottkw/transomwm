import Combine
import TransomEngine
import os

/// Owns the update status (SHIP-04, D-09), ported from gifsmith `UpdateService.Check`. One check at a time; a failed
/// check restores the previous status.
@MainActor final class UpdateController: ObservableObject {
    @Published private(set) var status: UpdateStatus = .idle
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

    func checkNow() async {
        guard isEnabled, status != .checking else { return }
        let previous = status
        status = .checking
        let check: UpdateCheck
        do {
            check = try await client.latest()
        } catch let error as GitHubReleaseClient.HTTPStatusError {
            logger.error("check failed: \(error.code, privacy: .public)")
            status = previous
            return
        } catch {
            logger.error("check failed: \(error.localizedDescription)")
            status = previous
            return
        }
        switch check {
        case .release(let release) where UpdateVersion.compare(release.version, currentVersion) == 1:
            logger.info("check: \(release.version, privacy: .public) available")
            status = .available(release)
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
        status = .current(currentVersion)
    }
}

import AppKit
import Combine
import Foundation
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
    private let defaults: UserDefaults
    private let downloader: DMGDownloader
    /// `DMGVerifier.check`; runs off the main actor (the notarisation check may ask Apple).
    private let verify: @Sendable (URL) -> OSStatus
    /// `NSWorkspace.open`; tests record instead of opening.
    private let open: (URL) -> Bool
    /// Read once per launch: an available update shows the brew command instead of Download and Open (D-10).
    let installedWithHomebrew: Bool
    /// On by default; read by the daily schedule (`startAutomatic`).
    static let automaticKey = "updates.automatic"
    /// When the last check finished, successful or not (the Debug "Updates" line).
    private(set) var lastChecked: Date?
    /// The running schedule; nil while automatic is off or before `startAutomatic`.
    private(set) var automaticTask: Task<Void, Never>?
    /// Kept so the Settings toggle can restart the schedule; set by `startAutomatic`.
    private var sleep: ((Duration) async throws -> Void)?
    private let logger = Logger(subsystem: "com.eightabyte.transom", category: "update")

    init(
        client: GitHubReleaseClient, currentVersion: String, build: String, isEnabled: Bool, defaults: UserDefaults,
        downloader: DMGDownloader = DMGDownloader(
            configuration: GitHubReleaseClient.configuration(), directory: DMGDownloader.productionDirectory),
        verify: @escaping @Sendable (URL) -> OSStatus = { DMGVerifier.check($0) },
        open: @escaping (URL) -> Bool = { NSWorkspace.shared.open($0) },
        fileExists: (String) -> Bool = { FileManager.default.fileExists(atPath: $0) }
    ) {
        self.client = client
        self.defaults = defaults
        self.downloader = downloader
        self.verify = verify
        self.open = open
        installedWithHomebrew = InstallLocation.isHomebrew(exists: fileExists)
        self.currentVersion = currentVersion
        self.build = build
        self.isEnabled = isEnabled
    }

    /// The Settings ▸ Updates toggle.
    var automatic: Bool {
        get { defaults.object(forKey: Self.automaticKey) as? Bool ?? true }
        set {
            objectWillChange.send()
            defaults.set(newValue, forKey: Self.automaticKey)
            restartAutomatic()
        }
    }

    /// gifsmith `RunAutoUpdates`: about 10 s after launch, then every 24 hours, while automatic is on (D-09). A failure
    /// shows nothing (`checkNow(manual: false)`). Called once at launch; `sleep` is injected by tests.
    func startAutomatic(sleep: @escaping (Duration) async throws -> Void = { try await Task.sleep(for: $0) }) {
        self.sleep = sleep
        restartAutomatic()
    }

    private func restartAutomatic() {
        automaticTask?.cancel()
        automaticTask = nil
        guard automatic, isEnabled, let sleep else { return }
        automaticTask = Task { [weak self] in
            var wait = Duration.seconds(10)
            while true {
                do { try await sleep(wait) } catch { return }
                guard !Task.isCancelled, let self else { return }
                await self.checkNow(manual: false)
                wait = .seconds(24 * 60 * 60)
            }
        }
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
        guard isEnabled else { return }
        // The daily check would turn "Quit Transom" back into "Download and Open" after the DMG was opened.
        if !manual, case .opened = machine.status { return }
        guard machine.begin(.check) else { return }
        defer { lastChecked = Date() }
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

    /// Download and Open (D-10), gifsmith `UpdateService.Download`: download with size and digest, then signature, Team
    /// ID and notarisation, then quarantine, then open. Only a fully verified file reaches `open`.
    func downloadAndOpen() async {
        guard machine.begin(.download), case .downloading(let release, _) = machine.status else { return }
        let file: URL
        do {
            file = try await downloader.download(release) { [weak self] fraction in
                // A late progress tick must not undo verifying.
                guard let self, case .downloading = self.machine.status else { return }
                self.machine.succeed(.downloading(release, fraction: fraction))
            }
        } catch DMGDownloader.Failure.digest {
            logger.error("verify failed: digest")
            machine.fail(.verifyFailed, manual: true)
            return
        } catch {
            logger.error("download failed: \(error.localizedDescription)")
            machine.fail(.downloadFailed(version: release.version), manual: true)
            return
        }
        logger.info("download \(release.version, privacy: .public) done")
        machine.succeed(.verifying(release))
        let check = verify
        let status = await Task.detached { check(file) }.value
        let quarantined = status == errSecSuccess && DMGVerifier.quarantine(file)
        guard quarantined else {
            // gifsmith: a failed check deletes the file.
            if status == errSecSuccess {
                logger.error("verify failed: quarantine")
            } else {
                logger.error("verify failed: team id (\(status, privacy: .public))")
            }
            try? FileManager.default.removeItem(at: file)
            machine.fail(.verifyFailed, manual: true)
            return
        }
        guard open(file) else {
            // gifsmith: the verified file stays for a retry.
            logger.error("open failed")
            machine.fail(.openFailed, manual: true)
            return
        }
        logger.info("opened \(release.assetName, privacy: .public)")
        machine.succeed(.opened(release))
    }
}

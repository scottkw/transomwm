import CryptoKit
import Foundation
import TransomEngine

/// gifsmith `update.Download`: fetches a release's DMG into an app-owned folder through a `.part` file. Every redirect
/// must be on the download allow-list (at most 5), and the byte count and SHA-256 must equal the release's.
final class DMGDownloader {
    /// `download` maps to "Couldn't download"; `digest` (size or SHA-256) to the signature-check failure.
    enum Failure: Error { case download, digest }

    static let productionDirectory = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        .appending(path: "com.eightabyte.transom/Updates", directoryHint: .isDirectory)

    private let configuration: URLSessionConfiguration
    let directory: URL

    init(configuration: URLSessionConfiguration, directory: URL) {
        self.configuration = configuration
        self.directory = directory
    }

    /// The verified-size, matching-digest file at `directory/assetName`. `progress` runs at most every 100 ms.
    func download(_ release: UpdateRelease, progress: @escaping @MainActor (Double?) -> Void) async throws -> URL {
        guard UpdateFeed.isAllowedDownload(release.url) else { throw Failure.download }
        let files = FileManager.default
        try files.createDirectory(at: directory, withIntermediateDirectories: true)
        try files.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
        let final = directory.appending(path: release.assetName)
        let part = directory.appending(path: release.assetName + ".part")
        var request = URLRequest(url: release.url)
        request.setValue("Transom", forHTTPHeaderField: "User-Agent")
        try await withCheckedThrowingContinuation { (done: CheckedContinuation<Void, any Error>) in
            let delegate = Delegate(release: release, part: part, progress: progress, done: done)
            let session = URLSession(configuration: configuration, delegate: delegate, delegateQueue: nil)
            session.downloadTask(with: request).resume()
            session.finishTasksAndInvalidate()
        }
        try files.moveItem(at: part, to: final)
        return final
    }

    func clean() throws {}

    nonisolated static func sha256Hex(of file: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: file)
        defer { try? handle.close() }
        var hasher = SHA256()
        while let chunk = try handle.read(upToCount: 1 << 20), !chunk.isEmpty { hasher.update(data: chunk) }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    /// Runs on the session's own queue; touched by one callback at a time.
    private nonisolated final class Delegate: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
        let release: UpdateRelease
        let part: URL
        let progress: @MainActor (Double?) -> Void
        let done: CheckedContinuation<Void, any Error>
        var redirects = 0
        var lastProgress = Date.distantPast
        var outcome: Result<Void, any Error> = .failure(Failure.download)

        init(release: UpdateRelease, part: URL, progress: @escaping @MainActor (Double?) -> Void,
             done: CheckedContinuation<Void, any Error>) {
            self.release = release
            self.part = part
            self.progress = progress
            self.done = done
        }

        func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                        newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
            redirects += 1
            guard redirects <= 5, let url = request.url, UpdateFeed.isAllowedDownload(url) else {
                task.cancel()
                completionHandler(nil)
                return
            }
            completionHandler(request)
        }

        func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64,
                        totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
            let now = Date()
            guard now.timeIntervalSince(lastProgress) >= 0.1 else { return }
            lastProgress = now
            let fraction = min(Double(totalBytesWritten) / Double(release.size), 1)
            let report = progress
            Task { @MainActor in report(fraction) }
        }

        func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
            guard (downloadTask.response as? HTTPURLResponse)?.statusCode == 200 else { return }
            do {
                // Exclusive: moveItem refuses an existing .part.
                try FileManager.default.moveItem(at: location, to: part)
                try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: part.path)
                let size = (try FileManager.default.attributesOfItem(atPath: part.path)[.size] as? NSNumber)?.int64Value
                guard size == release.size, try DMGDownloader.sha256Hex(of: part) == release.sha256 else {
                    outcome = .failure(Failure.digest)
                    return
                }
                outcome = .success(())
            } catch {
                outcome = .failure(error)
            }
        }

        func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: (any Error)?) {
            done.resume(with: error.map { _ in .failure(Failure.download) } ?? outcome)
        }
    }
}

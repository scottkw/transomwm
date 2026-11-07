/// What Settings ▸ Updates shows (gifsmith `UpdateStatus` states).
public enum UpdateStatus: Equatable, Sendable {
    case idle
    case checking
    /// Up to date; the running version.
    case current(String)
    case available(UpdateRelease)
    /// `fraction` is nil while the size is unknown.
    case downloading(UpdateRelease, fraction: Double?)
    case verifying(UpdateRelease)
    case opened(UpdateRelease)
}

/// A failed manual action, shown in place of the status line (09 UI-SPEC Surface 3 Errors).
public enum UpdateError: Equatable, Sendable {
    case checkFailed
    case downloadFailed(version: String)
    /// Size, digest, signature, Team ID or notarisation: the file was deleted.
    case verifyFailed
    case openFailed
}

/// gifsmith `UpdateService`'s rules as pure transitions: one operation at a time, and a failure puts back the status
/// from before it started.
public struct UpdateMachine: Equatable, Sendable {
    public enum Operation: Equatable, Sendable {
        case check
        /// Download and Open: only from available or opened.
        case download
    }

    public private(set) var status: UpdateStatus = .idle
    /// Set only by a failed manual operation; cleared when the next one starts.
    public private(set) var error: UpdateError?
    private var previous: UpdateStatus = .idle

    public init() {}

    /// gifsmith `busy`: an operation is running.
    public var isBusy: Bool {
        switch status {
        case .checking, .downloading, .verifying: true
        case .idle, .current, .available, .opened: false
        }
    }

    /// Starts `op`, or returns false and changes nothing while another one runs or a download has nothing to fetch.
    public mutating func begin(_ op: Operation) -> Bool {
        guard !isBusy else { return false }
        switch op {
        case .check:
            previous = status
            status = .checking
        case .download:
            let release: UpdateRelease
            switch status {
            case .available(let offered), .opened(let offered): release = offered
            default: return false
            }
            // gifsmith `Download`: any failure goes back to available, also when it started from opened.
            previous = .available(release)
            status = .downloading(release, fraction: nil)
        }
        error = nil
        return true
    }

    /// The operation's result, or its next step (download progress, verifying).
    public mutating func succeed(_ status: UpdateStatus) {
        self.status = status
        error = nil
    }

    /// Restores the status from before the operation; only a manual failure is shown.
    public mutating func fail(_ error: UpdateError, manual: Bool) {
        status = previous
        self.error = manual ? error : nil
    }
}

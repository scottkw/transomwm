/// What Settings ▸ Updates shows (gifsmith `UpdateStatus` states; 09-13 adds the rest).
public enum UpdateStatus: Equatable, Sendable {
    case idle
    case checking
    /// Up to date; the running version.
    case current(String)
    case available(UpdateRelease)
}

/// A failed manual action, shown in place of the status line (09 UI-SPEC Surface 3 Errors). 09-13 adds download,
/// verify and open.
public enum UpdateError: Equatable, Sendable {
    case checkFailed
}

/// gifsmith `UpdateService`'s rules as pure transitions: one operation at a time, and a failure puts back the status
/// from before it started.
public struct UpdateMachine: Equatable, Sendable {
    public enum Operation: Equatable, Sendable {
        case check
    }

    public private(set) var status: UpdateStatus = .idle
    /// Set only by a failed manual operation; cleared when the next one starts.
    public private(set) var error: UpdateError?
    private var previous: UpdateStatus = .idle

    public init() {}

    /// gifsmith `busy`: an operation is running. 09-13 adds downloading and verifying.
    public var isBusy: Bool { status == .checking }

    /// Starts `op`, or returns false and changes nothing while another one runs.
    public mutating func begin(_ op: Operation) -> Bool {
        guard !isBusy else { return false }
        previous = status
        error = nil
        switch op {
        case .check: status = .checking
        }
        return true
    }

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

/// When to refresh (D-09): every hint becomes a cancel-latest debounced refresh, so a notification storm
/// costs one refresh per quiet period (T-02-16). A periodic sweep catches anything a hint missed.
@MainActor final class RefreshScheduler {
    private let refresh: (Int32) async -> Void
    private let refreshAll: () async -> Void
    private var pending: [Int32: Task<Void, Never>] = [:]
    private var pendingAll: Task<Void, Never>?
    private var sweep: Task<Void, Never>?

    init(refresh: @escaping (Int32) async -> Void, refreshAll: @escaping () async -> Void) {
        self.refresh = refresh
        self.refreshAll = refreshAll
    }

    isolated deinit {
        for task in pending.values { task.cancel() }
        pendingAll?.cancel()
        sweep?.cancel()
    }

    /// Refreshes `pid` after `delay` of quiet; a newer call for the same pid replaces this one.
    /// A refresh already running is not cancelled, so its result is never lost.
    func schedule(pid: Int32, after delay: Duration = .milliseconds(75)) {
        pending[pid]?.cancel()
        pending[pid] = Task { [weak self, refresh] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled else { return }
            self?.pending[pid] = nil
            await refresh(pid)
        }
    }

    /// Refreshes every app after `delay` of quiet (display changes); a newer call replaces this one.
    func scheduleAll(after delay: Duration) {
        pendingAll?.cancel()
        pendingAll = Task { [weak self, refreshAll] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled else { return }
            self?.pendingAll = nil
            await refreshAll()
        }
    }

    /// Runs `refreshAll` every `interval` until the scheduler goes away.
    func startSweep(every interval: Duration = .seconds(5)) {
        sweep?.cancel()
        sweep = Task { [refreshAll] in
            while !Task.isCancelled {
                try? await Task.sleep(for: interval)
                guard !Task.isCancelled else { return }
                await refreshAll()
            }
        }
    }

    /// Drops every pending refresh and stops the sweep (the session paused); `startSweep()` restarts it.
    func stop() {
        for task in pending.values { task.cancel() }
        pending = [:]
        pendingAll?.cancel()
        pendingAll = nil
        sweep?.cancel()
        sweep = nil
    }

    /// Drops the pending refresh for `pid` (the app quit).
    func cancel(pid: Int32) {
        pending.removeValue(forKey: pid)?.cancel()
    }
}

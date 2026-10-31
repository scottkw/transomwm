import CoreGraphics
import Dispatch
import os

/// When a display change is acted on (D-11). The first CG reconfiguration callback (`begin()`) or screen-parameters
/// change (`touch()`) starts settling at once; each further one restarts the quiet period, so settled fires once,
/// `quiet` after the last change. A quiet period that ends while the session is asleep or locked waits; the next
/// `sessionResumed()` restarts the full quiet period (T-06-13).
@MainActor final class DisplaySettler {
    enum State: Equatable { case idle, settling, waitingForWake }

    private(set) var state = State.idle
    private let quiet: Duration
    private let sleep: (Duration) async throws -> Void
    private let isPaused: () -> Bool
    private let onSettling: () -> Void
    private let onSettled: () -> Void
    private var quietTask: Task<Void, Never>?
    private var observing = false
    private let logger = Logger(subsystem: "com.eightabyte.transom", category: "displays")

    init(
        quiet: Duration = .seconds(1.5), sleep: @escaping (Duration) async throws -> Void = { try await Task.sleep(for: $0) },
        isPaused: @escaping () -> Bool, onSettling: @escaping () -> Void, onSettled: @escaping () -> Void
    ) {
        self.quiet = quiet
        self.sleep = sleep
        self.isPaused = isPaused
        self.onSettling = onSettling
        self.onSettled = onSettled
    }

    isolated deinit {
        quietTask?.cancel()
        if observing { CGDisplayRemoveReconfigurationCallback(Self.callback, Unmanaged.passUnretained(self).toOpaque()) }
    }

    /// Starts the CG reconfiguration callback, which fires before the screen-parameters notification. Not in tests.
    func observeReconfiguration() {
        guard !observing else { return }
        observing = CGDisplayRegisterReconfigurationCallback(Self.callback, Unmanaged.passUnretained(self).toOpaque()) == .success
        if !observing { logger.error("could not register the display reconfiguration callback; screen-parameter changes still settle") }
    }

    /// The CG callback saw a reconfiguration begin.
    func begin() { changeSeen() }

    /// A screen-parameters change.
    func touch() { changeSeen() }

    /// The session woke or unlocked: a change still pending settles after a full quiet period.
    func sessionResumed() {
        guard state != .idle else { return }
        state = .settling
        restartQuiet()
    }

    private func changeSeen() {
        let wasIdle = state == .idle
        state = .settling
        restartQuiet()
        guard wasIdle else { return }
        logger.info("display change seen; debouncing")
        onSettling()
    }

    private func restartQuiet() {
        quietTask?.cancel()
        quietTask = Task { [weak self, sleep, quiet] in
            do { try await sleep(quiet) } catch { return }
            guard !Task.isCancelled, let self else { return }
            self.quietEnded()
        }
    }

    private func quietEnded() {
        quietTask = nil
        guard !isPaused() else {
            state = .waitingForWake
            logger.info("deferred: session asleep or locked")
            return
        }
        state = .idle
        onSettled()
    }

    /// The callback thread is undocumented, so the hop to main is unconditional (T-06-14). The refcon is unretained:
    /// the settler lives as long as the window system, and its deinit removes the callback.
    private nonisolated static let callback: CGDisplayReconfigurationCallBack = { _, flags, refcon in
        guard flags.contains(.beginConfigurationFlag), let refcon else { return }
        let address = UInt(bitPattern: refcon)
        DispatchQueue.main.async {
            MainActor.assumeIsolated {
                guard let pointer = UnsafeRawPointer(bitPattern: address) else { return }
                Unmanaged<DisplaySettler>.fromOpaque(pointer).takeUnretainedValue().begin()
            }
        }
    }
}

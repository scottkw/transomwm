import AppKit
import PaneEngine
import PaneModel
import os

/// The thin MainActor shell around `Arranger` (RESEARCH Pattern 1). It is the only reader of `system.events`
/// (Pitfall 2), fans each re-read inventory out through `onInventory`, and runs the Arranger's effects in order.
/// Every window command goes through `system.perform`, where `ExclusionFilter.admit` guards it (02-13).
@MainActor public final class ArrangeController {
    private let system: AXWindowSystem
    private let logger = Logger(subsystem: "com.eightabyte.pane", category: "arrange")
    private var started = false
    /// Each re-read inventory: the menu header and the Tracked Windows feed.
    public var onInventory: ((WindowInventory) -> Void)?
    public private(set) var arranger = Arranger()
    private var notices = NoticeQueue<Notice>()
    private lazy var toast = ToastPresenter()
    private let noticeExpiry = WakeTimer()

    public init(system: AXWindowSystem) {
        self.system = system
    }

    /// Feeds the current inventory, then starts the single events loop. Later calls only re-read the inventory.
    public func start() async {
        let inventory = await system.inventory()
        guard !started else {
            onInventory?(inventory)
            return
        }
        started = true
        await run(arranger.handle(.inventory(inventory), now: .now))
        onInventory?(inventory)
        Task { [weak self, system] in
            for await event in system.events {
                guard let self else { return }
                await self.run(self.arranger.handle(.event(event), now: .now))
                // inventory() serves the cache immediately, so re-reading it after each event is cheap.
                let inventory = await system.inventory()
                // New displays reach the Arranger as an inventory, which re-plans every shown desk (TILE-03).
                if case .displaysChanged = event { await self.run(self.arranger.handle(.inventory(inventory), now: .now)) }
                self.onInventory?(inventory)
            }
        }
    }

    /// Runs `command` on the frontmost app's focused tracked window.
    public func dispatch(_ command: Command) async {
        let pid = NSWorkspace.shared.frontmostApplication?.processIdentifier
        await dispatch(command, focused: pid.flatMap { system.focusedWindow(of: $0) }?.window)
    }

    public func dispatch(_ command: Command, focused: PaneModel.WindowRef?) async {
        await run(arranger.handle(.command(command, focused: focused), now: .now))
    }

    private func run(_ effects: [ArrangerEffect]) async {
        for effect in effects {
            switch effect {
            case .perform(let commands):
                await system.perform(commands)
            case .requery(let revived):
                let states = await LifecycleSync.requery(revived, using: system)
                await run(arranger.handle(.requeried(revived, states), now: .now))
            case .beep:
                NSSound.beep()
            case .announce(let text):
                postAnnouncement(text)
            case .fault(let message):
                logger.error("\(message, privacy: .public)")
            case .info(let message):
                logger.info("\(message, privacy: .public)")
            case .notice(let notice):
                present(notices.post(notice, at: .now))
            }
        }
    }

    /// Shows or hides the toast as the queue says, and schedules the visible notice's expiry.
    private func present(_ change: NoticeQueue<Notice>.Change) {
        switch change {
        case .show(let notice):
            toast.show(NoticeCopy.text(for: notice, appName: Self.appName), glyph: NoticeCopy.glyph(for: notice), on: displayUUID(of: notice))
            if let at = notices.expiresAt {
                noticeExpiry.set(at) { [weak self] in
                    guard let self else { return }
                    self.present(self.notices.expire(at: .now))
                }
            }
        case .hide:
            toast.hide()
        case .unchanged:
            break
        }
    }

    /// The display the toast belongs on: the first named window's.
    private func displayUUID(of notice: Notice) -> String? {
        switch notice {
        case .lostRoom(let windows): windows.first.flatMap { arranger.windows[$0.identity]?.displayUUID }
        }
    }

    private static func appName(_ window: PaneModel.WindowRef) -> String {
        NSRunningApplication(processIdentifier: window.pid)?.localizedName ?? window.bundleID
    }
}

/// One pending wake-up: `set` replaces any earlier one, so only the latest instant fires.
@MainActor final class WakeTimer {
    private var task: Task<Void, Never>?

    func set(_ instant: ContinuousClock.Instant, _ fire: @escaping @MainActor () async -> Void) {
        task?.cancel()
        task = Task {
            try? await Task.sleep(until: instant, clock: .continuous)
            guard !Task.isCancelled else { return }
            await fire()
        }
    }
}

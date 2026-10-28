import AppKit
import TransomEngine
import TransomModel
import os

/// The shell side of a camera move (D-A, UI-SPEC Surface 1): capture, show the stage over the real windows, animate,
/// hand the settle back to the engine, wait for that settle's read-backs, then reveal. Real windows never animate.
/// Created only with zoom on, so with zoom off no stage exists and ScreenCaptureKit is never touched (D-D).
@MainActor final class ZoomController {
    /// The preference that decides whether zoom exists at all (default on); 04-05's menu toggle writes it.
    static let enabledKey = "zoomEnabled"
    static let explainerShownKey = "zoomPreviewExplainerShown"
    /// ZOOM-07: the write path (first write to last read-back) of a settle.
    static let settleBudget: Duration = .milliseconds(500)

    enum Phase: String { case capturing, moving, settling, revealing }

    /// One display's move in flight, from capture to the end of the reveal fade.
    private struct Active {
        var move: CameraMove
        var settle: (UInt64) -> Void
        var phase: Phase
        var tracker: SettleTracker?
        var waiting: Set<WindowIdentity> = []
        var settleStarted: ContinuousClock.Instant?
        var lastReturn: ContinuousClock.Instant?
        /// Windows written, then of the commands: frame writes, parks, and frame writes that un-park an entering window.
        var writes = 0
        var counts = (frames: 0, parked: 0, unparked: 0)
        /// A move asked for during the 120 ms reveal fade starts when the fade ends.
        var queued: (move: CameraMove, settle: (UInt64) -> Void)?
    }

    private let logger = Logger(subsystem: "com.eightabyte.transom", category: "camera")
    /// Fires when a reveal fade ends (04-05's Turn Off Zoom and 04-06's pick mode wait for it).
    var onRevealed: ((_ displayUUID: String, _ move: CameraMove) -> Void)?
    /// Re-orders a visible toast and drop preview above a stage that just ordered in (UI-SPEC Surface 1 level row).
    var bringNoticesFront: () -> Void = {}
    /// The Arranger's info for a window: the CG window of its visible tab, its frame.
    var windowInfo: (WindowIdentity) -> WindowInfo? = { _ in nil }
    private(set) var lastSettle: (ms: Int, windows: Int)?
    var isIdle: Bool { active.isEmpty }

    private var stages: [String: StagePanel] = [:]
    private var active: [String: Active] = [:]
    private var revealTimers: [String: WakeTimer] = [:]
    private let capture = SnapshotCapture()

    /// Runs one `.cameraMove`; `settle(moveID)` is called when its animation ends. A move on a display that already has
    /// one in flight retargets it from where the tiles are (no queue, no jump).
    func run(_ move: CameraMove, settle: @escaping (UInt64) -> Void) {
        let uuid = move.displayUUID
        if var current = active[uuid] {
            guard current.phase != .revealing else {
                current.queued = (move, settle)
                active[uuid] = current
                return
            }
            logger.info("retarget \(String(describing: current.move.to), privacy: .public) → \(String(describing: move.to), privacy: .public) during \(current.phase.rawValue, privacy: .public)")
            let phase = current.phase
            current.move = move
            current.settle = settle
            current.tracker = nil
            current.waiting = []
            revealTimers[uuid]?.cancel()
            // While capturing, the capture's completion shows whichever move is latest.
            if phase != .capturing {
                current.phase = .moving
                stages[uuid]?.retarget(to: tiles(for: move, images: [:])) { [weak self] in self?.animationEnded(uuid, move.id) }
            }
            active[uuid] = current
            return
        }
        guard stage(for: uuid) != nil else {
            logger.fault("no screen for display \(uuid, privacy: .public); settling without a stage")
            settle(move.id)
            return
        }
        active[uuid] = Active(move: move, settle: settle, phase: .capturing)
        Task { [weak self] in
            guard let self else { return }
            let images = await self.captureStart(move)
            guard let current = self.active[uuid], current.phase == .capturing else { return }
            self.show(current.move, images: images)
        }
    }

    /// The settle's writes are about to go out: the reveal waits for each one's read-back + 50 ms, or the 1500 ms cap.
    func beginSettle(displayUUID uuid: String, moveID: UInt64, writes: [WindowCommand]) {
        guard var current = active[uuid], current.move.id == moveID, current.phase == .moving else { return }
        let ids = Set(writes.compactMap(Self.written))
        let now = ContinuousClock.now
        current.phase = .settling
        current.tracker = SettleTracker(pending: ids, started: now)
        current.waiting = ids
        current.settleStarted = now
        current.lastReturn = nil
        current.writes = ids.count
        let parked = writes.filter { if case .park = $0 { true } else { false } }.count
        let entering = Set(current.move.tiles.filter { $0.kind == .entering }.map(\.window.identity))
        let unparked = writes.filter { if case .setFrame(let w, _) = $0 { entering.contains(w.identity) } else { false } }.count
        current.counts = (ids.count - parked, parked, unparked)
        active[uuid] = current
        armReveal(uuid)
    }

    /// A read-back came in (`frameApplied`).
    func frameApplied(_ id: WindowIdentity) {
        let now = ContinuousClock.now
        for (uuid, var current) in active where current.tracker != nil {
            guard current.waiting.remove(id) != nil else { continue }
            current.tracker?.applied(id, at: now)
            current.lastReturn = now
            active[uuid] = current
            armReveal(uuid)
        }
    }

    /// Displays changed: stages for displays that are gone (or idle, since a display may have changed size) are dropped
    /// and made again on the next move.
    func displaysChanged() {
        let present = Set(Displays.current().map(\.uuid))
        for (uuid, stage) in stages where active[uuid] == nil || !present.contains(uuid) {
            stage.orderOut(nil)
            stages[uuid] = nil
            active[uuid] = nil
            revealTimers[uuid]?.cancel()
        }
    }

    // MARK: Move steps

    private func stage(for uuid: String) -> StagePanel? {
        if let stage = stages[uuid] { return stage }
        guard let nsScreen = Displays.screen(uuid: uuid) else { return nil }
        let panel = StagePanel(screen: nsScreen)
        stages[uuid] = panel
        return panel
    }

    /// UI-SPEC step 3: the windows on screen at the start, at the larger of their start and end size (capped at their
    /// own size) in pixels, within 120 ms, four at a time. Skipped without Screen Recording.
    private func captureStart(_ move: CameraMove) async -> [UInt32: CGImage] {
        guard SnapshotCapture.isGranted() else { return [:] }
        let scale = Displays.screen(uuid: move.displayUUID)?.backingScaleFactor ?? 2
        let requests = move.tiles.compactMap { tile -> (CGWindowID, CGSize)? in
            guard tile.kind != .entering, let id = cgWindow(tile.window) else { return nil }
            let native = windowInfo(tile.window.identity)?.frame.size ?? tile.start.size
            let width = min(max(tile.start.width, tile.end.width), native.width)
            let height = min(max(tile.start.height, tile.end.height), native.height)
            return (id, CGSize(width: width * scale, height: height * scale))
        }
        return await capture.captureAll(requests, deadline: SnapshotCapture.moveBudget)
    }

    /// UI-SPEC steps 4 and 5: the stage orders in instantly with every tile over its window, then the 250 ms move.
    private func show(_ move: CameraMove, images: [UInt32: CGImage]) {
        let uuid = move.displayUUID
        guard let stage = stage(for: uuid) else { return }
        let tiles = tiles(for: move, images: images)
        stage.show(tiles: tiles)
        bringNoticesFront()
        active[uuid]?.phase = .moving
        let snapshots = tiles.filter { if case .snapshot = $0.content { true } else { false } }.count
        logger.info("move display \(uuid, privacy: .public): \(String(describing: move.from), privacy: .public) → \(String(describing: move.to), privacy: .public), \(tiles.count, privacy: .public) tiles, \(snapshots, privacy: .public) snapshots, \(tiles.count - snapshots, privacy: .public) fallback")
        stage.animate { [weak self] in
            self?.animationEnded(uuid, move.id)
        }
    }

    /// A stale completion (the move was retargeted) does nothing; the latest move's own completion settles it.
    private func animationEnded(_ uuid: String, _ moveID: UInt64) {
        guard let current = active[uuid], current.move.id == moveID, current.phase == .moving else { return }
        current.settle(moveID)
    }

    private func armReveal(_ uuid: String) {
        guard let at = active[uuid]?.tracker?.revealAt() else { return }
        revealTimers[uuid, default: WakeTimer()].set(at) { [weak self] in self?.reveal(uuid) }
    }

    /// UI-SPEC step 7: every write back + 50 ms, or the cap; the stage fades out over 120 ms.
    private func reveal(_ uuid: String) {
        guard var current = active[uuid], current.phase == .settling, let started = current.settleStarted else { return }
        let capped = !current.waiting.isEmpty
        let elapsed = capped ? SettleTracker.cap : (current.lastReturn ?? started) - started
        let ms = Int(elapsed / .milliseconds(1))
        let counts = current.counts
        // shortcut: collapsed is 0 until 04-07 feeds the collapsible set; then count this settle's collapsed blocks.
        logger.info("settle \(ms, privacy: .public) ms: \(counts.frames, privacy: .public) writes, \(counts.parked, privacy: .public) parked, \(counts.unparked, privacy: .public) unparked, 0 collapsed")
        if capped, let slowest = current.waiting.first {
            logger.notice("settle cap 1500 ms reached; slowest \(slowest.bundleID, privacy: .public) \(ms, privacy: .public) ms")
        }
        if elapsed > Self.settleBudget {
            logger.notice("settle over budget: \(ms, privacy: .public) ms for \(current.writes, privacy: .public) windows")
        }
        lastSettle = (ms, current.writes)
        current.phase = .revealing
        active[uuid] = current
        let move = current.move
        guard let stage = stages[uuid] else { return finishReveal(uuid, move) }
        stage.fadeOut { [weak self] in self?.finishReveal(uuid, move) }
    }

    private func finishReveal(_ uuid: String, _ move: CameraMove) {
        let queued = active[uuid]?.queued
        active[uuid] = nil
        onRevealed?(uuid, move)
        if let queued { run(queued.move, settle: queued.settle) }
    }

    // MARK: Tiles

    /// One tile per window visible at the start or end, in AppKit coordinates. Each picks its content on its own: this
    /// move's capture, else the cached snapshot, else the app-colour fallback (UI-SPEC partial state).
    private func tiles(for move: CameraMove, images: [UInt32: CGImage]) -> [StageTile] {
        guard let primaryHeight = NSScreen.screens.first.map({ Double($0.frame.height) }) else { return [] }
        func appKit(_ rect: Rect) -> CGRect {
            let r = Coordinates.appKit(fromTopLeft: rect, primaryHeight: primaryHeight)
            return CGRect(x: r.x, y: r.y, width: r.width, height: r.height)
        }
        return move.tiles.map { tile in
            let cg = cgWindow(tile.window)
            let image = cg.flatMap { images[$0] ?? capture.cached($0) }
            return StageTile(
                id: cg ?? tile.window.windowID, start: appKit(tile.start), end: appKit(tile.end),
                content: image.map { .snapshot($0) } ?? fallback(tile.window))
        }
    }

    /// App colour, app icon, and the AX title (the app name when it has none).
    private func fallback(_ window: TransomModel.WindowRef) -> TileLayer.Content {
        let app = NSRunningApplication(processIdentifier: window.pid)
        let name = app?.localizedName ?? window.bundleID
        return .fallback(
            color: AppColor.color(forBundleID: window.bundleID, icon: app?.icon), icon: app?.icon,
            title: window.titleHint.isEmpty ? name : window.titleHint)
    }

    /// A window closed: its snapshot leaves the cache (T-04-13).
    func windowClosed(_ window: TransomModel.WindowRef) {
        capture.remove(window.windowID)
    }

    /// The CG window a window shows (its visible tab); nil for a synthetic ID, which has none.
    private func cgWindow(_ window: TransomModel.WindowRef) -> CGWindowID? {
        let id = windowInfo(window.identity)?.visibleMemberID ?? window.windowID
        return id < WindowIdentity.syntheticIDBase ? id : nil
    }

    private static func written(_ command: WindowCommand) -> WindowIdentity? {
        switch command {
        case .setFrame(let window, _), .park(let window, _): window.identity
        case .focus, .raise, .setHidden: nil
        }
    }
}

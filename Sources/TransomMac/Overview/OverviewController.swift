import AppKit
import KeyboardShortcuts
import TransomEngine
import TransomModel
import os

/// The overview (OVER-01, D-01, D-02, 06 UI-SPEC Surface 1): one stage panel per display not showing a full-screen
/// Space, each with that display's current-Space windows moved from their real frames into the main area. Real windows
/// never move: everything is drawn on the stage. Made by ArrangeController with zoom on; every rect comes from
/// `OverviewLayout`.
@MainActor final class OverviewController {
    private let logger = Logger(subsystem: "com.eightabyte.transom", category: "overview")
    /// The Arranger as it is now (windows, displays, World).
    private let arranger: () -> Arranger
    /// The Spaces lookup; nil while it is off.
    private let spaces: () -> SpacesSnapshot?
    /// The zoom stage's capture, cache and tile contents, shared so the overview and moves use one snapshot cache.
    private let zoom: () -> ZoomController
    /// Fires when the overview closes, by any path.
    var onClosed: () -> Void = {}

    private(set) var isOpen = false
    private var panels: [String: StagePanel] = [:]
    /// Each open panel's tiles: start = the real frame, end = the overview rect (AppKit coordinates).
    private var shown: [String: [StageTile]] = [:]
    private var escape: Task<Void, Never>?
    /// Bumped on every open and close, so a capture or animation finishing late never acts on a newer state.
    private var generation = 0

    init(arranger: @escaping () -> Arranger, spaces: @escaping () -> SpacesSnapshot?, zoom: @escaping () -> ZoomController) {
        self.arranger = arranger
        self.spaces = spaces
        self.zoom = zoom
    }

    /// The displays with an open overview panel (tests).
    var openPanels: [String] { isOpen ? Array(shown.keys) : [] }
    /// The tiles on that display's open panel (tests).
    func tileCount(display uuid: String) -> Int { isOpen ? shown[uuid]?.count ?? 0 : 0 }

    /// Show Overview while open dismisses it.
    func toggle(trigger: String) {
        if isOpen { dismiss(reason: "toggle") } else { open(trigger: trigger) }
    }

    /// Captures the current-Space windows (≤ 120 ms), then shows every panel with each tile over its window and moves the
    /// tiles to their overview rects.
    func open(trigger: String) {
        guard !isOpen else { return }
        isOpen = true
        generation += 1
        let opened = generation
        let started = ContinuousClock.now
        let arranger = arranger()
        let inputs = Self.inputs(arranger, spaces: spaces(), frontToBack: CGWindowList.onScreenFrontToBack())
        let layout = OverviewLayout(displays: inputs)
        let zoom = zoom()
        var requests: [(CGWindowID, CGSize)] = []
        for display in layout.displays {
            let scale = Displays.screen(uuid: display.uuid)?.backingScaleFactor ?? 2
            for tile in display.tiles {
                if let id = zoom.cgWindow(tile.window) { requests.append((id, CGSize(width: tile.rect.width * scale, height: tile.rect.height * scale))) }
            }
        }
        escape = Task { [weak self] in
            for await key in KeyboardShortcuts.events(for: KeyboardShortcuts.Shortcut(.escape)) where key == .keyDown {
                self?.dismiss(reason: "esc")
            }
        }
        Task { [weak self] in
            let images = await zoom.overviewImages(requests)
            guard let self, self.isOpen, self.generation == opened else { return }
            self.show(layout, arranger: arranger, images: images, trigger: trigger, started: started)
        }
    }

    private func show(_ layout: OverviewLayout, arranger: Arranger, images: [UInt32: CGImage], trigger: String, started: ContinuousClock.Instant) {
        guard let primaryHeight = NSScreen.screens.first.map({ Double($0.frame.height) }) else { return }
        func appKit(_ rect: Rect) -> CGRect {
            let r = Coordinates.appKit(fromTopLeft: rect, primaryHeight: primaryHeight)
            return CGRect(x: r.x, y: r.y, width: r.width, height: r.height)
        }
        let zoom = zoom()
        var snapshots = 0, fallbacks = 0
        for display in layout.displays {
            guard let panel = panel(for: display.uuid) else { continue }
            let tiles = display.tiles.map { tile in
                let cg = zoom.cgWindow(tile.window)
                let image = cg.flatMap { images[$0] ?? zoom.cachedSnapshot($0) }
                if image == nil { fallbacks += 1 } else { snapshots += 1 }
                let real = arranger.windows[tile.window.identity]?.frame ?? tile.rect
                return StageTile(
                    id: cg ?? tile.window.windowID, start: appKit(real), end: appKit(tile.rect),
                    content: image.map { .snapshot($0) } ?? zoom.fallback(tile.window))
            }
            if panel.isVisible { panel.freezeAtPresentation() }  // a close still fading: cancel its order-out
            panel.show(tiles: tiles)
            panel.animate {}
            shown[display.uuid] = tiles
        }
        let ms = Int((ContinuousClock.now - started) / .milliseconds(1))
        logger.info(
            "open \(trigger, privacy: .public): \(layout.displays.count, privacy: .public) displays, \(snapshots + fallbacks, privacy: .public) tiles, \(snapshots, privacy: .public) snapshots, \(fallbacks, privacy: .public) fallback, \(ms, privacy: .public) ms"
        )
    }

    /// Esc, Show Overview again: the reverse of open, then the stage fades out. No window command: nothing moved.
    func dismiss(reason: String) {
        guard close(reason: reason) else { return }
        let closed = generation
        let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        for (uuid, tiles) in shown {
            guard let panel = panels[uuid] else { continue }
            if reduceMotion {
                panel.fadeOut(duration: StagePanel.moveDuration)
                continue
            }
            let back = tiles.map { StageTile(id: $0.id, start: $0.end, end: $0.start, content: $0.content) }
            panel.retarget(to: back) { [weak self, weak panel] in
                guard self?.generation == closed else { return }
                panel?.fadeOut()
            }
        }
        shown = [:]
    }

    /// A Space, display, focus or session change, or another command: the stage fades out at once.
    func interrupt(reason: String) {
        guard close(reason: reason) else { return }
        for uuid in shown.keys { panels[uuid]?.fadeOut() }
        shown = [:]
    }

    private func close(reason: String) -> Bool {
        guard isOpen else { return false }
        isOpen = false
        generation += 1
        escape?.cancel()
        escape = nil
        logger.info("dismiss: \(reason, privacy: .public)")
        onClosed()
        return true
    }

    /// Displays changed: every panel is made again on the next open (a display may have changed size or gone).
    func displaysChanged() {
        interrupt(reason: "displays changed")
        for panel in panels.values { panel.orderOut(nil) }
        panels = [:]
    }

    private func panel(for uuid: String) -> StagePanel? {
        if let panel = panels[uuid] { return panel }
        guard let screen = Displays.screen(uuid: uuid) else { return nil }
        let panel = StagePanel(screen: screen)
        panels[uuid] = panel
        return panel
    }

    // MARK: Inputs

    /// Each display's shown windows on its current Space, back to front: tracked, not excluded, present, on that Space
    /// and on screen now (the CG list leaves out minimised and hidden windows). Without a CG list every such window counts.
    static func inputs(_ arranger: Arranger, spaces: SpacesSnapshot?, frontToBack: [CGWindowEntry]?) -> [OverviewDisplayInput] {
        let depth = frontToBack.map { list in Dictionary(list.enumerated().map { ($1.windowID, $0) }, uniquingKeysWith: { first, _ in first }) }
        return arranger.displays.enumerated().map { index, display in
            let current = display.currentSpaceID
            let shown = arranger.windows.values.compactMap { info -> (WindowInfo, Int)? in
                guard info.displayUUID == display.uuid, !info.isExcluded, info.state == .present else { return nil }
                if let current, let on = info.spaces, !on.contains(current) { return nil }
                let id = info.visibleMemberID ?? info.window.windowID
                guard let depth else { return (info, 0) }
                return depth[id].map { (info, $0) }
            }
            .sorted { $0.1 != $1.1 ? $0.1 > $1.1 : $0.0.window.identity < $1.0.window.identity }  // deepest (back) first
            let fullScreen = spaces?.displays.first { $0.displayUUID == display.uuid }
                .flatMap { list in list.spaces.first { $0.id == list.current } }?.kind == .fullScreen
            return OverviewDisplayInput(
                uuid: display.uuid, visibleFrame: display.visibleFrame, isMain: index == 0, isFullScreen: fullScreen, current: current,
                windows: shown.map { OverviewWindow(window: $0.0.window, frame: $0.0.frame) })
        }
    }
}

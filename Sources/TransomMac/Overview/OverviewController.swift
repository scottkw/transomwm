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
    /// Posts the chords that switch Spaces (06-07).
    private let switcher: SpaceSwitcher
    /// Fires when the overview closes, by any path.
    var onClosed: () -> Void = {}
    /// Focuses a window picked on another Space, once that Space shows (AX lists it only then).
    var focusWindow: (TransomModel.WindowRef) async -> Void = { _ in }
    /// A pick's Space switch did not land within 1 s: beep and announce this text.
    var onSwitchFailed: (String) -> Void = { _ in }
    /// A press that travels this far before release is a drag, not a click (D-16).
    static let dragThreshold: CGFloat = 4

    private(set) var isOpen = false
    private var panels: [String: StagePanel] = [:]
    /// Each open panel's tiles: start = the real frame, end = the overview rect (AppKit coordinates).
    private var shown: [String: [StageTile]] = [:]
    private var escape: Task<Void, Never>?
    /// Bumped on every open and close, so a capture or animation finishing late never acts on a newer state.
    private var generation = 0
    /// The open overview's geometry, for hit-testing clicks.
    private var layout: OverviewLayout?

    init(
        arranger: @escaping () -> Arranger, spaces: @escaping () -> SpacesSnapshot?, zoom: @escaping () -> ZoomController, switcher: SpaceSwitcher
    ) {
        self.arranger = arranger
        self.spaces = spaces
        self.zoom = zoom
        self.switcher = switcher
    }

    /// The displays with an open overview panel (tests).
    var openPanels: [String] { isOpen ? Array(shown.keys) : [] }
    /// The tiles on that display's open panel (tests).
    func tileCount(display uuid: String) -> Int { isOpen ? shown[uuid]?.count ?? 0 : 0 }

    /// Show Overview while open dismisses it. False when it could not open (every display is in full screen).
    @discardableResult func toggle(trigger: String) -> Bool {
        guard !isOpen else {
            dismiss(reason: "toggle")
            return true
        }
        return open(trigger: trigger)
    }

    /// Captures the current-Space windows (≤ 120 ms), then shows every panel with each tile over its window and moves the
    /// tiles to their overview rects. False, with nothing shown, when no display can have a panel.
    @discardableResult func open(trigger: String) -> Bool {
        guard !isOpen else { return true }
        let started = ContinuousClock.now
        let arranger = arranger()
        let snapshot = spaces()
        let inputs = Self.inputs(arranger, spaces: snapshot, frontToBack: CGWindowList.onScreenFrontToBack())
        for input in inputs where input.spaces.count > OverviewLayout.maxSpaces {
            logger.notice("display \(input.uuid, privacy: .public) lists \(input.spaces.count, privacy: .public) Spaces; the strip shows 16")
        }
        let message = NSAttributedString(string: OverviewCopy.noWindows, attributes: [.font: NSFont.systemFont(ofSize: 13)]).size()
        let layout = OverviewLayout(
            displays: inputs, stripShown: snapshot != nil, separateSpaces: snapshot?.separateSpaces ?? true,
            emptyCapsuleSize: Size(width: ceil(message.width) + 16, height: 24))
        guard !layout.displays.isEmpty else { return false }
        isOpen = true
        generation += 1
        let opened = generation
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
            self.show(layout, inputs: inputs, arranger: arranger, images: images, trigger: trigger, started: started)
        }
        return true
    }

    private func show(
        _ layout: OverviewLayout, inputs: [OverviewDisplayInput], arranger: Arranger, images: [UInt32: CGImage], trigger: String,
        started: ContinuousClock.Instant
    ) {
        guard let primaryHeight = NSScreen.screens.first.map({ Double($0.frame.height) }) else { return }
        func appKit(_ rect: Rect) -> CGRect {
            let r = Coordinates.appKit(fromTopLeft: rect, primaryHeight: primaryHeight)
            return CGRect(x: r.x, y: r.y, width: r.width, height: r.height)
        }
        self.layout = layout
        let zoom = zoom()
        var snapshots = 0, fallbacks = 0
        func image(_ window: TransomModel.WindowRef) -> CGImage? { zoom.cgWindow(window).flatMap { images[$0] ?? zoom.cachedSnapshot($0) } }
        for display in layout.displays {
            guard let panel = panel(for: display.uuid), let input = inputs.first(where: { $0.uuid == display.uuid }) else { continue }
            let collapsed = arranger.homeView(on: display.uuid)?.collapsed ?? [:]
            let tiles = display.tiles.map { tile in
                let picture = image(tile.window)
                if picture == nil { fallbacks += 1 } else { snapshots += 1 }
                let real = arranger.windows[tile.window.identity]?.frame ?? tile.rect
                let content: TileLayer.Content =
                    collapsed[tile.window] != nil ? zoom.collapsedBlock(tile.window) : picture.map { .snapshot($0) } ?? zoom.fallback(tile.window)
                return StageTile(id: zoom.cgWindow(tile.window) ?? tile.window.windowID, start: appKit(real), end: appKit(tile.rect), content: content)
            }
            if panel.isVisible { panel.freezeAtPresentation() }  // a close still fading: cancel its order-out
            panel.show(tiles: tiles)
            panel.showOverview(overlay(display, input: input, image: image, appKit: appKit))
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
            panel.clearOverview()
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
        panel.onOverviewClick = { [weak self] point, travel in self?.click(at: point, travel: travel) }
        panels[uuid] = panel
        return panel
    }

    // MARK: Picks (06-07)

    /// A released press on a panel (AppKit global point). A drag does nothing (D-16); the backdrop dismisses.
    private func click(at point: CGPoint, travel: CGFloat) {
        guard isOpen, travel < Self.dragThreshold, let layout, let primaryHeight = NSScreen.screens.first.map({ Double($0.frame.height) }) else { return }
        guard let item = layout.item(at: Point(x: point.x, y: primaryHeight - point.y)) else { return dismiss(reason: "backdrop") }
        pick(item)
    }

    /// Picks a strip item: another Space's thumbnail switches there; the current one's dismisses. Main-area tiles are
    /// picked by 06-08/06-09.
    func pick(_ item: OverviewItem) {
        guard isOpen, let layout else { return }
        guard case .thumbnail(let space) = item else { return }
        guard let display = layout.displays.first(where: { $0.thumbnails.contains { $0.spaceID == space } }) else { return }
        if display.thumbnails.first(where: { $0.spaceID == space })?.isCurrent == true { return dismiss(reason: "current space") }
        logger.info("pick space \(space, privacy: .public)")
        switchAway(to: space, on: display.uuid)
    }

    /// The stage fades out (120 ms), then the display switches to `space`. A switch that does not land is refused.
    private func switchAway(to space: UInt64, on display: String) {
        interrupt(reason: "pick")
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(StagePanel.revealFade))
            guard let self else { return }
            if !(await self.switcher.switchTo(space: space, on: display)) { self.onSwitchFailed("switch to space \(space) failed") }
        }
    }

    /// The strip (thumbnails, mini tiles, labels) and the empty-message capsule of one display.
    private func overlay(
        _ display: OverviewDisplayLayout, input: OverviewDisplayInput, image: (TransomModel.WindowRef) -> CGImage?, appKit: (Rect) -> CGRect
    ) -> OverviewOverlay {
        let zoom = zoom()
        let thumbnails = display.thumbnails.map { thumb in
            let space = input.spaces.first { $0.id == thumb.spaceID }
            let label: String
            if space?.kind == .fullScreen {
                let windows = input.hiddenSpaceWindows[thumb.spaceID] ?? []
                let apps = windows.compactMap { NSRunningApplication(processIdentifier: $0.window.pid)?.localizedName }
                label = OverviewCopy.fullScreenLabel(apps.reduce(into: []) { if !$0.contains($1) { $0.append($1) } })
            } else {
                label = space.map { OverviewCopy.desktopLabel($0.index) } ?? ""
            }
            let radius = max(2, TileLayer.cornerRadius * thumb.rect.width / max(1, input.visibleFrame.width))
            // Mini tiles show only snapshots already cached (D-03): never a capture of a hidden Space.
            let minis = thumb.miniTiles.map { mini in
                OverviewOverlay.Mini(
                    rect: appKit(mini.rect), content: image(mini.window).map { .snapshot($0) } ?? zoom.collapsedBlock(mini.window), radius: radius)
            }
            return OverviewOverlay.Thumbnail(
                rect: appKit(thumb.rect), labelRect: appKit(thumb.labelRect), label: label, isCurrent: thumb.isCurrent, minis: minis)
        }
        return OverviewOverlay(thumbnails: thumbnails, emptyMessage: display.emptyCapsule.map { (appKit($0), OverviewCopy.noWindows) })
    }

    // MARK: Inputs

    /// Each display's inputs. Shown windows: tracked, not excluded, present, on the current Space and on screen now (the
    /// CG list leaves out minimised and hidden windows), back to front; without a CG list every such window counts. A
    /// zoomed display adds its home view. Other Spaces' windows come from their stored desks, planned, and the tracked
    /// windows' own Space sets for full-screen Spaces: no AX reads (D-14).
    static func inputs(_ arranger: Arranger, spaces: SpacesSnapshot?, frontToBack: [CGWindowEntry]?) -> [OverviewDisplayInput] {
        let depth = frontToBack.map { list in Dictionary(list.enumerated().map { ($1.windowID, $0) }, uniquingKeysWith: { first, _ in first }) }
        return arranger.displays.enumerated().map { index, display in
            let list = spaces?.displays.first { $0.displayUUID == display.uuid }
            let current = list?.current ?? display.currentSpaceID
            let shown = arranger.windows.values.compactMap { info -> (WindowInfo, Int)? in
                guard info.displayUUID == display.uuid, !info.isExcluded, info.state == .present else { return nil }
                if let current, let on = info.spaces, !on.contains(current) { return nil }
                let id = info.visibleMemberID ?? info.window.windowID
                guard let depth else { return (info, 0) }
                return depth[id].map { (info, $0) }
            }
            .sorted { $0.1 != $1.1 ? $0.1 > $1.1 : $0.0.window.identity < $1.0.window.identity }  // deepest (back) first
            var hidden: [UInt64: [OverviewWindow]] = [:]
            for space in list?.spaces ?? [] where space.id != current {
                hidden[space.id] = space.kind == .fullScreen
                    ? arranger.windows.values.filter { $0.spaces?.contains(space.id) == true }.sorted { $0.window.identity < $1.window.identity }
                        .map { OverviewWindow(window: $0.window, frame: $0.frame) }
                    : plannedWindows(arranger, key: DeskKey(displayUUID: display.uuid, spaceID: space.id), area: display.visibleFrame)
            }
            let homeView = arranger.homeView(on: display.uuid)
            return OverviewDisplayInput(
                uuid: display.uuid, visibleFrame: display.visibleFrame, isMain: index == 0,
                isFullScreen: list?.spaces.first { $0.id == current }?.kind == .fullScreen, spaces: list?.spaces ?? [], current: current,
                windows: shown.map { OverviewWindow(window: $0.0.window, frame: $0.0.frame) },
                home: (homeView?.frames ?? [:]).merging(homeView?.collapsed ?? [:]) { first, _ in first }, hiddenSpaceWindows: hidden)
        }
    }

    /// A hidden Space's windows: its docked windows at their planned tiles, then its present floaters at their frames.
    private static func plannedWindows(_ arranger: Arranger, key: DeskKey, area: Rect) -> [OverviewWindow] {
        guard let desk = arranger.world[key] else { return [] }
        let planned = (try? Planner.plan(desk: desk, area: area, gap: arranger.gap, mins: [:]).frames) ?? [:]
        let docked = desk.tree.windows.compactMap { window in planned[window].map { OverviewWindow(window: window, frame: $0) } }
        let floating = desk.desktop.windows.filter { $0.state == .present }.compactMap { floater in
            (planned[floater.window] ?? arranger.windows[floater.window.identity]?.frame).map { OverviewWindow(window: floater.window, frame: $0) }
        }
        return docked + floating
    }
}

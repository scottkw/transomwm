import AppKit
import TransomEngine
import TransomModel
import TransomPrivate
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
    /// The frontmost app's focused tracked window: the initial selection when it is shown.
    var focused: () -> TransomModel.WindowRef? = { nil }
    /// A press that travels this far before release is a drag, not a click (D-16).
    static let dragThreshold: CGFloat = 4

    private(set) var isOpen = false
    private var panels: [String: StagePanel] = [:]
    /// Each open panel's tiles: start = the real frame, end = the overview rect (AppKit coordinates).
    private var shown: [String: [StageTile]] = [:]
    /// The one selection across every display (D-04).
    private(set) var selection = OverviewSelection()
    /// Bumped on every open and close, so a capture or animation finishing late never acts on a newer state.
    private var generation = 0
    /// The open overview's geometry, for hit-testing clicks.
    private var layout: OverviewLayout?
    /// Per display: the capture waiting for its Space change to settle, and the Space whose visit was captured (D-03).
    private var visitTasks: [String: Task<Void, Never>] = [:]
    private var capturedVisit: [String: UInt64] = [:]

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
        let requests = Self.requests(layout.displays, zoom: zoom)
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
        selection = OverviewSelection.initial(layout: layout, focused: focused(), pointer: pointer())
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
        takeKeys()
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
        releaseKeys()
        selection = OverviewSelection()
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
        panel.onKey = { [weak self] event in self?.key(event) }
        panels[uuid] = panel
        return panel
    }

    // MARK: Keys and selection (06-08)

    /// While open, one panel is key without activating Transom, so the overview keys never reach the app behind and the
    /// event tap stays mouse-only (T-03-28). macOS 15 does not deliver modifier-less Return, Tab or Space as Carbon
    /// hotkeys, so these are not hotkeys (06-08 Rule 4 deviation).
    private func takeKeys() {
        let uuid = selection.display ?? layout?.displays.first?.uuid
        guard isOpen, let panel = uuid.flatMap({ panels[$0] }) ?? panels.values.first(where: \.isVisible) else { return }
        panel.takesKeys = true
        panel.makeKey()
    }

    /// Every close path: no panel may become key again, and the key one stops acting on keys at once. It hands key back
    /// to the frontmost app when it orders out at the end of its fade.
    private func releaseKeys() {
        for panel in panels.values { panel.takesKeys = false }
    }

    /// True while an overview panel is key (tests: keys must go back to the frontmost app after every close).
    var holdsKeys: Bool { panels.values.contains { $0.isKeyWindow } }

    /// The overview keys (06 UI-SPEC Surface 3); any other key does nothing while open.
    private func key(_ event: NSEvent) {
        guard isOpen else { return }
        switch event.keyCode {
        case 53: dismiss(reason: "esc")  // Esc
        case 123: move(.left)
        case 124: move(.right)
        case 125: move(.down)
        case 126: move(.up)
        case 48: move(event.modifierFlags.contains(.shift) ? .backTab : .tab)
        case 36, 76: pickSelection()  // Return, keypad Enter
        default: break
        }
    }

    private func move(_ key: OverviewKey) {
        guard isOpen, let layout else { return }
        selection.move(key, in: layout, focused: focused())
    }

    /// A window closed while open: if it was selected, the selection moves to the nearest remaining item.
    func windowClosed(_ window: TransomModel.WindowRef) {
        guard isOpen, let layout else { return }
        selection.reselect(afterRemoving: window, in: layout)
    }

    /// Return: picks the selected item.
    private func pickSelection() {
        guard isOpen, let item = selection.selected else { return }
        pick(item)
    }

    /// The pointer in top-left global points.
    private func pointer() -> Point? {
        guard let primaryHeight = NSScreen.screens.first.map({ Double($0.frame.height) }) else { return nil }
        let location = NSEvent.mouseLocation
        return Point(x: location.x, y: primaryHeight - location.y)
    }

    // MARK: Picks (06-07)

    /// A released press on a panel (AppKit global point). A drag does nothing (D-16); the backdrop dismisses.
    private func click(at point: CGPoint, travel: CGFloat) {
        guard isOpen, travel < Self.dragThreshold, let layout, let primaryHeight = NSScreen.screens.first.map({ Double($0.frame.height) }) else { return }
        guard let item = layout.item(at: Point(x: point.x, y: primaryHeight - point.y)) else { return dismiss(reason: "backdrop") }
        pick(item)
    }

    /// Picks an item. A main-area tile focuses and raises its window as the reverse animation starts. Another Space's
    /// thumbnail switches there; a mini tile on another Space switches there, then focuses its window. The current
    /// Space's thumbnail dismisses, and its mini tile focuses that window.
    func pick(_ item: OverviewItem) {
        guard isOpen, let layout else { return }
        let space: UInt64, window: TransomModel.WindowRef?
        switch item {
        case .tile(let picked): return pickOnCurrentSpace(picked, in: layout)
        case .thumbnail(let id): (space, window) = (id, nil)
        case .miniTile(let picked, let id): (space, window) = (id, picked)
        }
        guard let display = layout.displays.first(where: { $0.thumbnails.contains { $0.spaceID == space } }) else { return }
        if display.thumbnails.first(where: { $0.spaceID == space })?.isCurrent == true {
            dismiss(reason: "current space")
            if let window { Task { await focusWindow(window) } }
            return
        }
        if let window {
            logger.info("pick window \(window.windowID, privacy: .public) on space \(space, privacy: .public) (switch space)")
        } else {
            logger.info("pick space \(space, privacy: .public)")
        }
        switchAway(to: space, on: display.uuid, then: window)
    }

    /// A shown window: the reverse animation starts with its tile on top (the order once it is raised), and it gets focus.
    private func pickOnCurrentSpace(_ window: TransomModel.WindowRef, in layout: OverviewLayout) {
        guard let display = layout.displays.first(where: { $0.tiles.contains { $0.window == window } }) else { return }
        let space = arranger().displays.first { $0.uuid == display.uuid }?.currentSpaceID ?? 0
        logger.info("pick window \(window.windowID, privacy: .public) on space \(space, privacy: .public) (same space)")
        panels[display.uuid]?.bringToFront(zoom().cgWindow(window) ?? window.windowID)
        dismiss(reason: "pick")
        Task { await focusWindow(window) }
    }

    /// The stage fades out (120 ms), then the display switches to `space` and `window` gets focus. A switch that does not
    /// land within 1 s beeps and announces (Surface 2); the overview is closed by then.
    private func switchAway(to space: UInt64, on display: String, then window: TransomModel.WindowRef?) {
        interrupt(reason: "pick")
        let refusal = refusal(for: space, on: display)
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(StagePanel.revealFade))
            guard let self else { return }
            guard await self.switcher.switchTo(space: space, on: display) else { return self.onSwitchFailed(refusal) }
            if let window { await self.focusWindow(window) }
        }
    }

    /// "Couldn't switch to Desktop {n}", or the full-screen Space's app.
    private func refusal(for space: UInt64, on display: String) -> String {
        let info = spaces()?.displays.first { $0.displayUUID == display }?.spaces.first { $0.id == space }
        guard info?.kind == .fullScreen else { return OverviewCopy.couldNotSwitch(desktop: info?.index ?? 0) }
        let owner = arranger().windows.values.first { $0.spaces?.contains(space) == true }?.window
        let name = owner.map { NSRunningApplication(processIdentifier: $0.pid)?.localizedName ?? $0.bundleID } ?? ""
        return OverviewCopy.couldNotSwitch(app: MenuCopy.truncatedAppName(name))
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

    // MARK: Snapshots of a visit (D-03)

    /// A display now shows `space`: 1 s after the change settles (latest change wins), the windows it shows are captured
    /// once into the snapshot cache, so the strip has real previews of this Space after the user leaves it. A repeated
    /// change to the Space already captured on this visit does nothing.
    func spaceDidSettle(display uuid: String, space: UInt64?) {
        guard let space, capturedVisit[uuid] != space else { return }
        capturedVisit[uuid] = nil
        visitTasks[uuid]?.cancel()
        visitTasks[uuid] = Task { [weak self] in
            try? await Task.sleep(for: .seconds(1))
            guard !Task.isCancelled, let self else { return }
            await self.captureVisit(display: uuid, space: space)
        }
    }

    /// Only the on-screen windows of the Space the display shows now, at their main-area size × backing scale; never a
    /// window on a hidden Space (D-03), so nothing without a CG on-screen list. Screen Recording is checked by the capture.
    private func captureVisit(display uuid: String, space: UInt64) async {
        let snapshot = spaces()
        guard (snapshot?.displays.first { $0.displayUUID == uuid }?.current ?? SkyLightSpaces.currentSpace(displayUUID: uuid)) == space,
            let onScreen = CGWindowList.onScreenFrontToBack()
        else { return }
        let input = Self.inputs(arranger(), spaces: snapshot, frontToBack: onScreen).filter { $0.uuid == uuid }
        let layout = OverviewLayout(
            displays: input, stripShown: snapshot != nil, separateSpaces: snapshot?.separateSpaces ?? true, emptyCapsuleSize: Size(width: 0, height: 0))
        let zoom = zoom()
        let images = await zoom.overviewImages(Self.requests(layout.displays, zoom: zoom), deadline: Self.visitBudget)
        capturedVisit[uuid] = space
        logger.info("space \(space, privacy: .public) captured \(images.count, privacy: .public) windows after visit")
    }

    /// A background capture has no one waiting: it may take longer than an open's 120 ms.
    static let visitBudget = Duration.seconds(2)

    /// One capture per shown tile, at its overview size × the display's backing scale.
    private static func requests(_ displays: [OverviewDisplayLayout], zoom: ZoomController) -> [(CGWindowID, CGSize)] {
        displays.flatMap { display in
            let scale = Displays.screen(uuid: display.uuid)?.backingScaleFactor ?? 2
            return display.tiles.compactMap { tile in
                zoom.cgWindow(tile.window).map { ($0, CGSize(width: tile.rect.width * scale, height: tile.rect.height * scale)) }
            }
        }
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

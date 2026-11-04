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
    /// Brings a picked parked or collapsed window into view on its display (a camera move) and focuses it at settle.
    var frameWindow: (TransomModel.WindowRef, _ displayUUID: String) async -> Void = { _, _ in }
    /// A pick's Space switch did not land within 1 s: beep and announce this text.
    var onSwitchFailed: (String) -> Void = { _ in }
    /// The frontmost app's focused tracked window: the initial selection when it is shown.
    var focused: () -> TransomModel.WindowRef? = { nil }
    /// A press that travels this far before release is a drag, not a click (D-16).
    static let dragThreshold: CGFloat = 4

    private(set) var isOpen = false
    private(set) var panels: [String: StagePanel] = [:]
    /// Each open panel's tiles: start = the real frame, end = the overview rect (AppKit coordinates).
    private var shown: [String: [StageTile]] = [:]
    /// The one selection across every display (D-04), drawn as it changes.
    private(set) var selection = OverviewSelection() {
        didSet {
            guard selection != oldValue else { return }
            markSelection()
            announceSelection(from: oldValue)
        }
    }
    /// The latest selection announcement waiting for its 150 ms slot (nil: none waiting).
    private var queuedAnnouncement: String?
    private let announcementTimer = WakeTimer()
    /// Fires when an open animation ends: trigger-to-end time, tiles and snapshots (Debug S6).
    var onOpened: ((ms: Int, windows: Int, snapshots: Int)) -> Void = { _ in }
    /// Each open panel's strip as built, so a selected mini tile's label swap can be undone.
    private var overlays: [String: OverviewOverlay] = [:]
    /// The thumbnail whose label shows a selected mini tile's title.
    private var swappedLabel: (display: String, space: UInt64)?
    /// Bumped on every open and close, so a capture or animation finishing late never acts on a newer state.
    private var generation = 0
    /// The open overview's geometry, for hit-testing clicks.
    private(set) var layout: OverviewLayout?
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
    /// The window tiles on that display's open panel, group strips not counted (tests).
    func tileCount(display uuid: String) -> Int {
        isOpen ? shown[uuid]?.filter { switch $0.content { case .strip, .placeholder: false; default: true } }.count ?? 0 : 0
    }

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
        let zoom = zoom()
        let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion  // read at each open
        let opened = generation
        var timed = false
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
            // After the tiles, so each strip draws above its group's tile; a collapsed group is one block, no strip.
            let strips = display.tiles.compactMap { tile in
                collapsed[tile.window] == nil ? strip(tile, scale: display.scale, arranger: arranger, appKit: appKit) : nil
            }
            let waiting = display.placeholders.map { placeholder($0, input: input, appKit: appKit) }
            if panel.isVisible { panel.freezeAtPresentation() }  // a close still fading: cancel its order-out
            panel.show(tiles: waiting + tiles + strips)
            let strip = overlay(display, input: input, image: image, appKit: appKit)
            overlays[display.uuid] = strip
            panel.showOverview(strip)
            // Reduce Motion: the real-frame tiles fade out as the overview fades in, nothing moving (Surface 1 Motion).
            let first = !timed
            timed = true
            panel.animate(crossfade: reduceMotion) { [weak self] in
                guard first, let self, self.generation == opened else { return }
                self.opened(trigger: trigger, started: started, displays: layout.displays.count, snapshots: snapshots, fallbacks: fallbacks)
            }
            shown[display.uuid] = waiting + tiles + strips
        }
        swappedLabel = nil
        selection = OverviewSelection.initial(layout: layout, focused: focused(), pointer: pointer())  // drawn by didSet, not announced
        takeKeys()
        postAnnouncement(OverviewCopy.openedAnnouncement(windows: snapshots + fallbacks, displays: layout.displays.count))
    }

    /// The open animation ended: `{ms}` runs from the trigger to here (Debug S6 and the open log line).
    private func opened(trigger: String, started: ContinuousClock.Instant, displays: Int, snapshots: Int, fallbacks: Int) {
        let ms = Int((ContinuousClock.now - started) / .milliseconds(1))
        logger.info(
            "open \(trigger, privacy: .public): \(displays, privacy: .public) displays, \(snapshots + fallbacks, privacy: .public) tiles, \(snapshots, privacy: .public) snapshots, \(fallbacks, privacy: .public) fallback, \(ms, privacy: .public) ms"
        )
        onOpened((ms, snapshots + fallbacks, snapshots))
    }

    /// Esc, Show Overview again: the reverse of open, then the stage fades out. No window command: nothing moved.
    /// A pick says nothing extra (`announce` false): VoiceOver reads the focused window itself.
    func dismiss(reason: String, announce: Bool = true) {
        guard close(log: "dismiss: \(reason)") else { return }
        if announce { postAnnouncement(OverviewCopy.closedAnnouncement) }
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

    /// A Space, display, focus or session change, the status menu, or another command: the stage fades out over 120 ms
    /// at once, with no reverse animation (also under Reduce Motion).
    func interrupt(reason: OverviewCopy.Interruption) { fadeAway(log: OverviewCopy.interruptedLog(reason)) }

    private func fadeAway(log: String) {
        guard close(log: log) else { return }
        for uuid in shown.keys { panels[uuid]?.fadeOut() }
        shown = [:]
    }

    private func close(log: String) -> Bool {
        guard isOpen else { return false }
        isOpen = false
        generation += 1
        releaseKeys()
        selection = OverviewSelection()
        queuedAnnouncement = nil
        announcementTimer.cancel()
        logger.info("\(log, privacy: .public)")
        onClosed()
        // Without Screen Recording, the Phase 4 explainer may show once, after the stage has gone, never during it.
        let closed = generation
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(StagePanel.moveDuration + StagePanel.revealFade))
            guard let self, !self.isOpen, self.generation == closed else { return }
            self.zoom().offerExplainerAfterOverview()
        }
        return true
    }

    /// Displays changed: every panel is made again on the next open (a display may have changed size or gone).
    func displaysChanged() {
        interrupt(reason: .displayChange)
        for panel in panels.values { panel.orderOut(nil) }
        panels = [:]
    }

    private func panel(for uuid: String) -> StagePanel? {
        if let panel = panels[uuid] {
            if panel.isOnActiveSpace { return panel }
            // macOS 27 can leave a panel on the Space shown during a screen lock despite .canJoinAllSpaces: ordered in
            // again, it would stay there, off screen. A new panel joins every Space, as after a relaunch.
            logger.notice("display \(uuid, privacy: .public): overview panel was off the shown Space; made a new one")
            panel.orderOut(nil)
        }
        guard let screen = Displays.screen(uuid: uuid) else { return nil }
        let panel = StagePanel(screen: screen)
        panel.onOverviewClick = { [weak self] point, travel in self?.click(at: point, travel: travel) }
        panel.onKey = { [weak self] event in self?.key(event) }
        panel.onOverviewHover = { [weak self] point in self?.hover(at: point) }
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

    /// A window closed while open: its tile fades out and, if it was selected, the selection moves to the nearest
    /// remaining item.
    func windowClosed(_ window: TransomModel.WindowRef) {
        guard isOpen, let layout else { return }
        selection.reselect(afterRemoving: window, in: layout)
        windowsChanged()
    }

    /// While open, windows opened or closed: the layout is made again from the Arranger as it is now. A tile new to it
    /// fades in over 120 ms at its overview rect, a tile gone from it fades out over 120 ms; every other tile, the strip
    /// and the empty capsule stay as they are.
    /// shortcut: the strip and the empty capsule are not rebuilt; rebuild them if a live change there turns out to matter.
    func windowsChanged() {
        guard isOpen, let old = layout, let primaryHeight = NSScreen.screens.first.map({ Double($0.frame.height) }) else { return }
        let snapshot = spaces()
        let arranger = arranger()
        let inputs = Self.inputs(arranger, spaces: snapshot, frontToBack: CGWindowList.onScreenFrontToBack())
        let new = OverviewLayout(
            displays: inputs, stripShown: snapshot != nil, separateSpaces: snapshot?.separateSpaces ?? true, emptyCapsuleSize: Size(width: 0, height: 0))
        func appKit(_ rect: Rect) -> CGRect {
            let r = Coordinates.appKit(fromTopLeft: rect, primaryHeight: primaryHeight)
            return CGRect(x: r.x, y: r.y, width: r.width, height: r.height)
        }
        let zoom = zoom()
        var displays: [OverviewDisplayLayout] = []
        for display in old.displays {
            guard let panel = panels[display.uuid], let fresh = new.displays.first(where: { $0.uuid == display.uuid }) else {
                displays.append(display)
                continue
            }
            let kept = display.tiles.filter { tile in fresh.tiles.contains { $0.window == tile.window } }
            let added = fresh.tiles.filter { tile in !display.tiles.contains { $0.window == tile.window } }
            let keptWaiting = display.placeholders.filter { tile in fresh.placeholders.contains { $0.window == tile.window } }
            let newWaiting = fresh.placeholders.filter { tile in !display.placeholders.contains { $0.window == tile.window } }
            guard kept.count != display.tiles.count || !added.isEmpty || keptWaiting.count != display.placeholders.count || !newWaiting.isEmpty else {
                displays.append(display)
                continue
            }
            let id = { (window: TransomModel.WindowRef) in zoom.cgWindow(window) ?? window.windowID }
            let gone = display.tiles.filter { tile in !kept.contains { $0.window == tile.window } }.map { id($0.window) }
            let goneWaiting = display.placeholders.filter { tile in !keptWaiting.contains { $0.window == tile.window } }.map(\.window.windowID)
            let removed = gone + gone.map(StageTile.stripID) + goneWaiting  // a gone tile's strip goes with it
            let addedTiles = added.map { tile in
                let content = zoom.cgWindow(tile.window).flatMap { zoom.cachedSnapshot($0) }.map { TileLayer.Content.snapshot($0) } ?? zoom.fallback(tile.window)
                let real = arranger.windows[tile.window.identity]?.frame ?? tile.rect
                return StageTile(id: id(tile.window), start: appKit(real), end: appKit(tile.rect), content: content)
            } + added.compactMap { strip($0, scale: fresh.scale, arranger: arranger, appKit: appKit) }
                + newWaiting.map { placeholder($0, input: inputs.first { $0.uuid == display.uuid }, appKit: appKit) }
            panel.fadeTiles(adding: addedTiles, removing: removed)
            shown[display.uuid] = (shown[display.uuid] ?? []).filter { !removed.contains($0.id) } + addedTiles
            var updated = display
            updated.tiles = kept + added
            updated.placeholders = keptWaiting + newWaiting
            displays.append(updated)
        }
        layout = OverviewLayout(laidOut: displays)
        logger.info("live update: \(displays.reduce(0) { $0 + $1.tiles.count }, privacy: .public) tiles")
    }

    /// Return: picks the selected item.
    private func pickSelection() {
        guard isOpen, let item = selection.selected else { return }
        pick(item)
    }

    /// The pointer moved over a panel (AppKit global): an item under it becomes the selection; the backdrop, a gap or
    /// the empty capsule leave the selection where it is, so a resting pointer never fights the keys. True over an item.
    private func hover(at point: CGPoint) -> Bool? {
        guard isOpen, let layout, let primaryHeight = NSScreen.screens.first.map({ Double($0.frame.height) }) else { return nil }
        let location = Point(x: point.x, y: primaryHeight - point.y)
        guard let item = layout.item(at: location), let display = layout.display(at: location) else { return false }
        selection = OverviewSelection(selected: item, display: display.uuid)
        return true
    }

    /// Draws the selection on its panel and clears the others; a selected mini tile's thumbnail label shows its title.
    private func markSelection() {
        guard isOpen, let layout, let primaryHeight = NSScreen.screens.first.map({ Double($0.frame.height) }) else {
            for panel in panels.values { panel.showMark(nil) }
            return
        }
        func appKit(_ rect: Rect) -> CGRect {
            let r = Coordinates.appKit(fromTopLeft: rect, primaryHeight: primaryHeight)
            return CGRect(x: r.x, y: r.y, width: r.width, height: r.height)
        }
        var label: (display: String, space: UInt64, title: String)?
        for display in layout.displays {
            guard let panel = panels[display.uuid] else { continue }
            guard display.uuid == selection.display, let item = selection.selected else {
                panel.showMark(nil)
                continue
            }
            switch item {
            case .tile(let window):
                guard let index = display.tiles.firstIndex(where: { $0.window == window }) else { panel.showMark(nil); continue }
                let rect = display.tiles[index].rect
                let id = zoom().cgWindow(window) ?? window.windowID
                let content = shown[display.uuid]?.first { $0.id == id }?.content
                guard case .snapshot? = content else {
                    panel.showMark(OverviewMark(ring: appKit(rect), radius: min(TileLayer.cornerRadius, min(rect.width, rect.height) / 2)))
                    continue  // a fallback tile already shows its title
                }
                let title = OverviewCopy.titleOrApp(title: window.titleHint, app: appName(window))
                let text = NSAttributedString(string: title, attributes: [.font: NSFont.systemFont(ofSize: 13)]).size()
                let capsule = OverviewLayout.titleCapsule(tile: rect, mainArea: display.mainArea, size: Size(width: ceil(text.width) + 16, height: 24))
                panel.showMark(OverviewMark(ring: appKit(rect), radius: TileLayer.cornerRadius * display.scale, titleRect: capsule.map(appKit), title: title))
            case .miniTile(let window, let space):
                guard let thumb = display.thumbnails.first(where: { $0.spaceID == space }), let mini = thumb.miniTiles.first(where: { $0.window == window })
                else { panel.showMark(nil); continue }
                let radius = max(2, TileLayer.cornerRadius * thumb.rect.width / max(1, display.visibleFrame.width))
                panel.showMark(OverviewMark(ring: appKit(mini.rect), radius: radius))
                label = (display.uuid, space, OverviewCopy.titleOrApp(title: window.titleHint, app: appName(window)))
            case .thumbnail(let space):
                guard let thumb = display.thumbnails.first(where: { $0.spaceID == space }) else { panel.showMark(nil); continue }
                panel.showMark(OverviewMark(ring: appKit(thumb.rect).insetBy(dx: -4, dy: -4), radius: 12))
            }
        }
        swapLabel(label)
    }

    /// Restores the thumbnail label swapped last, then shows `label` under its thumbnail (Label Regular).
    private func swapLabel(_ label: (display: String, space: UInt64, title: String)?) {
        if let old = swappedLabel, old.display != label?.display || old.space != label?.space, let strip = overlays[old.display] {
            panels[old.display]?.updateOverview(strip)
        }
        swappedLabel = label.map { ($0.display, $0.space) }
        guard let label, var strip = overlays[label.display],
            let index = layout?.displays.first(where: { $0.uuid == label.display })?.thumbnails.firstIndex(where: { $0.spaceID == label.space })
        else { return }
        strip.thumbnails[index].label = label.title
        strip.thumbnails[index].labelIsTitle = true
        panels[label.display]?.updateOverview(strip)
    }

    /// VoiceOver hears where the selection went, the latest one per 150 ms (holding an arrow queues no backlog). The
    /// initial selection is not announced: "Overview, {n} windows" is.
    private func announceSelection(from old: OverviewSelection) {
        guard isOpen, old.selected != nil, let text = selectionText(changedDisplay: old.display != selection.display) else { return }
        let idle = queuedAnnouncement == nil
        queuedAnnouncement = text
        guard idle else { return }
        announcementTimer.set(.now + .milliseconds(150)) { [weak self] in
            guard let self, let text = self.queuedAnnouncement else { return }
            self.queuedAnnouncement = nil
            postAnnouncement(text)
        }
    }

    /// The Accessibility table's words for the selected item, after the display's name when Tab changed display.
    private func selectionText(changedDisplay: Bool) -> String? {
        guard let item = selection.selected, let uuid = selection.display, let display = layout?.displays.first(where: { $0.uuid == uuid }) else {
            return nil
        }
        let spaceInfo = { (id: UInt64) in self.spaces()?.displays.first { $0.displayUUID == uuid }?.spaces.first { $0.id == id } }
        let text: String
        switch item {
        case .tile(let window):
            let tab = arranger().tabGroupMembers(holding: window).map { TabCopy.overviewTabSuffix(index: $0.selected + 1, count: $0.members.count) }
            text = OverviewCopy.tileAnnouncement(app: appName(window), title: window.titleHint) + (tab ?? "")
        case .miniTile(let window, let space):
            text = OverviewCopy.miniTileAnnouncement(app: appName(window), title: window.titleHint, desktop: spaceInfo(space)?.index ?? 0)
        case .thumbnail(let space):
            guard let index = display.thumbnails.firstIndex(where: { $0.spaceID == space }) else { return nil }
            let thumb = display.thumbnails[index]
            if spaceInfo(space)?.kind == .fullScreen {
                text = OverviewCopy.thumbnailAnnouncement(fullScreenApp: overlays[uuid]?.thumbnails[index].label ?? "")
            } else {
                text = OverviewCopy.thumbnailAnnouncement(desktop: spaceInfo(space)?.index ?? 0, current: thumb.isCurrent, windows: thumb.miniTiles.count)
            }
        }
        guard changedDisplay, let name = Displays.screen(uuid: uuid)?.localizedName else { return text }
        return OverviewCopy.displayPrefix(name, text)
    }

    private func appName(_ window: TransomModel.WindowRef) -> String {
        NSRunningApplication(processIdentifier: window.pid)?.localizedName ?? window.bundleID
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
            dismiss(reason: "current space", announce: false)
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
    /// A window the camera parked or collapsed (its display zoomed in): the overview closes the same way, then
    /// `frameWindow` brings it into view with a camera move and focuses it at settle.
    private func pickOnCurrentSpace(_ window: TransomModel.WindowRef, in layout: OverviewLayout) {
        guard let display = layout.displays.first(where: { $0.tiles.contains { $0.window == window } }) else { return }
        let arranger = arranger()
        let space = arranger.displays.first { $0.uuid == display.uuid }?.currentSpaceID ?? 0
        let hidden = arranger.homeView(on: display.uuid).map { $0.collapsed[window] != nil || arranger.isParked(window) } ?? false
        logger.info("pick window \(window.windowID, privacy: .public) on space \(space, privacy: .public) (\(hidden ? "camera move" : "same space", privacy: .public))")
        panels[display.uuid]?.bringToFront(zoom().cgWindow(window) ?? window.windowID)
        dismiss(reason: "pick", announce: false)
        guard hidden else {
            Task { await focusWindow(window) }
            return
        }
        // The camera's stage comes up only once the overview's has gone (reverse animation, then its fade).
        let closing = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? StagePanel.moveDuration : StagePanel.moveDuration + StagePanel.revealFade
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(closing))
            await self?.frameWindow(window, display.uuid)
        }
    }

    /// The stage fades out (120 ms), then the display switches to `space` and `window` gets focus. A switch that does not
    /// land within 1 s beeps and announces (Surface 2); the overview is closed by then.
    private func switchAway(to space: UInt64, on display: String, then window: TransomModel.WindowRef?) {
        fadeAway(log: "dismiss: pick")
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

    /// A placeholder's tile: from its tile on the desk to its main-area rect, drawn as on screen (08 UI-SPEC Surface 2).
    private func placeholder(_ tile: OverviewTile, input: OverviewDisplayInput?, appKit: (Rect) -> CGRect) -> StageTile {
        let real = input?.placeholders.first { $0.window == tile.window }?.frame ?? tile.rect
        return StageTile(id: tile.window.windowID, start: appKit(real), end: appKit(tile.rect), content: PlaceholderLook(bundleID: tile.window.bundleID).content)
    }

    /// A group tile's icon-only strip (07 UI-SPEC Surface 6): from above its window's real frame to above its main-area
    /// rect, 28 pt × the display's scale. Nil for a window in no group. Mini tiles never get one.
    private func strip(_ tile: OverviewTile, scale: Double, arranger: Arranger, appKit: (Rect) -> CGRect) -> StageTile? {
        guard let group = arranger.tabGroupMembers(holding: tile.window) else { return nil }
        let zoom = zoom()
        let real = arranger.windows[tile.window.identity]?.frame ?? tile.rect
        let end = Rect(x: tile.rect.x, y: tile.rect.y - TabBand.height * scale, width: tile.rect.width, height: TabBand.stripHeight * scale)
        return StageTile(
            id: StageTile.stripID(zoom.cgWindow(tile.window) ?? tile.window.windowID), start: appKit(TabBand.strip(of: TabBand.frame(ofContent: real))),
            end: appKit(end), content: zoom.stripContent(group.members, selected: group.selected))
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
                // A hidden tab is never shown, docked or floating (UI-SPEC Surface 3).
                guard info.displayUUID == display.uuid, !info.isExcluded, info.state == .present, !arranger.isHiddenTab(info.window) else { return nil }
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
            var input = OverviewDisplayInput(
                uuid: display.uuid, visibleFrame: display.visibleFrame, isMain: index == 0,
                isFullScreen: list?.spaces.first { $0.id == current }?.kind == .fullScreen, spaces: list?.spaces ?? [], current: current,
                windows: shown.map { OverviewWindow(window: $0.0.window, frame: $0.0.frame) },
                home: (homeView?.frames ?? [:]).merging(homeView?.collapsed ?? [:]) { first, _ in first }, hiddenSpaceWindows: hidden)
            input.placeholders = arranger.homePlaceholders(on: display.uuid).map { OverviewWindow(window: $0.window, frame: $0.frame) }
            return input
        }
    }

    /// A hidden Space's windows: its docked windows at their planned tiles, then its present floaters at their frames.
    private static func plannedWindows(_ arranger: Arranger, key: DeskKey, area: Rect) -> [OverviewWindow] {
        guard let desk = arranger.world[key] else { return [] }
        let planned = (try? Planner.plan(desk: desk, area: area, gap: arranger.gap, mins: [:]).frames) ?? [:]
        // A placeholder is not a window: a mini tile would count and select as one (08 UI-SPEC Surface 2).
        let docked = desk.tree.windows.filter { !arranger.isPlaceholder($0) }.compactMap { window in planned[window].map { OverviewWindow(window: window, frame: $0) } }
        let floating = desk.desktop.windows.filter { $0.state == .present && !arranger.isHiddenTab($0.window) }.compactMap { floater in
            (planned[floater.window] ?? arranger.windows[floater.window.identity]?.frame).map { OverviewWindow(window: floater.window, frame: $0) }
        }
        return docked + floating
    }
}

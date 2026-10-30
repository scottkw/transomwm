import AppKit
import KeyboardShortcuts
import TransomEngine
import TransomModel
import os

/// Pointer input for the camera (04-06, RESEARCH Pattern 7): publishes the tap's `ZoomTapState` and turns the presses
/// `ZoomTapRules` takes into camera moves. Owned by ArrangeController; every action goes through the engine's own
/// `.zoomTo` / `.camera`, so pointer input reuses its targets, toggles and refusals.
@MainActor final class ZoomInput {
    private weak var controller: ArrangeController?
    private let tap: InputTap
    private let log = Logger(subsystem: "com.eightabyte.transom", category: "zoomInput")
    /// The state the tap last got, so an unchanged one is not swapped in again.
    private var published = ZoomTapState()

    /// A ⌘⇧-drag in progress, in global top-left points. `tiles` and `tree` are the view's at mouse-down.
    private struct Band {
        var start: CGPoint
        var flags: CGEventFlags
        var clickState: Int64
        var display: DisplayInfo
        var current: CGPoint
        var tiles: [NodeID: Rect]
        var tree: LayoutTree?
        /// Shown once the pointer has travelled 4 pt; until then the press may still be a ⌘⇧-click.
        var shown = false
        var target: NodeID?
        /// Esc canceled it: the tap still takes the rest of the press, which then does nothing.
        var cancelled = false
    }
    private var band: Band?
    /// A ⌘⇧-drag is in progress: gestures are disarmed meanwhile (UI-SPEC Surface 2).
    var isBandActive: Bool { band != nil }
    /// The temporary Esc hotkeys while a band is active (ZOOM-12). Each stream registers its Carbon hotkey when it
    /// starts and unregisters when its task is cancelled.
    private var bandEscapes: [Task<Void, Never>] = []
    /// Esc with no modifier, ⇧, ⌘ and ⌘⇧ (the user may still hold ⌘⇧). Never with ⌥: ⌥⌘Esc is Force Quit.
    private static let escapeModifiers: [NSEvent.ModifierFlags] = [[], [.shift], [.command], [.command, .shift]]

    /// Pick mode on one display (Surface 5): its window tiles by CG window, the passive hover monitor, the Esc hotkey.
    private struct Pick {
        var displayUUID: String
        var tiles: [UInt32: CGRect]
        /// Collapsed blocks: their windows are parked, so the tap cannot match them; `pointerDown` picks them instead.
        var blocks: [(window: TransomModel.WindowRef, rect: CGRect)] = []
        var monitor: Any?
        var escape: Task<Void, Never>
        var hovered: UInt32?
    }
    private var pick: Pick?
    /// The Zoom Out to All Windows / Zoom Out One Level move whose reveal starts pick mode.
    private var pickMove: UInt64?

    init(controller: ArrangeController, tap: InputTap) {
        self.controller = controller
        self.tap = tap
    }

    /// Hands the tap what the zoom rules read. Called after every Arranger change and whenever zoom, readiness or a
    /// move's progress changes.
    func publish() {
        guard let controller else { return }
        let arranger = controller.arranger
        var state = ZoomTapState()
        state.armed =
            controller.isZoomEnabled && controller.isReady() && arranger.pauseReasons.isEmpty && (controller.zoomController?.isIdle ?? true)
        if state.armed {
            state.deskDisplays = arranger.displays.filter { arranger.world[Self.deskKey($0)] != nil }.map { Self.cgRect($0.frame) }
            state.pickTiles = pick?.tiles
            state.titleBarDoubleClick = UserDefaults.standard.object(forKey: ShortcutsModel.doubleClickKey) as? Bool ?? true
            if state.titleBarDoubleClick { state.titleBars = titleBars(arranger) }
        }
        guard state != published else { return }
        published = state
        tap.setZoomState(state)
    }

    /// Every docked window's title band, by the CG window it shows: from its top edge down to its green button's
    /// bottom, from the frames Transom tracks (no AX). Floating windows keep macOS's own double-click.
    private func titleBars(_ arranger: Arranger) -> [UInt32: CGRect] {
        var bars: [UInt32: CGRect] = [:]
        for info in arranger.windows.values where info.kind == .dockable && !info.isExcluded && info.state == .present {
            guard let button = info.greenButton, let leaf = arranger.leafNode(of: info.window), leaf != .desktop else { continue }
            bars[info.visibleMemberID ?? info.window.windowID] = CGRect(
                x: info.frame.x, y: info.frame.y, width: info.frame.width, height: button.y + button.height)
        }
        return bars
    }

    /// One event of a taken zoom press.
    func tapEvent(_ kind: ZoomTapRules.Kind, _ event: TapEvent) async {
        switch kind {
        case .band:
            if event.type == .leftMouseDown { endPick(reason: "rect zoom") }
            await bandEvent(event)
        case .pick(let id): await pickClick(cgID: id)
        case .titleBarDoubleClick(let id): await titleBarDoubleClick(cgID: id, at: event.location)
        }
    }

    /// A left press the tap let through (or a green-button press): ends a band whose release was lost and pick mode,
    /// and frames the Desktop on a double-click on its wallpaper (ZOOM-11), which is never taken.
    func pointerDown(_ event: TapEvent) {
        endBand()
        if let current = pick, let block = current.blocks.first(where: { $0.rect.contains(event.location) }) {
            endPick(reason: "picked")
            log.info("\(ZoomCopy.logPick(block.window.windowID), privacy: .public)")
            Task { await zoom(toLeafOf: block.window, displayUUID: current.displayUUID) }
            return
        }
        endPick(reason: "click")
        guard event.clickState == 2, published.armed else { return }
        // Its own task: Finder's hit test must not hold up the Arranger's view of this press.
        Task { await desktopDoubleClick(at: event.location) }
    }

    private func desktopDoubleClick(at location: CGPoint) async {
        guard let controller else { return }
        let point = Point(x: location.x, y: location.y)
        let arranger = controller.arranger
        guard let display = arranger.displays.first(where: { $0.frame.contains(point) }),
            let desktop = (try? arranger.shownLeafRects(displayUUID: display.uuid))?[.desktop], desktop.contains(point),
            CGWindowList.topmostWindow(at: point) == nil  // wallpaper, not a window over the Desktop tile
        else { return }
        let finder = NSRunningApplication.runningApplications(withBundleIdentifier: Arranger.finderBundleID).first?.processIdentifier
        // Off the tap and off main: Finder's hit test may take up to its 0.25 s timeout.
        let hit = await Task.detached { finder.flatMap { Self.finderElement(at: location, pid: $0) } }.value
        if let hit { log.debug("desktop double-click hit \(hit.role, privacy: .public) / \(hit.subrole ?? "-", privacy: .public)") }
        guard !Self.isDesktopItem(hit) else { return }  // a desktop icon only opens
        log.info("\(ZoomCopy.logDesktopDoubleClick, privacy: .public)")
        await controller.camera(.frameDesktop, displayUUID: display.uuid, focused: nil, pointer: point)
    }

    /// A title-bar double-click on a docked window (ZOOM-10): frame it, or go back when it is framed (the engine toggles).
    private func titleBarDoubleClick(cgID: UInt32, at location: CGPoint) async {
        guard let controller, let window = controller.trackedWindow(cgID: cgID) else { return }
        let point = Point(x: location.x, y: location.y)
        guard let uuid = controller.arranger.windows[window.identity]?.displayUUID ?? controller.pointerDisplay().uuid else { return }
        log.info("\(ZoomCopy.logTitleBarDoubleClick(window.windowID), privacy: .public)")
        await controller.camera(.frameWindow, displayUUID: uuid, focused: window, pointer: point)
    }

    // MARK: Pick mode (Surface 5)

    /// Any Transom command ends pick mode and forgets a pending zoom-out.
    func noteCommand() {
        endPick(reason: "command")
        pickMove = nil
    }

    /// The camera command that made `moveID` was Zoom Out to All Windows or Zoom Out One Level.
    func expectPick(moveID: UInt64) {
        pickMove = moveID
    }

    /// A move revealed: pick mode starts when it was the expected zoom-out and the new view holds more than one window.
    func revealed(displayUUID uuid: String, move: CameraMove) {
        guard let expected = pickMove, expected == move.id else { return }
        pickMove = nil
        let shown = move.tiles.filter { $0.kind != .leaving }
        guard shown.count > 1, let controller else { return }
        let arranger = controller.arranger
        var tiles: [UInt32: CGRect] = [:]
        var blocks: [(window: TransomModel.WindowRef, rect: CGRect)] = []
        for tile in shown {
            if tile.kind == .collapsed {
                blocks.append((tile.window, Self.cgRect(tile.end)))
                continue
            }
            guard let info = arranger.windows[tile.window.identity], let leaf = arranger.leafNode(of: tile.window), leaf != .desktop else { continue }
            tiles[info.visibleMemberID ?? tile.window.windowID] = Self.cgRect(tile.end)
        }
        endPick(reason: "new pick")
        let monitor = NSEvent.addGlobalMonitorForEvents(matching: .mouseMoved) { [weak self] _ in
            MainActor.assumeIsolated { self?.hover() }
        }
        let escape = Task { [weak self] in
            for await key in KeyboardShortcuts.events(for: KeyboardShortcuts.Shortcut(.escape)) where key == .keyDown {
                self?.endPick(reason: "Esc")
            }
        }
        pick = Pick(displayUUID: uuid, tiles: tiles, blocks: blocks, monitor: monitor, escape: escape)
        log.info("\(ZoomCopy.logPickOn, privacy: .public)")
        publish()
        hover()
    }

    /// The hover ring follows the tile under the pointer; none over the Desktop tile, gaps, the menu bar or the Dock.
    private func hover() {
        guard var current = pick, let controller else { return }
        let point = controller.pointerDisplay().point
        let hovered = current.tiles.first { $0.value.contains(CGPoint(x: point.x, y: point.y)) }
        guard hovered?.key != current.hovered else { return }
        current.hovered = hovered?.key
        pick = current
        if let rect = hovered?.value {
            controller.previews?.showPickRing(
                Rect(x: rect.minX, y: rect.minY, width: rect.width, height: rect.height), radius: TileLayer.cornerRadius, on: current.displayUUID)
        } else {
            controller.previews?.hidePickRing(on: current.displayUUID)
        }
    }

    /// Ends pick mode: the monitor, the Esc hotkey, the ring and the published tiles all go.
    func endPick(reason: String) {
        guard let current = pick else { return }
        pick = nil
        if let monitor = current.monitor { NSEvent.removeMonitor(monitor) }
        current.escape.cancel()
        controller?.previews?.hidePickRing(on: current.displayUUID)
        log.info("\(ZoomCopy.logPickOff(reason), privacy: .public)")
        publish()
    }

    /// A pick click on a docked window: zoom to its leaf and focus it once the move settles.
    private func pickClick(cgID: UInt32) async {
        guard let uuid = pick?.displayUUID else { return }
        endPick(reason: "picked")
        guard let window = controller?.trackedWindow(cgID: cgID) else { return }
        log.info("\(ZoomCopy.logPick(window.windowID), privacy: .public)")
        await zoom(toLeafOf: window, displayUUID: uuid)
    }

    /// A click on a stage tile while the stage is up (any mode): retargets the move to that window's leaf, focused at
    /// settle. The backdrop swallows its own clicks.
    func stageClick(cgID: UInt32, displayUUID uuid: String) async {
        guard let window = controller?.trackedWindow(cgID: cgID) else { return }
        await zoom(toLeafOf: window, displayUUID: uuid)
    }

    func zoom(toLeafOf window: TransomModel.WindowRef, displayUUID uuid: String) async {
        guard let controller, let leaf = controller.arranger.leafNode(of: window), leaf != .desktop,
            let tree = controller.arranger.deskKey(of: window).flatMap({ controller.arranger.world[$0]?.tree })
        else { return }
        await controller.zoom(to: Navigator.target(leaf, in: tree), displayUUID: uuid, focus: window)
    }

    // MARK: Rubber band (Surface 4)

    private func bandEvent(_ event: TapEvent) async {
        switch event.type {
        case .leftMouseDown:
            endBand()  // a press whose release was lost
            guard let controller, let display = controller.arranger.displays.first(where: { Self.cgRect($0.frame).contains(event.location) })
            else { return }
            let arranger = controller.arranger
            var tiles: [NodeID: Rect] = [:]
            do {
                tiles = try arranger.shownLeafRects(displayUUID: display.uuid)
            } catch {
                log.error("rect zoom: no tiles on display \(display.uuid, privacy: .public): \(String(describing: error), privacy: .public)")
            }
            band = Band(
                start: event.location, flags: event.flags, clickState: event.clickState, display: display, current: event.location, tiles: tiles,
                tree: arranger.world[Self.deskKey(display)]?.tree)
            controller.gestures.publish()
            bandEscapes = Self.escapeModifiers.map { modifiers in
                Task { [weak self] in
                    for await key in KeyboardShortcuts.events(for: KeyboardShortcuts.Shortcut(.escape, modifiers: modifiers)) where key == .keyDown {
                        self?.cancelBand()
                    }
                }
            }
        case .leftMouseDragged:
            guard var current = band, !current.cancelled else { return }
            current.current = Self.clamp(event.location, to: current.display.frame)
            current.shown = current.shown || !Self.isClick(start: current.start, end: current.current)
            band = current
            if current.shown { drawBand() }
        case .leftMouseUp:
            guard var current = band else { return }
            endBand()
            guard !current.cancelled else { return }
            current.current = Self.clamp(event.location, to: current.display.frame)
            guard current.shown || !Self.isClick(start: current.start, end: current.current) else { return repost(current) }
            let rect = Self.bandRect(current.start, current.current)
            guard let tree = current.tree, let target = Navigator.rectTarget(band: rect, tiles: current.tiles, tree: tree) else {
                log.info("\(ZoomCopy.logRectNoTarget, privacy: .public)")  // a marquee over nothing: no move, no beep
                return
            }
            log.info("\(ZoomCopy.logRectZoom(String(describing: target)), privacy: .public)")
            await controller?.zoom(to: Navigator.target(target, in: tree), displayUUID: current.display.uuid)
        default:
            break
        }
    }

    /// The band and, when its target node changes, the target preview.
    private func drawBand() {
        guard var current = band else { return }
        let rect = Self.bandRect(current.start, current.current)
        current.target = current.tree.flatMap { Navigator.rectTarget(band: rect, tiles: current.tiles, tree: $0) }
        band = current
        let targetRect = current.target.flatMap { target in current.tree.flatMap { Self.rect(of: target, tiles: current.tiles, tree: $0) } }
        controller?.previews?.showBand(rect, target: targetRect, on: current.display.uuid)
    }

    /// Esc during the band (ZOOM-12): no move, the band fades out, "Zoom canceled". The tap still takes the rest of the
    /// press, so no click reaches an app.
    private func cancelBand() {
        guard var current = band, !current.cancelled else { return }
        current.cancelled = true
        band = current
        stopEscapes()
        controller?.previews?.hideBand(on: current.display.uuid)
        postAnnouncement(ZoomCopy.zoomCanceled)
        log.info("\(ZoomCopy.logRectCanceled, privacy: .public)")
    }

    /// The band is over: its drawing fades and its Esc hotkeys go.
    private func endBand() {
        guard let current = band else { return }
        band = nil
        controller?.gestures.publish()
        stopEscapes()
        controller?.previews?.hideBand(on: current.display.uuid)
    }

    private func stopEscapes() {
        for task in bandEscapes { task.cancel() }
        bandEscapes = []
    }

    /// A ⌘⇧-click (Pitfall 10): the exact press, re-posted at its point and flags, tagged so the tap lets it through.
    private func repost(_ press: Band) {
        for type in [CGEventType.leftMouseDown, .leftMouseUp] {
            guard let event = CGEvent(mouseEventSource: nil, mouseType: type, mouseCursorPosition: press.start, mouseButton: .left) else { continue }
            event.flags = press.flags
            event.setIntegerValueField(.mouseEventClickState, value: max(press.clickState, 1))
            event.setIntegerValueField(.eventSourceUserData, value: ZoomTapRules.repostTag)
            event.post(tap: .cgSessionEventTap)
        }
        log.info("\(ZoomCopy.logRepost, privacy: .public)")
    }

    /// The tap went down, Accessibility left or zoom turned off: nothing of a press or of pick mode may linger.
    func reset(reason: String) {
        endBand()
        endPick(reason: reason)
        pickMove = nil
    }

    // MARK: Desktop hit test (A4)

    /// Finder's AX element at `point`: its role and subrole. Nil when Finder has nothing there.
    nonisolated private static func finderElement(at point: CGPoint, pid: pid_t) -> (role: String, subrole: String?)? {
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, 0.25)
        var element: AXUIElement?
        guard AXUIElementCopyElementAtPosition(app, Float(point.x), Float(point.y), &element) == .success, let element else { return nil }
        func string(_ attribute: String) -> String? {
            var value: CFTypeRef?
            return AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success ? value as? String : nil
        }
        return string(kAXRoleAttribute).map { ($0, string(kAXSubroleAttribute)) }
    }

    /// Whether the hit is a desktop icon (or its label) rather than bare wallpaper. Only the desktop's own containers
    /// count as wallpaper, so an unknown role is treated as an icon and never frames (RESEARCH A4, unverified: UAT).
    nonisolated static func isDesktopItem(_ hit: (role: String, subrole: String?)?) -> Bool {
        guard let hit else { return false }
        return ![kAXScrollAreaRole, kAXGroupRole, kAXWindowRole, kAXApplicationRole].contains(hit.role)
    }

    // MARK: Pure helpers

    /// The on-screen rect of `node`: the union of its leaves' tiles.
    nonisolated static func rect(of node: NodeID, tiles: [NodeID: Rect], tree: LayoutTree) -> Rect? {
        let rects = tiles.filter { Navigator.ancestors(of: $0.key, in: tree).contains(node) }.values
        guard let minX = rects.map(\.minX).min(), let minY = rects.map(\.minY).min(), let maxX = rects.map(\.maxX).max(),
            let maxY = rects.map(\.maxY).max()
        else { return nil }
        return Rect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }

    /// A ⌘⇧ press that travelled under 4 pt is a click, not a band.
    nonisolated static func isClick(start: CGPoint, end: CGPoint) -> Bool {
        hypot(end.x - start.x, end.y - start.y) < 4
    }

    /// `point` held inside `frame` (the display where the drag began).
    nonisolated static func clamp(_ point: CGPoint, to frame: Rect) -> CGPoint {
        CGPoint(x: min(max(point.x, frame.minX), frame.maxX), y: min(max(point.y, frame.minY), frame.maxY))
    }

    /// The rect from mouse-down to the pointer.
    nonisolated static func bandRect(_ a: CGPoint, _ b: CGPoint) -> Rect {
        Rect(x: min(a.x, b.x), y: min(a.y, b.y), width: abs(b.x - a.x), height: abs(b.y - a.y))
    }

    nonisolated static func cgRect(_ rect: Rect) -> CGRect { CGRect(x: rect.x, y: rect.y, width: rect.width, height: rect.height) }

    /// The desk shown on `display` (the engine's `Arranger.key`).
    nonisolated static func deskKey(_ display: DisplayInfo) -> DeskKey {
        DeskKey(displayUUID: display.uuid, spaceID: display.currentSpaceID)
    }
}

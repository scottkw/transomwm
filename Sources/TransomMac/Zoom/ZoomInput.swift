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
    /// The temporary Esc hotkeys while a band is active (ZOOM-12). Each stream registers its Carbon hotkey when it
    /// starts and unregisters when its task is cancelled.
    private var bandEscapes: [Task<Void, Never>] = []
    /// Esc with no modifier, ⇧, ⌘ and ⌘⇧ (the user may still hold ⌘⇧). Never with ⌥: ⌥⌘Esc is Force Quit.
    private static let escapeModifiers: [NSEvent.ModifierFlags] = [[], [.shift], [.command], [.command, .shift]]

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
        }
        guard state != published else { return }
        published = state
        tap.setZoomState(state)
    }

    /// One event of a taken zoom press.
    func tapEvent(_ kind: ZoomTapRules.Kind, _ event: TapEvent) async {
        switch kind {
        case .band: await bandEvent(event)
        case .pick, .titleBarDoubleClick: break
        }
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

    /// The tap went down or Accessibility left: nothing of a press may linger.
    func reset() {
        endBand()
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
    nonisolated private static func deskKey(_ display: DisplayInfo) -> DeskKey {
        DeskKey(displayUUID: display.uuid, spaceID: display.currentSpaceID)
    }
}

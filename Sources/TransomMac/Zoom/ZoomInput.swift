import AppKit
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
    }
    private var band: Band?

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
            band = nil
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
        case .leftMouseDragged:
            guard var current = band else { return }
            current.current = Self.clamp(event.location, to: current.display.frame)
            band = current
        case .leftMouseUp:
            guard var current = band else { return }
            band = nil
            current.current = Self.clamp(event.location, to: current.display.frame)
            guard !Self.isClick(start: current.start, end: current.current) else { return }
            let rect = Self.bandRect(current.start, current.current)
            guard let tree = current.tree, let target = Navigator.rectTarget(band: rect, tiles: current.tiles, tree: tree) else {
                log.info("rect zoom: no target")  // a marquee over nothing: no move, no beep
                return
            }
            log.info("rect zoom → \(String(describing: target), privacy: .public)")
            await controller?.zoom(to: Navigator.target(target, in: tree), displayUUID: current.display.uuid)
        default:
            break
        }
    }

    // MARK: Pure helpers

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

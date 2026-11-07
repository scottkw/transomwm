import AppKit
import TransomEngine
import TransomModel
import QuartzCore

/// Never key or main: clicking or dragging a handle leaves the frontmost app frontmost (UI-SPEC Surface 3).
private final class HandlePanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

/// One gap strip: invisible at rest, the accent at 50% on hover and 85% while dragged. Hover and the cursor come from
/// an always-active tracking area with `NSCursor.set()`, since macOS sends such an area no cursor-update events (RESEARCH Pattern 8).
/// If macOS keeps the arrow while Transom is inactive, the highlight and the drag still work (A5).
private final class HandleView: NSView {
    var handle: GapHandle
    var onDrag: ((GapHandle, Double, Bool) -> Void)?
    private var hovering = false
    /// The pointer at mouse-down (AppKit screen points) and the handle's rect then; nil when not dragging.
    private var press: (point: NSPoint, rect: Rect)?
    private var delta = 0.0

    init(_ handle: GapHandle) {
        self.handle = handle
        super.init(frame: .zero)
        wantsLayer = true
        layer?.opacity = 0
        setAccessibilityElement(false)
    }

    @available(*, unavailable) required init?(coder: NSCoder) { fatalError("not used") }

    override var wantsUpdateLayer: Bool { true }

    /// Re-resolved in the current appearance, so the accent and dark mode follow.
    override func updateLayer() {
        layer?.backgroundColor = HighlightColor.current.cgColor
        layer?.cornerRadius = min(min(bounds.width, bounds.height) / 2, 4)
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .mouseMoved, .activeAlways, .inVisibleRect], owner: self))
    }

    override func mouseEntered(with event: NSEvent) {
        hovering = true
        cursor.set()
        if press == nil { fade(to: 0.5, over: 0.08) }
    }

    override func mouseMoved(with event: NSEvent) { cursor.set() }

    override func mouseExited(with event: NSEvent) {
        hovering = false
        if press == nil { fade(to: 0, over: 0.12) }
    }

    override func mouseDown(with event: NSEvent) {
        press = (NSEvent.mouseLocation, handle.rect)
        delta = 0
        fade(to: 0.85, over: 0)
        cursor.set()
    }

    override func mouseDragged(with event: NSEvent) {
        guard let press else { return }
        let now = NSEvent.mouseLocation
        // Top-left points: x grows right, y grows down (AppKit's y grows up).
        delta = handle.axis == .horizontal ? now.x - press.point.x : press.point.y - now.y
        onDrag?(handle, delta, false)
        cursor.set()
    }

    override func mouseUp(with event: NSEvent) {
        guard press != nil else { return }
        onDrag?(handle, delta, true)
        press = nil
        fade(to: hovering ? 0.5 : 0, over: hovering ? 0 : 0.12)
        cursor.set()
    }

    /// Left-right or up-down; while dragging, the single-direction cursor once the strip has stopped short of the
    /// pointer (one side is at its minimum).
    private var cursor: NSCursor {
        let horizontal = handle.axis == .horizontal
        guard let press else { return Self.cursor(horizontal: horizontal, toward: nil) }
        let moved = horizontal ? handle.rect.minX - press.rect.minX : handle.rect.minY - press.rect.minY
        guard abs(delta - moved) > 1 else { return Self.cursor(horizontal: horizontal, toward: nil) }
        // Past the limit the strip only goes back the other way.
        return Self.cursor(horizontal: horizontal, toward: delta > moved ? .leading : .trailing)
    }

    private enum Way { case leading, trailing }

    private static func cursor(horizontal: Bool, toward way: Way?) -> NSCursor {
        if #available(macOS 15, *) {
            switch (horizontal, way) {
            case (true, nil): return .columnResize
            case (true, .leading?): return .columnResize(directions: .left)
            case (true, .trailing?): return .columnResize(directions: .right)
            case (false, nil): return .rowResize
            case (false, .leading?): return .rowResize(directions: .up)
            case (false, .trailing?): return .rowResize(directions: .down)
            }
        }
        switch (horizontal, way) {
        case (true, nil): return .resizeLeftRight
        case (true, .leading?): return .resizeLeft
        case (true, .trailing?): return .resizeRight
        case (false, nil): return .resizeUpDown
        case (false, .leading?): return .resizeUp
        case (false, .trailing?): return .resizeDown
        }
    }

    private func fade(to opacity: Float, over duration: Double) {
        guard let layer else { return }
        let animation = CABasicAnimation(keyPath: "opacity")
        animation.fromValue = layer.presentation()?.opacity ?? layer.opacity
        animation.toValue = opacity
        animation.duration = duration
        layer.opacity = opacity
        layer.add(animation, forKey: "fade")
    }
}

/// The gap handles (TILE-05, UI-SPEC Surface 3): one borderless, non-activating panel per handle, recycled through a
/// pool, at floating level on every Space and excluded from capture. A handle covers only the gap, so taking its
/// clicks steals nothing from an app. Drags go to `onDrag` as points along the handle's axis since the press, which
/// ArrangeController feeds to the Arranger as `.gapDrag`; mouse-up is `ended`, the one `World.edit`.
@MainActor final class GapHandlePanels {
    var onDrag: ((GapHandle, Double, Bool) -> Void)?
    private var shown: [String: [HandlePanel]] = [:]
    private var pool: [HandlePanel] = []
    private var observers: [NSObjectProtocol] = []

    init() {
        let redraw: @Sendable (Notification) -> Void = { [weak self] _ in
            MainActor.assumeIsolated {
                for panel in self?.shown.values.flatMap({ $0 }) ?? [] { panel.contentView?.needsDisplay = true }
            }
        }
        // The accent changed, or the user's highlight override did.
        observers = [NSColor.systemColorsDidChangeNotification, HighlightColor.didChange].map {
            NotificationCenter.default.addObserver(forName: $0, object: nil, queue: .main, using: redraw)
        }
    }

    /// Shows exactly `handles` on that display. A panel keeps its handle (split and children) across updates, so a
    /// handle being dragged follows the gap and keeps its drag.
    func show(_ handles: [GapHandle], on displayUUID: String) {
        var old = shown[displayUUID] ?? []
        var next: [HandlePanel] = []
        let primaryHeight = NSScreen.screens.first?.frame.height ?? 0
        for handle in handles {
            let same = { (panel: HandlePanel) in Self.view(panel).map { Self.sameGap($0.handle, handle) } ?? false }
            var panel = old.firstIndex(where: same).map { old.remove(at: $0) } ?? pool.popLast() ?? makePanel(handle)
            if panel.leftOnAnotherSpace("display \(displayUUID): gap handle panel") {
                panel.orderOut(nil)
                panel = makePanel(handle)
            }
            Self.view(panel)?.handle = handle
            let rect = Coordinates.appKit(fromTopLeft: handle.rect, primaryHeight: primaryHeight)
            panel.setFrame(NSRect(x: rect.x, y: rect.y, width: rect.width, height: rect.height), display: true)
            panel.orderFrontRegardless()
            next.append(panel)
        }
        for panel in old { panel.orderOut(nil) }
        pool += old
        shown[displayUUID] = next
    }

    private func makePanel(_ handle: GapHandle) -> HandlePanel {
        let panel = HandlePanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        panel.ignoresMouseEvents = false
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        panel.sharingType = .none
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.animationBehavior = .none
        panel.hidesOnDeactivate = false
        panel.setAccessibilityElement(false)
        let view = HandleView(handle)
        view.onDrag = { [weak self] handle, delta, ended in self?.onDrag?(handle, delta, ended) }
        panel.contentView = view
        return panel
    }

    private static func view(_ panel: HandlePanel) -> HandleView? { panel.contentView as? HandleView }

    private static func sameGap(_ a: GapHandle, _ b: GapHandle) -> Bool {
        a.split == b.split && a.first == b.first && a.second == b.second
    }
}

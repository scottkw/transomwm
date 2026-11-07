import AppKit
import QuartzCore
import TransomEngine
import TransomModel

/// Never key or main: a click on a block leaves the frontmost app frontmost and never activates Transom.
private final class BlockPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

/// One collapsed block at rest (UI-SPEC Surface 3): app-colour fill, radius min(12, shorter side / 2), 1 pt separator
/// border, the app icon at min(32, shorter side - 8) hidden below 16, no title. Hover adds a 2 pt accent ring and the
/// pointing hand; a double-click zooms in.
final class CollapsedBlockView: NSView {
    var block: CollapsedBlock {
        didSet { needsDisplay = true }
    }
    var onDoubleClick: ((TransomModel.WindowRef) -> Void)?
    private let icon = CALayer()
    private let ring = CALayer()

    init(_ block: CollapsedBlock) {
        self.block = block
        super.init(frame: .zero)
        wantsLayer = true
        ring.opacity = 0
        ring.borderWidth = 2
        layer?.addSublayer(icon)
        layer?.addSublayer(ring)
    }

    @available(*, unavailable) required init?(coder: NSCoder) { fatalError("not used") }

    // MARK: Accessibility (UI-SPEC Accessibility): a button that zooms in when pressed.

    nonisolated static let help = "Double-click to zoom in"

    /// "“{App}”, collapsed: {title}", the app name only when the title is empty; long app names truncated.
    nonisolated static func label(appName: String, title: String) -> String {
        let app = "\u{201C}\(MenuCopy.truncatedAppName(appName))\u{201D}, collapsed"
        return title.isEmpty ? app : "\(app): \(title)"
    }

    override func isAccessibilityElement() -> Bool { true }
    override func accessibilityRole() -> NSAccessibility.Role? { .button }
    override func accessibilityHelp() -> String? { Self.help }

    override func accessibilityLabel() -> String? {
        let name = NSRunningApplication(processIdentifier: block.window.pid)?.localizedName ?? block.window.bundleID
        guard block.groupSize > 1 else { return Self.label(appName: name, title: block.window.titleHint) }
        return TabCopy.collapsedGroupLabel(count: block.groupSize, app: name, title: block.window.titleHint)
    }

    override func accessibilityPerformPress() -> Bool {
        onDoubleClick?(block.window)
        return true
    }

    override var wantsUpdateLayer: Bool { true }

    /// Re-resolved in the current appearance, so dark mode, the accent and Increase Contrast follow.
    override func updateLayer() {
        guard let layer else { return }
        let app = NSRunningApplication(processIdentifier: block.window.pid)
        let shorter = min(bounds.width, bounds.height)
        let radius = min(TileLayer.cornerRadius, shorter / 2)
        let side = min(32, shorter - 8)
        let contrast = NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer.backgroundColor = AppColor.color(forBundleID: block.window.bundleID, icon: app?.icon).cgColor
        layer.cornerRadius = radius
        layer.borderWidth = 1
        layer.borderColor = NSColor.separatorColor.cgColor
        ring.frame = bounds
        ring.cornerRadius = radius
        ring.borderColor = HighlightColor.current.withAlphaComponent(contrast ? 1 : 0.85).cgColor
        icon.isHidden = side < TileLayer.minIcon || app?.icon == nil
        icon.frame = CGRect(x: (bounds.width - side) / 2, y: (bounds.height - side) / 2, width: max(side, 0), height: max(side, 0))
        icon.contents = app?.icon?.layerContents(forContentsScale: window?.backingScaleFactor ?? 2)
        icon.contentsGravity = .resizeAspect
        CATransaction.commit()
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .cursorUpdate, .activeAlways, .inVisibleRect], owner: self))
    }

    override func mouseEntered(with event: NSEvent) {
        NSCursor.pointingHand.set()
        fadeRing(to: 1, over: 0.08)
    }

    override func cursorUpdate(with event: NSEvent) { NSCursor.pointingHand.set() }

    override func mouseExited(with event: NSEvent) {
        fadeRing(to: 0, over: 0.12)
    }

    /// A single click does nothing here: pick mode's click is taken from the event tap (ZoomInput.pointerDown).
    override func mouseDown(with event: NSEvent) {
        if event.clickCount == 2 { onDoubleClick?(block.window) }
    }

    func resetHover() { fadeRing(to: 0, over: 0) }

    private func fadeRing(to opacity: Float, over duration: Double) {
        let animation = CABasicAnimation(keyPath: "opacity")
        animation.fromValue = ring.presentation()?.opacity ?? ring.opacity
        animation.toValue = opacity
        animation.duration = duration
        ring.opacity = opacity
        ring.add(animation, forKey: "fade")
    }
}

/// The collapsed-block panels (ZOOM-13, UI-SPEC Surface 3): one borderless, non-activating panel per collapsed tile,
/// recycled through a pool (the gap-handle pattern), at floating level on every Space and excluded from capture. A
/// panel covers exactly its tile, which would otherwise be bare wallpaper, so it steals no click from an app. A camera
/// move orders a display's panels out (the stage draws the blocks); its reveal fades them in over 120 ms.
@MainActor final class CollapsedPanels {
    var onDoubleClick: ((TransomModel.WindowRef, _ displayUUID: String) -> Void)?
    private var shown: [String: [BlockPanel]] = [:]
    private var pool: [BlockPanel] = []
    /// Displays whose move has not revealed yet: their panels are placed but stay out.
    private var hidden: Set<String> = []
    private var observers: [(NotificationCenter, NSObjectProtocol)] = []

    init() {
        let center = NotificationCenter.default, workspace = NSWorkspace.shared.notificationCenter
        let redraw: @Sendable (Notification) -> Void = { [weak self] _ in
            MainActor.assumeIsolated {
                for panel in self?.shown.values.flatMap({ $0 }) ?? [] { panel.contentView?.needsDisplay = true }
            }
        }
        observers = [
            (center, center.addObserver(forName: NSColor.systemColorsDidChangeNotification, object: nil, queue: .main, using: redraw)),
            (center, center.addObserver(forName: HighlightColor.didChange, object: nil, queue: .main, using: redraw)),
            (workspace, workspace.addObserver(forName: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification, object: nil, queue: .main, using: redraw)),
        ]
    }

    /// Shows exactly `blocks` on that display; empty hides them.
    func show(_ blocks: [CollapsedBlock], on displayUUID: String) {
        var old = shown[displayUUID] ?? []
        var next: [BlockPanel] = []
        let primaryHeight = NSScreen.screens.first?.frame.height ?? 0
        for block in blocks {
            let found = old.firstIndex { Self.view($0)?.block.window == block.window }.map { old.remove(at: $0) } ?? pool.popLast() ?? makePanel(block)
            let panel = onShownSpace(found, displayUUID)
            if let view = Self.view(panel) {
                view.block = block
                view.onDoubleClick = { [weak self] window in self?.onDoubleClick?(window, displayUUID) }
            }
            let rect = Coordinates.appKit(fromTopLeft: block.rect, primaryHeight: primaryHeight)
            panel.setFrame(NSRect(x: rect.x, y: rect.y, width: rect.width, height: rect.height), display: true)
            if !hidden.contains(displayUUID) {
                panel.alphaValue = 1
                panel.orderFrontRegardless()
            }
            next.append(panel)
        }
        for panel in old {
            panel.orderOut(nil)
            Self.view(panel)?.resetHover()
        }
        pool += old
        shown[displayUUID] = next.isEmpty ? nil : next
        if blocks.isEmpty { hidden.remove(displayUUID) }  // nothing waits for a reveal that may never come
    }

    /// A camera move started on that display.
    func hide(on displayUUID: String) {
        hidden.insert(displayUUID)
        for panel in shown[displayUUID] ?? [] { panel.orderOut(nil) }
    }

    /// That display's move revealed: its panels fade in over 120 ms (UI-SPEC Surface 1 step 7).
    func fadeIn(on displayUUID: String) {
        guard hidden.remove(displayUUID) != nil else { return }
        shown[displayUUID] = shown[displayUUID]?.map { onShownSpace($0, displayUUID) }
        for panel in shown[displayUUID] ?? [] {
            panel.alphaValue = 0
            panel.orderFrontRegardless()
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.12
                panel.animator().alphaValue = 1
            }
        }
    }

    private func makePanel(_ block: CollapsedBlock) -> BlockPanel {
        let panel = BlockPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        panel.ignoresMouseEvents = false
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        panel.sharingType = .none
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.animationBehavior = .none
        panel.hidesOnDeactivate = false
        panel.contentView = CollapsedBlockView(block)
        return panel
    }

    /// `panel`, or a new one with its block, handler and frame when macOS left it on another Space (`leftOnAnotherSpace`).
    private func onShownSpace(_ panel: BlockPanel, _ displayUUID: String) -> BlockPanel {
        guard let view = Self.view(panel), panel.leftOnAnotherSpace("display \(displayUUID): collapsed block panel") else { return panel }
        panel.orderOut(nil)
        let new = makePanel(view.block)
        Self.view(new)?.onDoubleClick = view.onDoubleClick
        new.setFrame(panel.frame, display: false)
        return new
    }

    private static func view(_ panel: BlockPanel) -> CollapsedBlockView? { panel.contentView as? CollapsedBlockView }
}

import AppKit
import TransomEngine
import TransomModel
import QuartzCore

/// Never key or main, so a preview can never take focus or input meant for the app being dragged (T-03-31).
private final class PreviewPanelWindow: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

/// The panel's content view: it tells the presenter when the appearance changes, because CGColors do not follow it.
private final class PreviewContentView: NSView {
    var onAppearanceChange: (() -> Void)?

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        onAppearanceChange?()
    }
}

/// The capsule label (UI-SPEC overlay label): glyph, 4 pt, text, with 8/4 pt padding, a `windowBackgroundColor` fill
/// and a 1 pt `separatorColor` border.
private final class PreviewLabelView: NSView {
    private let text = NSTextField(labelWithString: "")
    private let glyph = NSImageView()
    private let stack: NSStackView

    init(_ label: PreviewStyle.Label, glyphColor: NSColor) {
        text.stringValue = label.text
        text.font = NSFont.preferredFont(forTextStyle: .headline)
        text.textColor = .labelColor
        if let name = label.glyph {
            glyph.image = NSImage(systemSymbolName: name, accessibilityDescription: nil)?
                .withSymbolConfiguration(NSImage.SymbolConfiguration(textStyle: .headline))
            glyph.contentTintColor = glyphColor
        }
        stack = NSStackView(views: label.glyph == nil ? [text] : [glyph, text])
        stack.orientation = .horizontal
        stack.spacing = 4
        stack.edgeInsets = NSEdgeInsets(top: 4, left: 8, bottom: 4, right: 8)
        super.init(frame: .zero)
        addSubview(stack)
        wantsLayer = true
        setAccessibilityElement(false)
        frame.size = stack.fittingSize
        stack.frame = bounds
    }

    @available(*, unavailable) required init?(coder: NSCoder) { fatalError("not used") }

    /// Re-resolves the capsule's layer colours in the current appearance.
    func resolveColors() {
        effectiveAppearance.performAsCurrentDrawingAppearance {
            layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
            layer?.borderColor = NSColor.separatorColor.cgColor
        }
        layer?.borderWidth = 1
        layer?.cornerRadius = bounds.height / 2
    }
}

/// The drop preview (UI-SPEC Surface 2): one borderless, non-activating, click-through panel per display, created at
/// launch and when displays change, covering that display's frame, on every Space and excluded from screen capture. It
/// needs no Screen Recording permission (TILE-10). Preview rects are CAShapeLayers styled by `PreviewStyle`.
@MainActor final class PreviewPresenter {
    private struct Overlay {
        let panel: PreviewPanelWindow
        let view: PreviewContentView
        let root: CALayer
        /// The panel's frame in AppKit coordinates.
        let frame: NSRect
    }

    private var overlays: [String: Overlay] = [:]
    private var shown: (state: PreviewState, display: String)?
    /// Bumped by every show and hide, so a fade that finishes after a newer change does not order a panel out.
    private var generation = 0
    private var reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    private var increaseContrast = NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast
    private var observers: [(NotificationCenter, NSObjectProtocol)] = []

    init() {
        rebuildPanels()
        let center = NotificationCenter.default, workspace = NSWorkspace.shared.notificationCenter
        observers = [
            (center, center.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.rebuildPanels() }
            }),
            // The user changed the accent colour.
            (center, center.addObserver(forName: NSColor.systemColorsDidChangeNotification, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.redraw() }
            }),
            (workspace, workspace.addObserver(forName: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated {
                    guard let self else { return }
                    self.reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
                    self.increaseContrast = NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast
                    self.redraw()
                }
            }),
        ]
    }

    /// Shows `state` on `displayUUID`'s panel, or withdraws the preview (nil). The panel is ordered front when a preview
    /// first shows and ordered out once it has faded.
    func show(_ state: PreviewState?, on displayUUID: String?) {
        guard let state, let uuid = displayUUID, let overlay = overlays[uuid] else {
            hide(after: 0.08)
            return
        }
        generation += 1
        let previous = shown?.display == uuid ? shown?.state : nil
        if let old = shown, old.display != uuid { overlays[old.display]?.panel.orderOut(nil) }
        shown = (state, uuid)
        switch previous {
        case nil:
            draw(state, in: overlay)
            fadeIn(overlay, duration: 0.12)
        case let previous? where Self.sameKind(previous, state):
            if case .clamp = state {
                draw(state, in: overlay)  // follows the dragged window, so no easing
            } else if reduceMotion {
                draw(state, in: overlay)
                fadeIn(overlay, duration: 0.12)  // no morph: the new rect fades in
            } else {
                morph(overlay, to: state)
            }
        case _?:
            let fade = CATransition()
            fade.type = .fade
            fade.duration = 0.08
            overlay.root.add(fade, forKey: "crossfade")
            draw(state, in: overlay)
        }
    }

    /// Re-orders the shown preview's panel above a panel at the same level that just ordered in (the camera stage).
    func bringFront() {
        if let display = shown?.display { overlays[display]?.panel.orderFrontRegardless() }
    }

    /// Keyboard parity: the blocked preview at `rect` for 600 ms (fade in 120 ms, hold, fade out 120 ms).
    func flashBlocked(_ rect: Rect, on displayUUID: String) {
        guard shown == nil, let overlay = overlays[displayUUID] else { return }
        generation += 1
        let flash = generation
        draw(.blocked(rect), in: overlay)
        fadeIn(overlay, duration: 0.12)
        Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(480))
            guard let self, self.generation == flash else { return }
            self.fadeOut(overlay, duration: 0.12, generation: flash)
        }
    }

    // MARK: Panels

    /// One panel per display, covering its full frame (`Displays` gives top-left frames).
    private func rebuildPanels() {
        for overlay in overlays.values { overlay.panel.orderOut(nil) }
        overlays = [:]
        shown = nil
        guard let primaryHeight = NSScreen.screens.first?.frame.height else { return }
        for display in Displays.current() {
            let rect = Coordinates.appKit(fromTopLeft: display.frame, primaryHeight: primaryHeight)
            let frame = NSRect(x: rect.x, y: rect.y, width: rect.width, height: rect.height)
            let panel = PreviewPanelWindow(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
            panel.ignoresMouseEvents = true
            panel.level = .floating
            panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
            panel.sharingType = .none
            panel.isOpaque = false
            panel.backgroundColor = .clear
            panel.hasShadow = false
            panel.animationBehavior = .none
            panel.hidesOnDeactivate = false
            panel.setAccessibilityElement(false)
            let view = PreviewContentView(frame: NSRect(origin: .zero, size: frame.size))
            view.wantsLayer = true
            view.setAccessibilityElement(false)
            view.onAppearanceChange = { [weak self] in self?.redraw() }
            let root = CALayer()
            root.frame = view.bounds
            root.opacity = 0
            view.layer?.addSublayer(root)
            panel.contentView = view
            panel.setFrame(frame, display: false)
            overlays[display.uuid] = Overlay(panel: panel, view: view, root: root, frame: frame)
        }
    }

    // MARK: Drawing

    private func redraw() {
        guard let shown, let overlay = overlays[shown.display] else { return }
        draw(shown.state, in: overlay)
    }

    /// Replaces the panel's layers with `state`'s, with no animation.
    private func draw(_ state: PreviewState, in overlay: Overlay) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        overlay.root.sublayers?.forEach { $0.removeFromSuperlayer() }
        overlay.view.subviews.forEach { $0.removeFromSuperview() }
        for style in PreviewStyle.layers(for: state, increaseContrast: increaseContrast) {
            let local = localRect(style.rect, in: overlay)
            let shape = CAShapeLayer()
            shape.path = CGPath(roundedRect: local, cornerWidth: style.cornerRadius, cornerHeight: style.cornerRadius, transform: nil)
            shape.lineWidth = style.borderWidth
            shape.lineDashPattern = style.dash?.map { NSNumber(value: $0) }
            overlay.view.effectiveAppearance.performAsCurrentDrawingAppearance {
                shape.fillColor = Self.color(style.fill).withAlphaComponent(style.fillAlpha).cgColor
                shape.strokeColor = Self.color(style.border).withAlphaComponent(style.borderAlpha).cgColor
            }
            overlay.root.addSublayer(shape)
            if let label = style.label {
                let view = PreviewLabelView(label, glyphColor: Self.color(label.glyphRole))
                let size = view.frame.size
                if PreviewStyle.showsLabel(in: Size(width: local.width, height: local.height), labelSize: Size(width: size.width, height: size.height)) {
                    view.frame.origin = CGPoint(x: (local.midX - size.width / 2).rounded(), y: (local.midY - size.height / 2).rounded())
                    overlay.view.addSubview(view)
                    view.resolveColors()
                }
            }
        }
        CATransaction.commit()
    }

    /// Animates each rect from where it is to `state`'s, 120 ms ease-in-out (UI-SPEC animation table).
    private func morph(_ overlay: Overlay, to state: PreviewState) {
        let old = (overlay.root.sublayers ?? []).compactMap { $0 as? CAShapeLayer }.map(\.path)
        draw(state, in: overlay)
        let shapes = (overlay.root.sublayers ?? []).compactMap { $0 as? CAShapeLayer }
        guard old.count == shapes.count else { return }
        for (shape, from) in zip(shapes, old) {
            let animation = CABasicAnimation(keyPath: "path")
            animation.fromValue = from
            animation.toValue = shape.path
            animation.duration = 0.12
            animation.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            shape.add(animation, forKey: "morph")
        }
    }

    private func fadeIn(_ overlay: Overlay, duration: Double) {
        overlay.panel.orderFrontRegardless()
        let animation = CABasicAnimation(keyPath: "opacity")
        animation.fromValue = 0
        animation.toValue = 1
        animation.duration = duration
        animation.timingFunction = CAMediaTimingFunction(name: .easeOut)
        overlay.root.opacity = 1
        overlay.root.add(animation, forKey: "fade")
    }

    private func hide(after duration: Double) {
        guard let current = shown, let overlay = overlays[current.display] else { return }
        shown = nil
        generation += 1
        fadeOut(overlay, duration: duration, generation: generation)
    }

    private func fadeOut(_ overlay: Overlay, duration: Double, generation shown: Int) {
        let animation = CABasicAnimation(keyPath: "opacity")
        animation.fromValue = overlay.root.presentation()?.opacity ?? overlay.root.opacity
        animation.toValue = 0
        animation.duration = duration
        overlay.root.opacity = 0
        overlay.root.add(animation, forKey: "fade")
        Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(Int(duration * 1000)))
            guard let self, self.generation == shown else { return }
            overlay.panel.orderOut(nil)
        }
    }

    /// A top-left global rect in the panel's (bottom-left) view coordinates.
    private func localRect(_ rect: Rect, in overlay: Overlay) -> CGRect {
        let primaryHeight = NSScreen.screens.first?.frame.height ?? overlay.frame.height
        let appKit = Coordinates.appKit(fromTopLeft: rect, primaryHeight: primaryHeight)
        return CGRect(x: appKit.x - overlay.frame.minX, y: appKit.y - overlay.frame.minY, width: appKit.width, height: appKit.height)
    }

    private static func color(_ role: PreviewStyle.ColorRole) -> NSColor {
        switch role {
        case .accent: .controlAccentColor
        case .red: .systemRed
        case .label: .labelColor
        }
    }

    private static func sameKind(_ a: PreviewState, _ b: PreviewState) -> Bool {
        switch (a, b) {
        case (.dock, .dock), (.blocked, .blocked), (.swap, .swap), (.snapBack, .snapBack), (.clamp, .clamp): true
        default: false
        }
    }
}

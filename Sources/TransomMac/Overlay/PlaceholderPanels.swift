import AppKit
import QuartzCore
import TransomEngine
import TransomModel

/// Never key or main: a placeholder never activates Transom or takes keys.
private final class PlaceholderPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

/// What a placeholder shows for its app (08 UI-SPEC Surface 2): the running app's, else the installed app's, else nothing
/// to name: "Waiting for a window…", the generic app icon and systemGray.
struct PlaceholderLook {
    var label: String
    var icon: NSImage
    var color: NSColor

    init(bundleID: String) {
        let running = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first
        let path = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID)?.path
        let name = running?.localizedName ?? path.map { path in
            let shown = FileManager.default.displayName(atPath: path)
            return shown.hasSuffix(".app") ? String(shown.dropLast(4)) : shown
        }
        let icon = running?.icon ?? path.map(NSWorkspace.shared.icon(forFile:))
        self.label = ViewCopy.placeholderLabel(appName: name)
        self.icon = icon ?? NSWorkspace.shared.icon(for: .applicationBundle)
        self.color = AppColor.color(forBundleID: bundleID, icon: icon)
    }

    var content: TileLayer.Content { .placeholder(color: color, icon: icon, label: label) }
}

/// One placeholder at rest: the stage's placeholder tile at the panel's size, rebuilt in the current appearance, so dark
/// mode and Increase Contrast follow. A sibling of the collapsed block: no hover ring, cursor or double-click, since
/// nothing here takes a click.
final class PlaceholderView: NSView {
    var tile: PlaceholderTile {
        didSet { needsDisplay = true }
    }
    private var drawn: CALayer?

    init(_ tile: PlaceholderTile) {
        self.tile = tile
        super.init(frame: .zero)
        wantsLayer = true
    }

    @available(*, unavailable) required init?(coder: NSCoder) { fatalError("not used") }

    override func isAccessibilityElement() -> Bool { true }
    override func accessibilityRole() -> NSAccessibility.Role? { .staticText }
    override func accessibilityLabel() -> String? { PlaceholderLook(bundleID: tile.bundleID).label }
    override func accessibilityHelp() -> String? { ViewCopy.placeholderHelp }

    override var wantsUpdateLayer: Bool { true }

    override func updateLayer() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        drawn?.removeFromSuperlayer()
        let next = TileLayer(
            PlaceholderLook(bundleID: tile.bundleID).content, rect: bounds, endSize: bounds.size, appearance: effectiveAppearance,
            scale: window?.backingScaleFactor ?? 2)
        layer?.addSublayer(next)
        drawn = next
        CATransaction.commit()
    }
}

/// The placeholder panels (08 UI-SPEC Surface 2): one click-through panel per tile held for an absent window, at normal
/// level ordered back, so any real window shows above it, on its desk's Space only and out of every capture. A camera
/// move orders a display's panels out (the stage draws them); its reveal fades them in over 120 ms.
@MainActor final class PlaceholderPanels {
    private var shown: [String: [PlaceholderPanel]] = [:]
    private var pool: [PlaceholderPanel] = []
    /// Displays whose move has not revealed yet: their panels are placed but stay out.
    private var hidden: Set<String> = []
    /// The Space each display's panels belong to (the tab strip rule).
    private var spaces: [String: UInt64] = [:]
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
            (workspace, workspace.addObserver(forName: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification, object: nil, queue: .main, using: redraw)),
        ]
    }

    /// The panels' window numbers (tests).
    var windowNumbers: Set<Int> { Set(shown.values.joined().map(\.windowNumber)) }

    /// Shows exactly `tiles` on that display; empty hides them. A new one fades in over 120 ms, a gone one fades out.
    func show(_ tiles: [PlaceholderTile], on displayUUID: String, space: UInt64?) {
        spaces[displayUUID] = space
        var old = shown[displayUUID] ?? []
        var next: [PlaceholderPanel] = []
        let primaryHeight = NSScreen.screens.first?.frame.height ?? 0
        for tile in tiles {
            let kept = old.firstIndex { Self.view($0)?.tile.window == tile.window }.map { old.remove(at: $0) }
            let panel = (kept ?? pool.popLast()).map { onShownSpace($0, displayUUID) } ?? makePanel(tile)
            Self.view(panel)?.tile = tile
            let rect = Coordinates.appKit(fromTopLeft: tile.frame, primaryHeight: primaryHeight)
            panel.setFrame(NSRect(x: rect.x, y: rect.y, width: rect.width, height: rect.height), display: true)
            if (kept == nil || !panel.isVisible) && !hidden.contains(displayUUID) { fadeIn(panel) }
            next.append(panel)
        }
        for panel in old { fadeOut(panel) }
        shown[displayUUID] = next.isEmpty ? nil : next
        if tiles.isEmpty { hidden.remove(displayUUID) }  // nothing waits for a reveal that may never come
    }

    /// A camera move started on that display.
    func hide(on displayUUID: String) {
        hidden.insert(displayUUID)
        for panel in shown[displayUUID] ?? [] { panel.orderOut(nil) }
    }

    /// That display's move revealed: its panels fade in over 120 ms.
    func fadeIn(on displayUUID: String) {
        guard hidden.remove(displayUUID) != nil else { return }
        for panel in shown[displayUUID] ?? [] { fadeIn(panel) }
    }

    /// That display now shows `space`: panels of another desk go out at once; returning to their Space brings them back.
    func spaceChanged(displayUUID: String, to space: UInt64?) {
        guard let space else { return }  // Spaces unknown: macOS keeps each panel on its own Space
        let panels = shown[displayUUID] ?? []
        if space == spaces[displayUUID] {
            for panel in panels where !panel.isVisible && !hidden.contains(displayUUID) { fadeIn(panel) }
        } else {
            for panel in panels { panel.orderOut(nil) }
        }
    }

    private func fadeIn(_ panel: PlaceholderPanel) {
        panel.alphaValue = 0
        panel.orderBack(nil)
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.12
            panel.animator().alphaValue = 1
        }
    }

    /// Fades out over 120 ms, then returns to the pool unless it was shown again meanwhile.
    private func fadeOut(_ panel: PlaceholderPanel) {
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.12
            panel.animator().alphaValue = 0
        } completionHandler: { [weak self] in
            MainActor.assumeIsolated {
                guard let self, !self.shown.values.joined().contains(where: { $0 === panel }) else { return }
                panel.orderOut(nil)
                if !self.pool.contains(where: { $0 === panel }) { self.pool.append(panel) }
            }
        }
    }

    private func makePanel(_ tile: PlaceholderTile) -> PlaceholderPanel {
        let panel = PlaceholderPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        panel.ignoresMouseEvents = true
        panel.level = .normal
        panel.collectionBehavior = [.stationary, .ignoresCycle]
        panel.sharingType = .none
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.animationBehavior = .none
        panel.hidesOnDeactivate = false
        panel.contentView = PlaceholderView(tile)
        return panel
    }

    /// `panel`, or a new one with its tile when macOS left it, still ordered in, on another Space
    /// (`leftOnAnotherSpace`). Never asked of a hidden panel: an ordered-out one reports off the active Space too.
    private func onShownSpace(_ panel: PlaceholderPanel, _ displayUUID: String) -> PlaceholderPanel {
        guard panel.isVisible, let view = Self.view(panel), panel.leftOnAnotherSpace("display \(displayUUID): placeholder panel") else { return panel }
        panel.orderOut(nil)
        return makePanel(view.tile)
    }

    private static func view(_ panel: PlaceholderPanel) -> PlaceholderView? { panel.contentView as? PlaceholderView }
}

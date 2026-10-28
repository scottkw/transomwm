import AppKit
import QuartzCore

/// One window's tile on the stage. Rects are AppKit global coordinates (bottom-left origin); callers convert with
/// `Coordinates.appKit(fromTopLeft:primaryHeight:)`.
public struct StageTile {
    public var id: UInt32
    public var start: CGRect
    public var end: CGRect
    var content: TileLayer.Content

    init(id: UInt32, start: CGRect, end: CGRect, content: TileLayer.Content) {
        self.id = id
        self.start = start
        self.end = end
        self.content = content
    }

    /// A snapshot tile, or with no image a plain `fill` tile (the spike harness).
    public init(id: UInt32, start: CGRect, end: CGRect, image: CGImage?, fill: CGColor) {
        let content: TileLayer.Content = image.map { .snapshot($0) } ?? .fallback(color: NSColor(cgColor: fill) ?? .systemGray, icon: nil, title: "")
        self.init(id: id, start: start, end: end, content: content)
    }
}

/// Re-resolves the tiles' colours when the appearance changes.
private final class StageContentView: NSView {
    var onAppearanceChange: () -> Void = {}
    override func viewDidChangeEffectiveAppearance() { onAppearanceChange() }
}

/// The camera stage (UI-SPEC Surface 1): one never-key panel per display covering its whole frame, shown only while
/// the camera moves and until settle. An opaque wallpaper backdrop hides the real windows moving underneath; the tiles
/// are the only thing that animates. Hidden from screen capture, so Transom's own snapshots never see it (T-04-02).
public final class StagePanel: NSPanel {
    public static let moveDuration = 0.25
    public static let revealFade = 0.12

    private let backdrop = CALayer()
    /// The tiles moving toward `tiles`' end rects (with a crossfade, the end set fading in), by window ID.
    private var layers: [UInt32: TileLayer] = [:]
    /// Layers on their way out: a crossfade's start set, or tiles a retarget dropped. Removed at the next show.
    private var leaving: [TileLayer] = []
    private var colorObserver: NSObjectProtocol?
    private var tiles: [StageTile] = []
    /// Chosen when a move starts (Reduce Motion), kept by its retargets.
    private var crossfade = false

    public init(screen: NSScreen) {
        super.init(contentRect: screen.frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        setFrame(screen.frame, display: false)
        ignoresMouseEvents = false
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        sharingType = .none
        #if DEBUG
            // Debug only: lets VNC and screencapture see the stage for Claude-driven UAT (RESEARCH Pitfall 7).
            if ProcessInfo.processInfo.environment["TRANSOM_STAGE_CAPTURABLE"] == "1" { sharingType = .readOnly }
        #endif
        isOpaque = true
        backgroundColor = .clear
        hasShadow = false
        animationBehavior = .none
        hidesOnDeactivate = false
        setAccessibilityElement(false)
        let view = StageContentView(frame: NSRect(origin: .zero, size: screen.frame.size))
        view.wantsLayer = true
        contentView = view
        backdrop.frame = view.bounds
        backdrop.masksToBounds = true
        backdrop.contentsGravity = .resizeAspectFill
        if let url = NSWorkspace.shared.desktopImageURL(for: screen),
            let image = NSImage(contentsOf: url)?.cgImage(forProposedRect: nil, context: nil, hints: nil)
        {
            backdrop.contents = image
        } else {
            view.effectiveAppearance.performAsCurrentDrawingAppearance { backdrop.backgroundColor = NSColor.windowBackgroundColor.cgColor }
        }
        view.layer?.addSublayer(backdrop)
        view.onAppearanceChange = { [weak self] in self?.resolveColors() }
        colorObserver = NotificationCenter.default.addObserver(forName: NSColor.systemColorsDidChangeNotification, object: nil, queue: .main) {
            [weak self] _ in
            MainActor.assumeIsolated { self?.resolveColors() }
        }
    }

    private func resolveColors() {
        guard let appearance = contentView?.effectiveAppearance else { return }
        for layer in Array(layers.values) + leaving { layer.resolveColors(appearance) }
    }

    public override var canBecomeKey: Bool { false }
    public override var canBecomeMain: Bool { false }

    public var isShown: Bool { isVisible }

    /// Orders the stage in instantly, every tile exactly at its start rect.
    public func show(tiles: [StageTile]) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for layer in Array(layers.values) + leaving { layer.removeFromSuperlayer() }
        leaving = []
        self.tiles = tiles
        layers = Dictionary(tiles.map { ($0.id, makeTile($0, at: $0.start)) }, uniquingKeysWith: { first, _ in first })
        CATransaction.commit()
        alphaValue = 1
        orderFrontRegardless()
    }

    /// Moves every tile from its start to its end rect (ease-out), or with `crossfade` (Reduce Motion) fades the start
    /// set out while an end set fades in, nothing moving. `completion` runs when the animation ends.
    /// The crossfade choice is read when each move starts (Reduce Motion), so a change applies from the next move.
    public func animate(
        duration: Double = StagePanel.moveDuration, crossfade: Bool = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion,
        completion: @escaping () -> Void
    ) {
        self.crossfade = crossfade
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        CATransaction.setCompletionBlock(completion)
        if crossfade {
            leaving = Array(layers.values)
            layers = Dictionary(tiles.map { ($0.id, makeTile($0, at: $0.end)) }, uniquingKeysWith: { first, _ in first })
            for layer in leaving { fade(layer, to: 0, duration: duration) }
            for layer in layers.values { fade(layer, from: 0, to: 1, duration: duration) }
        } else {
            for tile in tiles {
                layers[tile.id]?.move(from: localRect(tile.start), to: localRect(tile.end), duration: duration, timing: Self.moveTiming)
            }
        }
        CATransaction.commit()
    }

    /// A new move during a move or settle (UI-SPEC Retargeting): every tile goes on from where it is now (its presentation
    /// rect) to its new end over a full move, with no jump; tiles new to the move start at their start rect. Tiles not in
    /// the new move finish their old animation off screen. Keeps the move's crossfade choice.
    public func retarget(to tiles: [StageTile], duration: Double = StagePanel.moveDuration, completion: @escaping () -> Void) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        CATransaction.setCompletionBlock(completion)
        if crossfade {
            let old = Array(layers.values) + leaving
            for layer in old { fade(layer, to: 0, duration: duration) }
            leaving = old
            layers = Dictionary(tiles.map { ($0.id, makeTile($0, at: $0.end)) }, uniquingKeysWith: { first, _ in first })
            for layer in layers.values { fade(layer, from: 0, to: 1, duration: duration) }
        } else {
            var next: [UInt32: TileLayer] = [:]
            for tile in tiles where next[tile.id] == nil {
                let layer = layers.removeValue(forKey: tile.id) ?? makeTile(tile, at: tile.start)
                // A tile already on stage goes on from its presentation() rect, so a retarget never jumps.
                layer.move(from: layer.currentRect, to: localRect(tile.end), duration: duration, timing: Self.moveTiming)
                next[tile.id] = layer
            }
            leaving += layers.values
            layers = next
        }
        self.tiles = tiles
        CATransaction.commit()
    }

    /// Fades the whole stage out, then orders it out. Window alpha rather than layer opacity: the panel is opaque, so
    /// transparent content would show black instead of the windows underneath.
    public func fadeOut(duration: Double = StagePanel.revealFade, completion: (@MainActor () -> Void)? = nil) {
        NSAnimationContext.runAnimationGroup { context in
            context.duration = duration
            animator().alphaValue = 0
        } completionHandler: { [weak self] in
            MainActor.assumeIsolated {
                self?.orderOut(nil)
                self?.alphaValue = 1
                completion?()
            }
        }
    }

    private func localRect(_ rect: CGRect) -> CGRect { rect.offsetBy(dx: -frame.minX, dy: -frame.minY) }

    private static let moveTiming = CAMediaTimingFunction(name: .easeOut)

    /// A tile layer at `rect`, its fallback laid out for the tile's end size.
    private func makeTile(_ tile: StageTile, at rect: CGRect) -> TileLayer {
        let appearance = contentView?.effectiveAppearance ?? NSAppearance.currentDrawing()
        let layer = TileLayer(tile.content, rect: localRect(rect), endSize: tile.end.size, appearance: appearance, scale: backingScaleFactor)
        contentView?.layer?.addSublayer(layer)
        return layer
    }

    /// Fades from the layer's current (presentation) opacity unless `from` is given.
    private func fade(_ layer: CALayer, from: Float? = nil, to: Float, duration: Double) {
        let animation = CABasicAnimation(keyPath: "opacity")
        animation.fromValue = from ?? layer.presentation()?.opacity ?? layer.opacity
        animation.toValue = to
        animation.duration = duration
        animation.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        layer.add(animation, forKey: "opacity")
        layer.opacity = to
    }
}

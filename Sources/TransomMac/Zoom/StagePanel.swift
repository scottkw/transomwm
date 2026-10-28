import AppKit
import QuartzCore

/// One window's tile on the stage. Rects are AppKit global coordinates (bottom-left origin); callers convert with
/// `Coordinates.appKit(fromTopLeft:primaryHeight:)`. A nil `image` draws `fill`.
public struct StageTile {
    public var id: UInt32
    public var start: CGRect
    public var end: CGRect
    public var image: CGImage?
    public var fill: CGColor

    public init(id: UInt32, start: CGRect, end: CGRect, image: CGImage?, fill: CGColor) {
        self.id = id
        self.start = start
        self.end = end
        self.image = image
        self.fill = fill
    }
}

/// The camera stage (UI-SPEC Surface 1): one never-key panel per display covering its whole frame, shown only while
/// the camera moves and until settle. An opaque wallpaper backdrop hides the real windows moving underneath; the tiles
/// are the only thing that animates. Hidden from screen capture, so Transom's own snapshots never see it (T-04-02).
public final class StagePanel: NSPanel {
    public static let moveDuration = 0.25
    public static let revealFade = 0.12

    private let backdrop = CALayer()
    /// The tiles moving toward `tiles`' end rects (with a crossfade, the end set fading in), by window ID.
    private var layers: [UInt32: CALayer] = [:]
    /// Layers on their way out: a crossfade's start set, or tiles a retarget dropped. Removed at the next show.
    private var leaving: [CALayer] = []
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
        let view = NSView(frame: NSRect(origin: .zero, size: screen.frame.size))
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
    public func animate(duration: Double = StagePanel.moveDuration, crossfade: Bool, completion: @escaping () -> Void) {
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
                guard let layer = layers[tile.id] else { continue }
                move(layer, tile, from: localRect(tile.start), duration: duration)
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
            var next: [UInt32: CALayer] = [:]
            for tile in tiles where next[tile.id] == nil {
                if let layer = layers.removeValue(forKey: tile.id) {
                    let from = layer.presentation()?.frame ?? layer.frame
                    let image = layer.sublayers?.first
                    let imageFrom = image.map { $0.presentation()?.frame ?? $0.frame }
                    layer.removeAllAnimations()
                    image?.removeAllAnimations()
                    move(layer, tile, from: from, imageFrom: imageFrom, duration: duration)
                    next[tile.id] = layer
                } else {
                    let layer = makeTile(tile, at: tile.start)
                    move(layer, tile, from: localRect(tile.start), duration: duration)
                    next[tile.id] = layer
                }
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

    private func makeTile(_ tile: StageTile, at rect: CGRect) -> CALayer {
        let container = CALayer()
        container.frame = localRect(rect)
        container.masksToBounds = true
        if let image = tile.image {
            let content = CALayer()
            content.contents = image
            content.frame = Self.imageFrame(image, in: container.bounds.size)
            container.addSublayer(content)
        } else {
            container.backgroundColor = tile.fill
        }
        contentView?.layer?.addSublayer(container)
        return container
    }

    /// Aspect-fill, anchored to the top edge so the title bar stays visible (layer y grows upward).
    static func imageFrame(_ image: CGImage, in size: CGSize) -> CGRect {
        let scale = max(size.width / CGFloat(max(1, image.width)), size.height / CGFloat(max(1, image.height)))
        let width = CGFloat(image.width) * scale, height = CGFloat(image.height) * scale
        return CGRect(x: (size.width - width) / 2, y: size.height - height, width: width, height: height)
    }

    /// Animates a tile container to its end rect, and its snapshot (if any) to the aspect-fill frame at that size.
    private func move(_ layer: CALayer, _ tile: StageTile, from: CGRect, imageFrom: CGRect? = nil, duration: Double) {
        let to = localRect(tile.end)
        move(layer, from: from, to: to, duration: duration)
        if let image = layer.sublayers?.first, let content = tile.image {
            move(image, from: imageFrom ?? Self.imageFrame(content, in: from.size), to: Self.imageFrame(content, in: to.size), duration: duration)
        }
    }

    private func move(_ layer: CALayer, from: CGRect, to: CGRect, duration: Double) {
        let timing = CAMediaTimingFunction(name: .easeOut)
        let position = CABasicAnimation(keyPath: "position")
        position.fromValue = NSValue(point: CGPoint(x: from.midX, y: from.midY))
        position.toValue = NSValue(point: CGPoint(x: to.midX, y: to.midY))
        let bounds = CABasicAnimation(keyPath: "bounds")
        bounds.fromValue = NSValue(rect: CGRect(origin: .zero, size: from.size))
        bounds.toValue = NSValue(rect: CGRect(origin: .zero, size: to.size))
        for animation in [position, bounds] {
            animation.duration = duration
            animation.timingFunction = timing
            layer.add(animation, forKey: animation.keyPath)
        }
        layer.frame = to
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

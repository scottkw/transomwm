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
    private var startLayers: [CALayer] = []
    private var endLayers: [CALayer] = []
    private var tiles: [StageTile] = []

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

    /// Orders the stage in instantly, every tile exactly at its start rect.
    public func show(tiles: [StageTile]) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for layer in startLayers + endLayers { layer.removeFromSuperlayer() }
        self.tiles = tiles
        startLayers = tiles.map { makeTile($0, at: $0.start) }
        endLayers = []
        CATransaction.commit()
        alphaValue = 1
        orderFrontRegardless()
    }

    /// Moves every tile from its start to its end rect (ease-out), or with `crossfade` (Reduce Motion) fades the start
    /// set out while an end set fades in, nothing moving. `completion` runs when the animation ends.
    public func animate(duration: Double = StagePanel.moveDuration, crossfade: Bool, completion: @escaping () -> Void) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        CATransaction.setCompletionBlock(completion)
        if crossfade {
            endLayers = tiles.map { makeTile($0, at: $0.end) }
            let timing = CAMediaTimingFunction(name: .easeInEaseOut)
            for layer in startLayers { fade(layer, from: 1, to: 0, duration: duration, timing: timing) }
            for layer in endLayers { fade(layer, from: 0, to: 1, duration: duration, timing: timing) }
        } else {
            let timing = CAMediaTimingFunction(name: .easeOut)
            for (layer, tile) in zip(startLayers, tiles) {
                let from = localRect(tile.start), to = localRect(tile.end)
                move(layer, from: from, to: to, duration: duration, timing: timing)
                if let image = layer.sublayers?.first, let content = tile.image {
                    move(image, from: Self.imageFrame(content, in: from.size), to: Self.imageFrame(content, in: to.size), duration: duration, timing: timing)
                }
            }
        }
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

    private func move(_ layer: CALayer, from: CGRect, to: CGRect, duration: Double, timing: CAMediaTimingFunction) {
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

    private func fade(_ layer: CALayer, from: Float, to: Float, duration: Double, timing: CAMediaTimingFunction) {
        let animation = CABasicAnimation(keyPath: "opacity")
        animation.fromValue = from
        animation.toValue = to
        animation.duration = duration
        animation.timingFunction = timing
        layer.add(animation, forKey: "opacity")
        layer.opacity = to
    }
}

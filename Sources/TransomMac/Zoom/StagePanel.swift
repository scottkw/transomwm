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

/// The overview's strip and empty-message capsule (06 UI-SPEC Surfaces 1-2), drawn above the tiles. AppKit global rects.
struct OverviewOverlay {
    struct Mini {
        var rect: CGRect
        var content: TileLayer.Content
        /// 12 pt × the thumbnail's scale, at least 2 pt (fallback minis only).
        var radius: CGFloat
    }
    struct Thumbnail {
        var rect: CGRect
        var labelRect: CGRect
        /// Empty: no label capsule.
        var label: String
        var isCurrent: Bool
        var minis: [Mini]
    }
    var thumbnails: [Thumbnail] = []
    var emptyMessage: (rect: CGRect, text: String)?
}

/// Re-resolves the tiles' colours when the appearance changes, and takes every click on the stage.
private final class StageContentView: NSView {
    var onAppearanceChange: () -> Void = {}
    var onMouseDown: (CGPoint) -> Void = { _ in }
    override func viewDidChangeEffectiveAppearance() { onAppearanceChange() }
    // The panel is never key, so the first click must reach the view.
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func mouseDown(with event: NSEvent) { onMouseDown(convert(event.locationInWindow, from: nil)) }
}

/// The camera stage (UI-SPEC Surface 1): one never-key panel per display covering its whole frame, shown only while
/// the camera moves and until settle. An opaque wallpaper backdrop hides the real windows moving underneath; the tiles
/// are the only thing that animates. Hidden from screen capture, so Transom's own snapshots never see it (T-04-02).
public final class StagePanel: NSPanel {
    public static let moveDuration = 0.25
    public static let revealFade = 0.12

    private let backdrop = CALayer()
    /// The overview's strip and capsule, above every tile; rebuilt on appearance change.
    private let overlay = CALayer()
    private var overlaySpec: OverviewOverlay?
    /// The tiles moving toward `tiles`' end rects (with a crossfade, the end set fading in), by window ID.
    private var layers: [UInt32: TileLayer] = [:]
    /// Layers on their way out: a crossfade's start set, or tiles a retarget dropped. Removed at the next show.
    private var leaving: [TileLayer] = []
    private var colorObserver: NSObjectProtocol?
    private var tiles: [StageTile] = []
    /// Chosen when a move starts (Reduce Motion), kept by its retargets.
    private var crossfade = false
    /// Where a follow's lerp starts when it is not a tile's start rect: where the tile was when the follow's tile set last
    /// changed (a reversal, or a takeover, E-03). Spring back still returns to the start rect.
    private var followFrom: [UInt32: CGRect] = [:]
    /// Bumped when a gesture takes the stage over: completions scheduled before (a spring back's fade, a fade's order-out)
    /// no longer fire.
    private var generation = 0
    /// A click on a tile, by its window ID (Surface 5: retargets the camera). A click on the backdrop is swallowed.
    var onTileClick: ((UInt32) -> Void)?

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
        overlay.frame = view.bounds
        overlay.zPosition = 1
        view.layer?.addSublayer(overlay)
        view.onAppearanceChange = { [weak self] in self?.resolveColors() }
        view.onMouseDown = { [weak self] point in
            guard let self, let id = self.layers.first(where: { $0.value.currentRect.contains(point) })?.key else { return }
            self.onTileClick?(id)
        }
        colorObserver = NotificationCenter.default.addObserver(forName: NSColor.systemColorsDidChangeNotification, object: nil, queue: .main) {
            [weak self] _ in
            MainActor.assumeIsolated { self?.resolveColors() }
        }
    }

    private func resolveColors() {
        guard let appearance = contentView?.effectiveAppearance else { return }
        for layer in Array(layers.values) + leaving { layer.resolveColors(appearance) }
        if let overlaySpec { buildOverlay(overlaySpec) }
    }

    // MARK: Overview (06-06)

    /// Draws the overview's strip and capsule, fading in 0→1 over `duration` (opacity only, also under Reduce Motion).
    func showOverview(_ spec: OverviewOverlay, duration: Double = StagePanel.moveDuration) {
        overlaySpec = spec
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        buildOverlay(spec)
        CATransaction.commit()
        fade(overlay, from: 0, to: 1, duration: duration)
    }

    /// Fades the strip and capsule out over `duration`; they are rebuilt on the next `showOverview`.
    func clearOverview(duration: Double = StagePanel.moveDuration) {
        overlaySpec = nil
        fade(overlay, to: 0, duration: duration)
    }

    private func buildOverlay(_ spec: OverviewOverlay) {
        overlay.sublayers?.forEach { $0.removeFromSuperlayer() }
        guard let appearance = contentView?.effectiveAppearance else { return }
        let ring: CGFloat = NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast ? 1 : 0.85
        let scale = backingScaleFactor
        appearance.performAsCurrentDrawingAppearance {
            for thumb in spec.thumbnails {
                let layer = CALayer()
                layer.frame = localRect(thumb.rect)
                layer.masksToBounds = true
                layer.cornerRadius = 8
                layer.contentsGravity = .resizeAspectFill
                if let wallpaper = backdrop.contents { layer.contents = wallpaper } else { layer.backgroundColor = NSColor.windowBackgroundColor.cgColor }
                for mini in thumb.minis {
                    let rect = mini.rect.offsetBy(dx: -thumb.rect.minX, dy: -thumb.rect.minY)
                    let tile = TileLayer(mini.content, rect: rect, endSize: rect.size, appearance: appearance, scale: scale)
                    if case .snapshot = mini.content {} else { tile.cornerRadius = mini.radius }
                    layer.addSublayer(tile)
                }
                // The border goes on top of the minis: the current Space's 2 pt labelColor, else 1 pt separator.
                let border = CALayer()
                border.frame = layer.bounds
                border.cornerRadius = 8
                border.borderWidth = thumb.isCurrent ? 2 : 1
                border.borderColor = thumb.isCurrent ? NSColor.labelColor.withAlphaComponent(ring).cgColor : NSColor.separatorColor.cgColor
                layer.addSublayer(border)
                overlay.addSublayer(layer)
                if !thumb.label.isEmpty {
                    overlay.addSublayer(capsule(
                        thumb.label, in: localRect(thumb.labelRect), font: .systemFont(ofSize: 11, weight: thumb.isCurrent ? .semibold : .regular),
                        color: .labelColor))
                }
            }
            if let message = spec.emptyMessage {
                overlay.addSublayer(capsule(message.text, in: localRect(message.rect), font: .systemFont(ofSize: 13), color: .secondaryLabelColor))
            }
        }
    }

    /// An opaque one-line capsule: windowBackgroundColor, 1 pt separator border, text centred with 8 / 4 pt padding,
    /// truncated in the middle. Call inside the appearance's drawing scope.
    private func capsule(_ text: String, in rect: CGRect, font: NSFont, color: NSColor) -> CALayer {
        let layer = CALayer()
        layer.frame = rect
        layer.cornerRadius = rect.height / 2
        layer.backgroundColor = NSColor.windowBackgroundColor.cgColor
        layer.borderWidth = 1
        layer.borderColor = NSColor.separatorColor.cgColor
        let label = CATextLayer()
        label.frame = layer.bounds.insetBy(dx: 8, dy: 4)
        label.string = text
        label.font = font
        label.fontSize = font.pointSize
        label.foregroundColor = color.cgColor
        label.alignmentMode = .center
        label.truncationMode = .middle
        label.contentsScale = backingScaleFactor
        layer.addSublayer(label)
        return layer
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
        followFrom = [:]
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

    // MARK: Follow (05-04, UI-SPEC Surfaces 1, 2 and 4)

    /// A gesture's stage: in at once with every tile at its start rect, or, already up (a takeover, E-03), on from where
    /// each tile is. `crossfade` (Reduce Motion) is kept for the snap's retarget, as a move's is.
    public func beginFollow(tiles: [StageTile], crossfade: Bool) {
        if isVisible { refollow(tiles: tiles, finishingDropped: true) } else { show(tiles: tiles) }
        self.crossfade = crossfade
    }

    /// A gesture takes the stage over mid-move (E-03): every tile stops at its presentation frame, a running fade is
    /// cancelled, and completions already scheduled no longer fire. Leaving tiles finish on their way off screen.
    public func freezeAtPresentation() {
        generation += 1
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0
            animator().alphaValue = 1
        }
        alphaValue = 1
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for layer in layers.values { layer.freeze() }
        CATransaction.commit()
    }

    /// The follow's tile set changes (a reversal, or a takeover): every tile goes on from where it is now, a new one from
    /// its start rect, and the lerp runs from there, so nothing jumps (UI-SPEC Surface 1, E-03). Tiles the new set drops
    /// are removed (a reversal's are at their off-screen start), or with `finishingDropped` (a takeover's leaving tiles)
    /// go on to their old end, as a retarget's do.
    public func refollow(tiles new: [StageTile], finishingDropped: Bool = false) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        var next: [UInt32: TileLayer] = [:]
        followFrom = [:]
        for tile in new where next[tile.id] == nil {
            let old = layers.removeValue(forKey: tile.id)
            let from = old.map { $0.currentRect.offsetBy(dx: frame.minX, dy: frame.minY) } ?? tile.start
            old?.removeFromSuperlayer()
            next[tile.id] = makeTile(tile, at: from)
            followFrom[tile.id] = from
        }
        for tile in tiles {
            guard let layer = layers.removeValue(forKey: tile.id) else { continue }
            if finishingDropped {
                layer.move(from: layer.currentRect, to: localRect(tile.end), duration: Self.moveDuration, timing: Self.moveTiming)
                leaving.append(layer)
            } else {
                layer.removeFromSuperlayer()
            }
        }
        for layer in layers.values { layer.removeFromSuperlayer() }
        layers = next
        tiles = new
        CATransaction.commit()
        alphaValue = 1
        orderFrontRegardless()
    }

    /// One frame of finger tracking, set at once (no animation between samples): every tile at `followRect`.
    public func follow(t: Double, scale: Double, anchor: CGPoint, offset: CGVector) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for tile in tiles {
            let start = followFrom[tile.id] ?? tile.start
            layers[tile.id]?.set(localRect(Self.followRect(start: start, end: tile.end, t: t, scale: scale, anchor: anchor, offset: offset)))
        }
        CATransaction.commit()
    }

    /// lerp(start, end, t), then scaled by `scale` about `anchor`, then moved by `offset`. Global AppKit coordinates.
    nonisolated public static func followRect(start: CGRect, end: CGRect, t: Double, scale: Double, anchor: CGPoint, offset: CGVector) -> CGRect {
        func lerp(_ a: CGFloat, _ b: CGFloat) -> CGFloat { a + (b - a) * t }
        let x = lerp(start.minX, end.minX), y = lerp(start.minY, end.minY)
        return CGRect(
            x: anchor.x + (x - anchor.x) * scale + offset.dx, y: anchor.y + (y - anchor.y) * scale + offset.dy,
            width: lerp(start.width, end.width) * scale, height: lerp(start.height, end.height) * scale)
    }

    /// Spring back: every tile from where it is to its start rect over a move, then the reveal fade; with `fade` (Reduce
    /// Motion) the stage just fades out over a move, nothing moving. The real windows never moved, so nothing settles.
    public func springBack(fade: Bool, completion: @escaping @MainActor () -> Void) {
        guard !fade else { return fadeOut(duration: Self.moveDuration, completion: completion) }
        let started = generation
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        CATransaction.setCompletionBlock { [weak self] in
            MainActor.assumeIsolated {
                guard let self, self.generation == started else { return }  // taken over (E-03)
                self.fadeOut(completion: completion)
            }
        }
        for tile in tiles {
            guard let layer = layers[tile.id] else { continue }
            layer.move(from: layer.currentRect, to: localRect(tile.start), duration: Self.moveDuration, timing: Self.moveTiming)
        }
        CATransaction.commit()
    }

    /// A capture that came back while the stage is up: the tile's contents cross-fade to it over the reveal fade (opacity,
    /// not motion, so also under Reduce Motion); its frame is untouched.
    public func setContents(_ image: CGImage, for id: UInt32) {
        guard let layer = layers[id], let index = tiles.firstIndex(where: { $0.id == id }) else { return }
        tiles[index].content = .snapshot(image)
        let fade = CATransition()
        fade.type = .fade
        fade.duration = Self.revealFade
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer.add(fade, forKey: "contents")
        layer.setSnapshot(image)
        CATransaction.commit()
    }

    /// Fades the whole stage out, then orders it out. Window alpha rather than layer opacity: the panel is opaque, so
    /// transparent content would show black instead of the windows underneath.
    /// A gesture taking the stage over meanwhile (E-03) cancels both the order-out and `completion`.
    public func fadeOut(duration: Double = StagePanel.revealFade, completion: (@MainActor () -> Void)? = nil) {
        let started = generation
        NSAnimationContext.runAnimationGroup { context in
            context.duration = duration
            animator().alphaValue = 0
        } completionHandler: { [weak self] in
            MainActor.assumeIsolated {
                if let self {
                    guard self.generation == started else { return }
                    self.orderOut(nil)
                    self.alphaValue = 1
                }
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

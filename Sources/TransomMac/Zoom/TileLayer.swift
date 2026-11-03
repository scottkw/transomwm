import AppKit
import QuartzCore

/// One window's tile on the stage (UI-SPEC Surface 1, Tile contents). A snapshot is drawn aspect-fill and top-anchored
/// with no border or radius; a fallback is the app colour with the app icon and a title capsule, laid out for the tile's
/// end size and kept at that size through the move. The bounds are centred on (0, 0), so the icon and capsule stay
/// centred while the bounds animate.
nonisolated final class TileLayer: CALayer {
    enum Content {
        case snapshot(CGImage)
        case fallback(color: NSColor, icon: NSImage?, title: String)
        /// A collapsed window (UI-SPEC Surface 3, drawn on the stage): no title.
        case collapsed(color: NSColor, icon: NSImage?)
        /// A group's icon-only strip (07 UI-SPEC Surface 6): drawn once at the end size, stretched while it moves.
        case strip(icons: [NSImage?], selected: Int)
    }

    static let cornerRadius: CGFloat = 12
    static let maxIcon: CGFloat = 64
    static let minIcon: CGFloat = 16
    /// Clearance around the icon and capsule on each side (UI-SPEC md token).
    static let clearance: CGFloat = 16

    private var content: Content?
    private let picture = CALayer()
    private let iconLayer = CALayer()
    private let capsule = CALayer()
    private let label = CALayer()
    private var titleText = ""
    private var labelSize = CGSize.zero

    /// A tile at `rect` (stage-local), its fallback laid out for `endSize`.
    init(_ content: Content, rect: CGRect, endSize: CGSize, appearance: NSAppearance, scale: CGFloat) {
        self.content = content
        super.init()
        masksToBounds = true
        contentsScale = scale
        place(rect)
        switch content {
        case .snapshot(let image):
            picture.contents = image
            picture.frame = Self.pictureFrame(image, in: rect.size)
            addSublayer(picture)
        case .fallback(let color, let icon, let title):
            backgroundColor = color.cgColor
            cornerRadius = Self.cornerRadius
            borderWidth = 1
            layoutFallback(icon: icon, title: title, endSize: endSize, scale: scale)
        case .collapsed(let color, let icon):
            let shorter = min(endSize.width, endSize.height)
            backgroundColor = color.cgColor
            cornerRadius = min(Self.cornerRadius, shorter / 2)
            borderWidth = 1
            let side = min(32, shorter - 8)
            if let icon, side >= Self.minIcon {
                iconLayer.frame = CGRect(x: -side / 2, y: -side / 2, width: side, height: side)
                iconLayer.contents = icon.layerContents(forContentsScale: scale)
                iconLayer.contentsScale = scale
                iconLayer.contentsGravity = .resizeAspect
                addSublayer(iconLayer)
            }
        case .strip:
            contentsGravity = .resize
        }
        resolveColors(appearance)
    }

    /// Core Animation copies a layer for its presentation through this.
    override init(layer: Any) {
        super.init(layer: layer)
    }

    @available(*, unavailable) required init?(coder: NSCoder) { fatalError("not used") }

    /// Puts the tile at `rect` at once: centred bounds of its size, positioned at its centre.
    func place(_ rect: CGRect) {
        bounds = CGRect(x: -rect.width / 2, y: -rect.height / 2, width: rect.width, height: rect.height)
        position = CGPoint(x: rect.midX, y: rect.midY)
    }

    /// Puts the tile at `rect` at once with its snapshot re-fitted (follow mode; the caller disables actions).
    func set(_ rect: CGRect) {
        place(rect)
        if case .snapshot(let image) = content { picture.frame = Self.pictureFrame(image, in: rect.size) }
    }

    /// Swaps a fallback for a snapshot that came back late (the caller adds the cross-fade).
    func setSnapshot(_ image: CGImage) {
        content = .snapshot(image)
        for layer in sublayers ?? [] { layer.removeFromSuperlayer() }
        backgroundColor = nil
        borderWidth = 0
        cornerRadius = 0
        picture.contents = image
        picture.frame = Self.pictureFrame(image, in: bounds.size)
        addSublayer(picture)
    }

    /// Where the tile is on screen now: its presentation rect while it animates.
    var currentRect: CGRect { presentation()?.frame ?? frame }

    /// Stops where it is on screen now (E-03): the presentation frame and opacity become the model's. Call with actions
    /// disabled.
    func freeze() {
        let rect = currentRect, opacity = presentation()?.opacity ?? self.opacity
        removeAllAnimations()
        picture.removeAllAnimations()
        set(rect)
        self.opacity = opacity
    }

    /// Moves from `from` to `to` with one curve; a snapshot's picture goes on from where it is to its aspect-fill frame at
    /// the new size. `from` is the tile's start rect, or its presentation rect for a retarget.
    func move(from: CGRect, to: CGRect, duration: Double, timing: CAMediaTimingFunction) {
        let pictureFrom = picture.presentation()?.frame ?? picture.frame
        removeAllAnimations()
        picture.removeAllAnimations()
        animate(self, "position", NSValue(point: CGPoint(x: from.midX, y: from.midY)), NSValue(point: CGPoint(x: to.midX, y: to.midY)), duration, timing)
        animate(self, "bounds", NSValue(rect: Self.centred(from.size)), NSValue(rect: Self.centred(to.size)), duration, timing)
        place(to)
        guard case .snapshot(let image) = content else { return }
        let pictureTo = Self.pictureFrame(image, in: to.size)
        animate(picture, "position", NSValue(point: CGPoint(x: pictureFrom.midX, y: pictureFrom.midY)), NSValue(point: CGPoint(x: pictureTo.midX, y: pictureTo.midY)), duration, timing)
        animate(picture, "bounds", NSValue(rect: CGRect(origin: .zero, size: pictureFrom.size)), NSValue(rect: CGRect(origin: .zero, size: pictureTo.size)), duration, timing)
        picture.frame = pictureTo
    }

    /// The border and capsule colours in `appearance` (light/dark, accent and contrast changes).
    func resolveColors(_ appearance: NSAppearance) {
        if case .snapshot? = content { return }
        if case .strip(let icons, let selected)? = content {
            appearance.performAsCurrentDrawingAppearance {
                contents = StripLayerStyle.image(size: bounds.size, icons: icons, selected: selected).layerContents(forContentsScale: contentsScale)
            }
            return
        }
        appearance.performAsCurrentDrawingAppearance {
            borderColor = NSColor.separatorColor.cgColor
            capsule.backgroundColor = NSColor.windowBackgroundColor.cgColor
            capsule.borderColor = NSColor.separatorColor.cgColor
            if labelSize != .zero { label.contents = Self.text(titleText, size: labelSize).layerContents(forContentsScale: contentsScale) }
        }
    }

    // MARK: Layout

    private func layoutFallback(icon: NSImage?, title: String, endSize: CGSize, scale: CGFloat) {
        let side = min(Self.maxIcon, min(endSize.width, endSize.height) - 2 * Self.clearance)
        let showIcon = icon != nil && side >= Self.minIcon
        let iconSide = showIcon ? side : 0

        let attributed = Self.attributed(title)
        let natural = attributed.size()
        let labelWidth = min(ceil(natural.width), endSize.width - 2 * Self.clearance - 16)
        let capsuleSize = CGSize(width: labelWidth + 16, height: ceil(natural.height) + 8)
        let gap: CGFloat = showIcon ? 8 : 0
        let showCapsule = !title.isEmpty && labelWidth >= Self.font.pointSize
            && endSize.height >= iconSide + gap + capsuleSize.height + 2 * Self.clearance
            && endSize.width >= capsuleSize.width + 2 * Self.clearance

        // The icon (and the capsule under it, when it fits) centred as a group; y grows upward.
        let groupHeight = iconSide + (showCapsule ? gap + capsuleSize.height : 0)
        let top = groupHeight / 2
        if showIcon, let icon {
            iconLayer.frame = CGRect(x: -side / 2, y: top - side, width: side, height: side)
            iconLayer.contents = icon.layerContents(forContentsScale: scale)
            iconLayer.contentsScale = scale
            iconLayer.contentsGravity = .resizeAspect
            addSublayer(iconLayer)
        }
        guard showCapsule else { return }
        capsule.frame = CGRect(x: -capsuleSize.width / 2, y: -top, width: capsuleSize.width, height: capsuleSize.height)
        capsule.cornerRadius = capsuleSize.height / 2
        capsule.borderWidth = 1
        titleText = title
        labelSize = CGSize(width: labelWidth, height: ceil(natural.height))
        label.frame = CGRect(x: 8, y: 4, width: labelSize.width, height: labelSize.height)
        label.contentsScale = scale
        capsule.addSublayer(label)
        addSublayer(capsule)
    }

    private static var font: NSFont { NSFont.preferredFont(forTextStyle: .body) }

    /// One line, middle-truncated, Body, in `color` (`labelColor` for measuring).
    private static func attributed(_ title: String, color: NSColor = .labelColor) -> NSAttributedString {
        let style = NSMutableParagraphStyle()
        style.lineBreakMode = .byTruncatingMiddle
        return NSAttributedString(string: title, attributes: [.font: font, .foregroundColor: color, .paragraphStyle: style])
    }

    /// The title image. `labelColor` is resolved now, in the caller's drawing appearance: the image draws lazily, when
    /// that appearance is no longer current (black text on a dark capsule otherwise, UAT 04).
    static func text(_ title: String, size: CGSize) -> NSImage {
        let color = NSColor(cgColor: NSColor.labelColor.cgColor) ?? .labelColor
        return NSImage(size: size, flipped: false) { rect in
            attributed(title, color: color).draw(with: rect, options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine])
            return true
        }
    }

    private static func centred(_ size: CGSize) -> CGRect {
        CGRect(x: -size.width / 2, y: -size.height / 2, width: size.width, height: size.height)
    }

    /// Aspect-fill in a tile of `size`, anchored to the top edge so the title bar stays visible, in centred coordinates.
    static func pictureFrame(_ image: CGImage, in size: CGSize) -> CGRect {
        let scale = max(size.width / CGFloat(max(1, image.width)), size.height / CGFloat(max(1, image.height)))
        let width = CGFloat(image.width) * scale, height = CGFloat(image.height) * scale
        return CGRect(x: -width / 2, y: size.height / 2 - height, width: width, height: height)
    }

    private func animate(_ layer: CALayer, _ key: String, _ from: NSValue, _ to: NSValue, _ duration: Double, _ timing: CAMediaTimingFunction) {
        let animation = CABasicAnimation(keyPath: key)
        animation.fromValue = from
        animation.toValue = to
        animation.duration = duration
        animation.timingFunction = timing
        layer.add(animation, forKey: key)
    }
}

/// A group's strip on the stage and in the overview (07 UI-SPEC Surface 6): the strip recipe at `scale` (the strip's
/// height / 28), one icon-only chip per tab, the selected chip filled. No titles, buttons or overflow.
nonisolated enum StripLayerStyle {
    static let height: CGFloat = 28

    /// Radius 8 × scale (at least 2); chips share the width with 4 × scale gaps inside 4 × scale padding, 20 × scale
    /// tall; icons (16 × scale) hidden below 8 pt; below 4 pt tall only the fill is drawn. Rects in `frame`'s space.
    static func layout(frame: CGRect, scale: CGFloat, count: Int) -> (radius: CGFloat, chips: [CGRect], showsIcons: Bool, fillOnly: Bool) {
        let inset = 4 * scale
        let width = count > 0 ? max(0, (frame.width - 2 * inset - CGFloat(count - 1) * inset) / CGFloat(count)) : 0
        let chips = (0..<count).map { CGRect(x: frame.minX + inset + CGFloat($0) * (width + inset), y: frame.minY + inset, width: width, height: 20 * scale) }
        return (max(2, 8 * scale), chips, 16 * scale >= 8, frame.height < 4)
    }

    /// The strip at `size`. Colours are resolved now, in the caller's drawing appearance (the image draws lazily, UAT 04).
    static func image(size: CGSize, icons: [NSImage?], selected: Int) -> NSImage {
        let scale = size.height / height
        let style = layout(frame: CGRect(origin: .zero, size: size), scale: scale, count: icons.count)
        let fill = NSColor(cgColor: NSColor.windowBackgroundColor.cgColor) ?? .windowBackgroundColor
        let border = NSColor(cgColor: NSColor.separatorColor.cgColor) ?? .separatorColor
        let chosen = NSColor(cgColor: NSColor.labelColor.withAlphaComponent(0.16).cgColor) ?? .labelColor
        return NSImage(size: size, flipped: true) { rect in
            let outline = NSBezierPath(roundedRect: rect.insetBy(dx: 0.5, dy: 0.5), xRadius: style.radius, yRadius: style.radius)
            fill.setFill()
            outline.fill()
            guard !style.fillOnly else { return true }
            border.setStroke()
            outline.lineWidth = 1
            outline.stroke()
            for (i, chip) in style.chips.enumerated() {
                if i == selected {
                    chosen.setFill()
                    NSBezierPath(roundedRect: chip, xRadius: chip.height / 2, yRadius: chip.height / 2).fill()
                }
                guard style.showsIcons, let icon = icons[i] else { continue }
                let side = min(16 * scale, chip.width)
                icon.draw(in: CGRect(x: chip.midX - side / 2, y: chip.midY - side / 2, width: side, height: side))
            }
            return true
        }
    }
}

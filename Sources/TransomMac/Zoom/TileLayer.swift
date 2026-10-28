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

    /// Where the tile is on screen now: its presentation rect while it animates.
    var currentRect: CGRect { presentation()?.frame ?? frame }

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

    /// One line, middle-truncated, Body, `labelColor` (resolved by the caller's drawing appearance).
    private static func attributed(_ title: String) -> NSAttributedString {
        let style = NSMutableParagraphStyle()
        style.lineBreakMode = .byTruncatingMiddle
        return NSAttributedString(string: title, attributes: [.font: font, .foregroundColor: NSColor.labelColor, .paragraphStyle: style])
    }

    private static func text(_ title: String, size: CGSize) -> NSImage {
        NSImage(size: size, flipped: false) { rect in
            attributed(title).draw(with: rect, options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine])
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

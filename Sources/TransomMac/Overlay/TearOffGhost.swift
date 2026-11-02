import AppKit
import TransomEngine
import TransomModel

/// The tear-off ghost's capsule: 16 pt app icon and the Body title, middle-truncated (UI-SPEC Surface 4).
private final class TearOffGhostView: NSView {
    static let font = NSFont.preferredFont(forTextStyle: .body)
    static let maxWidth: CGFloat = 240
    static let height: CGFloat = 24
    /// Padding inside the capsule (sm), and the gap between icon and title (xs).
    static let padding: CGFloat = 8
    static let gap: CGFloat = 4
    static let icon: CGFloat = 16

    var icon: NSImage?
    var title = ""

    /// The capsule's width for `title`: icon, gap and title inside the padding, at most 240 pt.
    static func width(for title: String) -> CGFloat {
        let text = ceil((title as NSString).size(withAttributes: [.font: font]).width)
        return min(maxWidth, padding + icon + gap + text + padding)
    }

    override func draw(_ dirtyRect: NSRect) {
        let capsule = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: bounds.height / 2 - 0.5, yRadius: bounds.height / 2 - 0.5)
        NSColor.windowBackgroundColor.setFill()
        capsule.fill()
        NSColor.separatorColor.setStroke()
        capsule.lineWidth = 1
        capsule.stroke()
        let y = (bounds.height - Self.icon) / 2
        icon?.draw(in: NSRect(x: Self.padding, y: y, width: Self.icon, height: Self.icon))
        let style = NSMutableParagraphStyle()
        style.lineBreakMode = .byTruncatingMiddle
        let x = Self.padding + Self.icon + Self.gap
        (title as NSString).draw(
            in: NSRect(x: x, y: y - 1, width: bounds.width - x - Self.padding, height: Self.icon + 2),
            withAttributes: [.font: Self.font, .foregroundColor: NSColor.labelColor, .paragraphStyle: style])
    }
}

/// The tear-off ghost panel (UI-SPEC Surface 4): click-through, above the drop preview, on every Space, excluded from
/// capture. Its top-left sits 8 pt right of and below the pointer, so it never hides the drop target. Not an
/// accessibility element: the tear-off is announced instead.
@MainActor final class TearOffGhostPanel {
    private var panel: NSPanel?
    var isShown: Bool { panel != nil }

    /// Shows the ghost for `ghost`'s window (its title, else its app name), fading in over 120 ms.
    func show(_ ghost: TearOffGhost) {
        hide()
        let app = NSRunningApplication(processIdentifier: ghost.member.pid)
        let title = TabCopy.titleOrApp(title: ghost.title, app: app?.localizedName ?? ghost.member.bundleID)
        let panel = Self.makePanel()
        if let view = panel.contentView as? TearOffGhostView {
            view.icon = app?.icon
            view.title = title
        }
        panel.setContentSize(NSSize(width: TearOffGhostView.width(for: title), height: TearOffGhostView.height))
        self.panel = panel
        move(to: ghost.pointer)
        panel.alphaValue = 0
        panel.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.12
            panel.animator().alphaValue = 1
        }
    }

    /// Follows the pointer; a panel macOS left on another Space is replaced first (`leftOnAnotherSpace`).
    func move(to pointer: Point) {
        guard var panel else { return }
        if panel.leftOnAnotherSpace("tear-off ghost") {
            let new = Self.makePanel()
            new.contentView = panel.contentView
            new.setContentSize(panel.frame.size)
            new.alphaValue = 1
            panel.orderOut(nil)
            new.orderFrontRegardless()
            self.panel = new
            panel = new
        }
        let primaryHeight = NSScreen.screens.first?.frame.height ?? 0
        let size = panel.frame.size
        panel.setFrameOrigin(NSPoint(x: pointer.x + 8, y: primaryHeight - (pointer.y + 8) - size.height))
    }

    /// Fades out over 80 ms, then orders out.
    func hide() {
        guard let panel else { return }
        self.panel = nil
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.08
            panel.animator().alphaValue = 0
        } completionHandler: {
            MainActor.assumeIsolated { panel.orderOut(nil) }
        }
    }

    private static func makePanel() -> NSPanel {
        let panel = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        panel.ignoresMouseEvents = true
        // One above the drop preview panel's .floating level.
        panel.level = NSWindow.Level(rawValue: NSWindow.Level.floating.rawValue + 1)
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        panel.sharingType = .none
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.animationBehavior = .none
        panel.hidesOnDeactivate = false
        panel.contentView = TearOffGhostView()
        return panel
    }
}

import AppKit
import TransomEngine
import TransomModel
import SwiftUI

/// Posts a VoiceOver announcement (refusals and toasts use the same high priority).
func postAnnouncement(_ text: String) {
    NSAccessibility.post(
        element: NSApplication.shared, notification: .announcementRequested,
        userInfo: [.announcement: text, .priority: NSAccessibilityPriorityLevel.high.rawValue])
}

/// Never key or main, so a toast cannot take focus or input meant for another app (T-03-14).
private final class ToastPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

private struct ToastView: View {
    let text: String
    let glyph: String
    let warning: Bool

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: glyph)
                .font(.body)
                .imageScale(.large)
                .foregroundStyle(Color(nsColor: warning ? .systemOrange : .secondaryLabelColor))
                .accessibilityHidden(true)
            Text(verbatim: text)
                .font(.body)
                .foregroundStyle(Color(nsColor: .labelColor))
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: 360, alignment: .leading)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }
}

/// The one toast panel (UI-SPEC Surface 4): click-through, never activating Transom, on every Space, hidden from
/// screen capture. `ArrangeController` decides what shows through `NoticeQueue`.
@MainActor final class ToastPresenter {
    private(set) var panel = ToastPresenter.makePanel()
    /// Bumped by every show, so a fade-out that finishes after a newer show does not hide it.
    private var generation = 0

    /// The panel, its content view the HUD material the toast's text goes in.
    private static func makePanel() -> NSPanel {
        let panel = ToastPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.ignoresMouseEvents = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        panel.sharingType = .none
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        let effect = NSVisualEffectView()
        effect.material = .hudWindow
        effect.state = .active
        effect.wantsLayer = true
        effect.layer?.cornerRadius = 12
        effect.layer?.masksToBounds = true
        panel.contentView = effect
        return panel
    }

    /// Shows `text` centred 16 pt below the top of `displayUUID`'s visible frame (the menu-bar display when nil or
    /// gone), fading in over 160 ms, and announces it.
    func show(_ text: String, glyph: String, warning: Bool = false, on displayUUID: String?) {
        generation += 1
        if panel.leftOnAnotherSpace("toast panel") {
            panel.orderOut(nil)
            panel = Self.makePanel()
        }
        let hosting = NSHostingView(rootView: ToastView(text: text, glyph: glyph, warning: warning))
        let size = hosting.fittingSize
        hosting.frame = NSRect(origin: .zero, size: size)
        panel.contentView?.subviews.forEach { $0.removeFromSuperview() }
        panel.contentView?.addSubview(hosting)

        let displays = Displays.current()
        if let display = displays.first(where: { $0.uuid == displayUUID }) ?? displays.first,
            let primaryHeight = NSScreen.screens.first?.frame.height
        {
            let visible = display.visibleFrame
            let topLeft = Rect(x: (visible.midX - size.width / 2).rounded(), y: visible.minY + 16, width: size.width, height: size.height)
            let frame = Coordinates.appKit(fromTopLeft: topLeft, primaryHeight: primaryHeight)
            panel.setFrame(NSRect(x: frame.x, y: frame.y, width: frame.width, height: frame.height), display: true)
        }
        if !panel.isVisible { panel.alphaValue = 0 }
        panel.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.16
            panel.animator().alphaValue = 1
        }
        postAnnouncement(text)
    }

    /// Re-orders a visible toast above a panel at the same level that just ordered in (the camera stage).
    func bringFront() {
        if panel.isVisible { panel.orderFrontRegardless() }
    }

    /// Fades out over 240 ms, then orders the panel out.
    func hide() {
        let shown = generation
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.24
            panel.animator().alphaValue = 0
        } completionHandler: { [weak self] in
            MainActor.assumeIsolated {
                guard let self, self.generation == shown else { return }
                self.panel.orderOut(nil)
            }
        }
    }
}

import AppKit
import TransomEngine
import TransomModel

/// Never key or main: a click on a tab leaves the frontmost app frontmost and never activates Transom (T-07-03).
private final class StripPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

/// One group's strip (UI-SPEC Surface 2): `windowBackgroundColor`, 8 pt radius, 1 pt `separatorColor` border inside,
/// 4 pt padding, and one equal-width capsule tab per member (16 pt app icon, title in Body; the selected tab in
/// Heading on a `labelColor` 16% fill). A tab acts on mouse-up with under 4 pt of travel.
final class TabStripView: NSView {
    var strip: TabStrip {
        didSet { needsDisplay = true }
    }
    var onAction: ((TabAction) -> Void)?
    private var hovered: Int?
    private var press: (tab: Int?, at: NSPoint)?

    init(_ strip: TabStrip) {
        self.strip = strip
        super.init(frame: .zero)
    }

    @available(*, unavailable) required init?(coder: NSCoder) { fatalError("not used") }

    private static let padding: CGFloat = 4
    private static let tabHeight: CGFloat = 20
    /// Under this a press is still a click (UI-SPEC Spacing xs).
    private static let clickTravel: CGFloat = 4

    /// Tab `i`'s rect: the region inside the padding shared equally, 4 pt apart.
    func tabRect(_ i: Int) -> NSRect {
        let n = CGFloat(max(strip.members.count, 1))
        let region = bounds.width - 2 * Self.padding
        let width = max(0, (region - Self.padding * (n - 1)) / n)
        return NSRect(x: Self.padding + CGFloat(i) * (width + Self.padding), y: (bounds.height - Self.tabHeight) / 2, width: width, height: Self.tabHeight)
    }

    private func tab(at point: NSPoint) -> Int? { strip.members.indices.first { tabRect($0).contains(point) } }

    override func draw(_ dirtyRect: NSRect) {
        let contrast = NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast
        let outline = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: 8, yRadius: 8)
        NSColor.windowBackgroundColor.setFill()
        outline.fill()
        NSColor.separatorColor.setStroke()
        outline.lineWidth = 1
        outline.stroke()
        for (i, member) in strip.members.enumerated() {
            let rect = tabRect(i), isSelected = i == strip.selected
            let capsule = NSBezierPath(roundedRect: rect, xRadius: rect.height / 2, yRadius: rect.height / 2)
            let fill: CGFloat? = isSelected ? 0.16 : i == hovered ? 0.08 : nil
            if let fill {
                NSColor.labelColor.withAlphaComponent(contrast ? fill * 1.5 : fill).setFill()
                capsule.fill()
            }
            if isSelected, contrast {
                NSColor.labelColor.setStroke()
                capsule.lineWidth = 1
                capsule.stroke()
            }
            var x = rect.minX + 8
            if let icon = Self.icon(member.pid) {
                icon.draw(in: NSRect(x: x, y: rect.midY - 8, width: 16, height: 16))
                x += 16 + 4
            }
            let width = rect.maxX - 8 - x
            guard width > 8 else { continue }
            let title = strip.titles.indices.contains(i) && !strip.titles[i].isEmpty ? strip.titles[i] : Self.appName(member)
            let paragraph = NSMutableParagraphStyle()
            paragraph.lineBreakMode = .byTruncatingMiddle
            let text = NSAttributedString(string: title, attributes: [
                .font: NSFont.preferredFont(forTextStyle: isSelected ? .headline : .body),
                .foregroundColor: isSelected ? NSColor.labelColor : NSColor.secondaryLabelColor,
                .paragraphStyle: paragraph,
            ])
            let height = text.size().height
            text.draw(with: NSRect(x: x, y: rect.midY - height / 2, width: width, height: height), options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine])
        }
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .mouseMoved, .activeAlways, .inVisibleRect], owner: self))
    }

    override func mouseMoved(with event: NSEvent) { setHovered(tab(at: convert(event.locationInWindow, from: nil))) }
    override func mouseExited(with event: NSEvent) { setHovered(nil) }

    private func setHovered(_ tab: Int?) {
        guard tab != hovered else { return }
        hovered = tab
        needsDisplay = true
    }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        press = (tab(at: point), point)
    }

    /// A click on a tab selects it; on the background it focuses the selected member. A double-click is one click.
    override func mouseUp(with event: NSEvent) {
        guard let press else { return }
        self.press = nil
        let point = convert(event.locationInWindow, from: nil)
        guard hypot(point.x - press.at.x, point.y - press.at.y) < Self.clickTravel, tab(at: point) == press.tab, event.clickCount <= 1 else { return }
        let index = press.tab ?? strip.selected
        guard strip.members.indices.contains(index) else { return }
        onAction?(.select(strip.members[index], via: .click))
    }

    private static var icons: [Int32: NSImage] = [:]

    private static func icon(_ pid: Int32) -> NSImage? {
        if let icon = icons[pid] { return icon }
        let icon = NSRunningApplication(processIdentifier: pid)?.icon
        icons[pid] = icon
        return icon
    }

    private static func appName(_ window: TransomModel.WindowRef) -> String {
        MenuCopy.truncatedAppName(NSRunningApplication(processIdentifier: window.pid)?.localizedName ?? window.bundleID)
    }
}

/// The tab strip panels (UI-SPEC Surface 2): one borderless, non-activating panel per docked group, recycled through
/// a pool (the `CollapsedPanels` pattern), at normal level and bound to its group's Space (no `.canJoinAllSpaces`),
/// excluded from capture. A panel covers only the strip rect, which no window occupies, so it steals no click.
@MainActor final class TabStripPanels {
    var onAction: ((TabAction) -> Void)?
    /// The CG bounds of a member's window now (its visible tab), for the 500 ms backstop; nil when it has none.
    var bounds: ((TransomModel.WindowRef) -> Rect?)?
    private var shown: [String: [StripPanel]] = [:]
    private var pool: [StripPanel] = []
    private var observers: [(NotificationCenter, NSObjectProtocol)] = []
    private var backstop: Timer?
    /// Per group, the drifted strip rect the last backstop tick saw: a drift is followed only when two ticks agree,
    /// so a revealed member still at its park for a moment never pulls the strip there.
    private var drift: [GroupKey: Rect] = [:]

    /// The window numbers of the strips on screen: a press on one is never a window drag (Pitfall 4).
    var windowNumbers: Set<Int> { Set(shown.values.joined().map(\.windowNumber)) }

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

    /// Shows exactly `strips` on that display; empty hides them. A new group's strip fades in over 120 ms, a gone one
    /// fades out over 120 ms; a selection or title change redraws at once.
    func show(_ strips: [TabStrip], on displayUUID: String) {
        var old = shown[displayUUID] ?? []
        var next: [StripPanel] = []
        let primaryHeight = NSScreen.screens.first?.frame.height ?? 0
        for strip in strips {
            let kept = old.firstIndex { Self.view($0)?.strip.group == strip.group }.map { old.remove(at: $0) }
            let panel = (kept ?? pool.popLast()).map { onShownSpace($0, displayUUID) } ?? makePanel(strip)
            if let view = Self.view(panel) {
                view.strip = strip
                view.onAction = { [weak self] in self?.onAction?($0) }
            }
            place(panel, strip.frame, primaryHeight: primaryHeight)
            if kept == nil || !panel.isVisible { fadeIn(panel) }
            next.append(panel)
        }
        for panel in old { fadeOut(panel) }
        shown[displayUUID] = next.isEmpty ? nil : next
        updateBackstop()
    }

    /// The group whose selected member is `window`, when its strip is on screen.
    func group(selecting window: TransomModel.WindowRef) -> GroupKey? {
        shown.values.joined().lazy.compactMap { Self.view($0)?.strip }.first { $0.members[$0.selected] == window }?.group
    }

    /// Moves `group`'s strip over the content rect its selected window has now (a drag, or the app moving it), with
    /// no animation (UI-SPEC Surface 2, Following the group).
    func follow(_ group: GroupKey, contentBounds: Rect) {
        guard let panel = shown.values.joined().first(where: { Self.view($0)?.strip.group == group }) else { return }
        place(panel, TabBand.strip(of: TabBand.frame(ofContent: contentBounds)), primaryHeight: NSScreen.screens.first?.frame.height ?? 0)
    }

    private func place(_ panel: StripPanel, _ frame: Rect, primaryHeight: CGFloat) {
        let rect = Coordinates.appKit(fromTopLeft: frame, primaryHeight: primaryHeight)
        let target = NSRect(x: rect.x, y: rect.y, width: rect.width, height: rect.height)
        guard panel.frame != target else { return }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        panel.setFrame(target, display: true)
        CATransaction.commit()
    }

    /// Runs only while a strip is shown (T-07-09): CG bounds reads, no AX.
    private func updateBackstop() {
        if shown.isEmpty {
            backstop?.invalidate()
            backstop = nil
            drift = [:]
        } else if backstop == nil {
            backstop = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated { self?.checkDrift() }
            }
        }
    }

    /// The 500 ms backstop (D-04): a strip whose selected window sits more than 2 pt from the planned content rect
    /// follows it; once the window is back, the strip returns to the planned frame.
    private func checkDrift() {
        let primaryHeight = NSScreen.screens.first?.frame.height ?? 0
        var seen: [GroupKey: Rect] = [:]
        for panel in shown.values.joined() {
            guard let strip = Self.view(panel)?.strip, let now = bounds?(strip.members[strip.selected]) else { continue }
            let followed = TabBand.strip(of: TabBand.frame(ofContent: now))
            let planned = abs(followed.x - strip.frame.x) <= 2 && abs(followed.y - strip.frame.y) <= 2 && abs(followed.width - strip.frame.width) <= 2
            if planned {
                place(panel, strip.frame, primaryHeight: primaryHeight)
            } else {
                if drift[strip.group] == followed { place(panel, followed, primaryHeight: primaryHeight) }
                seen[strip.group] = followed
            }
        }
        drift = seen
    }

    /// Orders this group's strip front (one of its members was just selected).
    func raise(_ group: GroupKey) {
        shown.values.joined().first { Self.view($0)?.strip.group == group }?.orderFrontRegardless()
    }

    private func fadeIn(_ panel: StripPanel) {
        panel.alphaValue = 0
        panel.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.12
            panel.animator().alphaValue = 1
        }
    }

    /// Fades out over 120 ms, then returns to the pool unless it was shown again meanwhile.
    private func fadeOut(_ panel: StripPanel) {
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

    private func makePanel(_ strip: TabStrip) -> StripPanel {
        let panel = StripPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        panel.ignoresMouseEvents = false
        panel.level = .normal
        panel.collectionBehavior = [.stationary, .ignoresCycle]
        panel.allowsToolTipsWhenApplicationIsInactive = true
        panel.sharingType = .none
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.animationBehavior = .none
        panel.hidesOnDeactivate = false
        panel.contentView = TabStripView(strip)
        return panel
    }

    /// `panel`, or a new one with its strip when macOS left it on another Space (`leftOnAnotherSpace`).
    private func onShownSpace(_ panel: StripPanel, _ displayUUID: String) -> StripPanel {
        guard let view = Self.view(panel), panel.leftOnAnotherSpace("display \(displayUUID): tab strip panel") else { return panel }
        panel.orderOut(nil)
        let new = makePanel(view.strip)
        new.setFrame(panel.frame, display: false)
        return new
    }

    private static func view(_ panel: StripPanel) -> TabStripView? { panel.contentView as? TabStripView }
}

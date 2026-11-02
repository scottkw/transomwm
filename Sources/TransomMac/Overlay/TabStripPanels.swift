import AppKit
import TransomEngine
import TransomModel
import os

/// Never key or main: a click on a tab leaves the frontmost app frontmost and never activates Transom (T-07-03).
private final class StripPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

/// An accessibility child of the strip (a tab or the overflow button) whose press runs `press`. Accessibility calls
/// arrive on the main thread.
nonisolated private final class PressElement: NSAccessibilityElement {
    private let press: @MainActor @Sendable () -> Void

    init(_ press: @escaping @MainActor @Sendable () -> Void) {
        self.press = press
        super.init()
    }

    override func accessibilityPerformPress() -> Bool {
        let press = press
        MainActor.assumeIsolated { press() }
        return true
    }
}

/// One group's strip (UI-SPEC Surface 2), drawn from `TabStripLayout`: `windowBackgroundColor`, 8 pt radius, 1 pt
/// `separatorColor` border inside, then capsule tabs (titled, icon-only, or icon-only with the overflow button); the
/// selected tab in Heading on a `labelColor` 16% fill. A tab acts on mouse-up with under 4 pt of travel. Flipped, so
/// the layout's top-left rects apply as they are.
final class TabStripView: NSView, NSViewToolTipOwner {
    var strip: TabStrip {
        didSet { changed() }
    }
    var onAction: ((TabAction) -> Void)?

    /// What the pointer is over.
    private enum Target: Equatable { case tab(Int), overflow, button(TabStripButton) }
    private var hovered: Target?
    private var press: (target: Target?, at: NSPoint)?
    /// The hover / pressed fill, faded in over 80 ms and out over 120 ms.
    private let hover = CALayer()
    private var elements: [NSAccessibilityElement]?

    init(_ strip: TabStrip) {
        self.strip = strip
        super.init(frame: .zero)
        wantsLayer = true
        hover.opacity = 0
        hover.cornerRadius = 10
        layer?.addSublayer(hover)
    }

    @available(*, unavailable) required init?(coder: NSCoder) { fatalError("not used") }

    override var isFlipped: Bool { true }

    /// Under this a press is still a click (UI-SPEC Spacing xs).
    private static let clickTravel: CGFloat = 4

    /// Close, Minimize, then Float Group on a docked group or Dock Group on a floating one (UI-SPEC Surface 2).
    private var buttons: [TabStripButton] { [.closeGroup, .minimizeGroup, strip.floating ? .dockGroup : .floatGroup] }

    private var layout: TabStripLayout {
        TabStripLayout(width: bounds.width, tabCount: strip.members.count, selected: strip.selected, buttons: buttons)
    }

    /// The group buttons laid out (none under 116 pt), with their rects.
    private var buttonRects: [(TabStripButton, Rect)] { Array(zip(buttons, layout.buttonRects)) }

    private static func ns(_ rect: Rect) -> NSRect { NSRect(x: rect.x, y: rect.y, width: rect.width, height: rect.height) }

    private func target(at point: NSPoint) -> Target? {
        let layout = layout
        if let button = layout.overflow?.button, Self.ns(button).contains(point) { return .overflow }
        if let button = buttonRects.first(where: { Self.ns($0.1).contains(point) }) { return .button(button.0) }
        return layout.tabRects.first { Self.ns($0.value).contains(point) }.map { .tab($0.key) }
    }

    /// Tab `i`'s tooltip and overflow item: its title, else its app name.
    private func title(_ i: Int) -> String {
        TabCopy.titleOrApp(title: strip.titles.indices.contains(i) ? strip.titles[i] : "", app: Self.appName(strip.members[i]))
    }

    /// The strip or the size changed: redraw, and rebuild the tooltip rects and accessibility children.
    private func changed() {
        needsDisplay = true
        elements = nil
        removeAllToolTips()
        let layout = layout
        for rect in layout.tabRects.values { addToolTip(Self.ns(rect), owner: self, userData: nil) }
        if let button = layout.overflow?.button { addToolTip(Self.ns(button), owner: self, userData: nil) }
        for (_, rect) in buttonRects { addToolTip(Self.ns(rect), owner: self, userData: nil) }
        updateHover()
    }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        changed()
    }

    func view(_ view: NSView, stringForToolTip tag: NSView.ToolTipTag, point: NSPoint, userData data: UnsafeMutableRawPointer?) -> String {
        switch target(at: point) {
        case .tab(let i)?: title(i)
        case .overflow?: TabCopy.moreTabs
        case .button(let button)?: Self.label(button)
        case nil: ""
        }
    }

    private static func label(_ button: TabStripButton) -> String {
        switch button {
        case .closeGroup: TabCopy.closeGroup
        case .minimizeGroup: TabCopy.minimizeGroup
        case .floatGroup: TabCopy.floatGroup
        case .dockGroup: TabCopy.dockGroup
        }
    }

    private static func symbol(_ button: TabStripButton) -> String {
        switch button {
        case .closeGroup: "xmark"
        case .minimizeGroup: "minus"
        case .floatGroup: "macwindow"
        case .dockGroup: "rectangle.split.2x1"
        }
    }

    /// An SF Symbol centred in `rect`, `labelColor` when hovered or pressed, else `secondaryLabelColor`.
    private func drawGlyph(_ name: String, in rect: NSRect, active: Bool) {
        let color: NSColor = active ? .labelColor : .secondaryLabelColor
        let config = NSImage.SymbolConfiguration(textStyle: .body, scale: .small).applying(NSImage.SymbolConfiguration(paletteColors: [color]))
        guard let glyph = NSImage(systemSymbolName: name, accessibilityDescription: nil)?.withSymbolConfiguration(config) else { return }
        let size = glyph.size
        glyph.draw(
            in: NSRect(x: rect.midX - size.width / 2, y: rect.midY - size.height / 2, width: size.width, height: size.height),
            from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
    }

    override func draw(_ dirtyRect: NSRect) {
        let contrast = NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast
        let outline = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: 8, yRadius: 8)
        NSColor.windowBackgroundColor.setFill()
        outline.fill()
        NSColor.separatorColor.setStroke()
        outline.lineWidth = 1
        outline.stroke()
        let layout = layout
        for (i, rect) in layout.tabRects { drawTab(i, Self.ns(rect), titled: layout.mode == .titled, contrast: contrast) }
        if let button = layout.overflow?.button { drawGlyph("chevron.down", in: Self.ns(button), active: hovered == .overflow) }
        let active = hovered
        for (button, rect) in buttonRects { drawGlyph(Self.symbol(button), in: Self.ns(rect), active: active == .button(button)) }
        updateHover()  // the fill colour re-resolves with the appearance and Increase Contrast
    }

    private func drawTab(_ i: Int, _ rect: NSRect, titled: Bool, contrast: Bool) {
        let isSelected = i == strip.selected
        let capsule = NSBezierPath(roundedRect: rect, xRadius: rect.height / 2, yRadius: rect.height / 2)
        if isSelected {
            NSColor.labelColor.withAlphaComponent(contrast ? 0.24 : 0.16).setFill()
            capsule.fill()
            if contrast {
                NSColor.labelColor.setStroke()
                capsule.lineWidth = 1
                capsule.stroke()
            }
        }
        let iconX = titled ? rect.minX + 8 : rect.midX - 8
        Self.icon(strip.members[i].pid)?.draw(
            in: NSRect(x: iconX, y: rect.midY - 8, width: 16, height: 16), from: .zero, operation: .sourceOver, fraction: 1,
            respectFlipped: true, hints: nil)
        guard titled else { return }
        let x = iconX + 16 + 4, width = rect.maxX - 8 - x
        guard width > 8 else { return }
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byTruncatingMiddle
        let text = NSAttributedString(string: title(i), attributes: [
            .font: NSFont.preferredFont(forTextStyle: isSelected ? .headline : .body),
            .foregroundColor: isSelected ? NSColor.labelColor : NSColor.secondaryLabelColor,
            .paragraphStyle: paragraph,
        ])
        let height = text.size().height
        text.draw(with: NSRect(x: x, y: rect.midY - height / 2, width: width, height: height), options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine])
    }

    /// Places the hover fill (`labelColor` 8%, pressed 16%, × 1.5 with Increase Contrast) on the hovered or pressed
    /// unselected tab or the overflow button, fading it in over 80 ms and out over 120 ms.
    private func updateHover() {
        // A press shows its fill only while the pointer is over what it pressed.
        let target = press.map { $0.target == hovered ? $0.target : nil } ?? hovered, layout = layout
        let rect: Rect? = switch target {
        case .tab(let i)? where i != strip.selected: layout.tabRects[i]
        case .overflow?: layout.overflow?.button
        case .button(let button)?: buttonRects.first { $0.0 == button }?.1
        default: nil
        }
        let alpha = (press == nil ? 0.08 : 0.16) * (NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast ? 1.5 : 1)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        if let rect { hover.frame = Self.ns(rect) }
        effectiveAppearance.performAsCurrentDrawingAppearance {
            hover.backgroundColor = NSColor.labelColor.withAlphaComponent(alpha).cgColor
        }
        CATransaction.commit()
        let opacity: Float = rect == nil ? 0 : 1
        guard hover.opacity != opacity else { return }
        let animation = CABasicAnimation(keyPath: "opacity")
        animation.fromValue = hover.presentation()?.opacity ?? hover.opacity
        animation.toValue = opacity
        animation.duration = opacity == 1 ? 0.08 : 0.12
        hover.opacity = opacity
        hover.add(animation, forKey: "fade")
    }

    // MARK: Accessibility (UI-SPEC Accessibility): a tab group of radio-button tabs; overflowed tabs are still children.

    override func isAccessibilityElement() -> Bool { true }
    override func accessibilityRole() -> NSAccessibility.Role? { .tabGroup }
    override func accessibilityLabel() -> String? { TabCopy.stripLabel(count: strip.members.count) }

    override func accessibilityChildren() -> [Any]? {
        if let elements { return elements }
        let layout = layout, count = strip.members.count
        let overflowFrame = layout.overflow.map { Self.ns($0.button) } ?? .zero
        var made: [NSAccessibilityElement] = strip.members.indices.map { i in
            let tab = PressElement { [weak self] in self?.select(i, via: .click) }
            tab.setAccessibilityRole(.radioButton)
            tab.setAccessibilitySubrole(.tabButtonSubrole)  // `.tabButton` does not compile (Pitfall 11)
            tab.setAccessibilityLabel(TabCopy.tabLabel(app: Self.appName(strip.members[i]), title: strip.titles.indices.contains(i) ? strip.titles[i] : ""))
            tab.setAccessibilityValue(i == strip.selected ? 1 : 0)
            tab.setAccessibilityHelp(TabCopy.tabHelp(index: i + 1, count: count))
            tab.setAccessibilityParent(self)
            tab.setAccessibilityFrameInParentSpace(layout.tabRects[i].map(Self.ns) ?? overflowFrame)
            return tab
        }
        if let overflow = layout.overflow {
            let button = PressElement { [weak self] in self?.openOverflow() }
            button.setAccessibilityRole(.button)
            button.setAccessibilityLabel(TabCopy.moreTabs)
            button.setAccessibilityHelp(TabCopy.moreTabsHelp(overflow.hidden.count))
            button.setAccessibilityParent(self)
            button.setAccessibilityFrameInParentSpace(overflowFrame)
            made.append(button)
        }
        for (kind, rect) in buttonRects {
            let button = PressElement { [weak self] in self?.press(kind) }
            button.setAccessibilityRole(.button)
            button.setAccessibilityLabel(Self.label(kind))
            if kind == .closeGroup { button.setAccessibilityHelp(TabCopy.closeGroupHelp(count)) }
            button.setAccessibilityParent(self)
            button.setAccessibilityFrameInParentSpace(Self.ns(rect))
            made.append(button)
        }
        elements = made
        return made
    }

    // MARK: Pointer

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .mouseMoved, .activeAlways, .inVisibleRect], owner: self))
    }

    override func mouseMoved(with event: NSEvent) { setHovered(target(at: convert(event.locationInWindow, from: nil))) }

    /// A pressed button shows its pressed fill only while the pointer is still over it (standard button tracking).
    override func mouseDragged(with event: NSEvent) {
        guard case .button? = press?.target else { return }
        setHovered(target(at: convert(event.locationInWindow, from: nil)))
    }
    override func mouseExited(with event: NSEvent) { setHovered(nil) }

    private func setHovered(_ target: Target?) {
        guard target != hovered else { return }
        hovered = target
        needsDisplay = true  // the overflow glyph's colour
        updateHover()
    }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        press = (target(at: point), point)
        hovered = press?.target
        updateHover()
        needsDisplay = true  // a pressed button's glyph
    }

    /// A click on a tab selects it, on the overflow button opens its menu, on the background focuses the selected
    /// member. A double-click is one click. A group button acts on mouse-up inside it, however far the pointer
    /// travelled meanwhile; released outside, it does nothing.
    override func mouseUp(with event: NSEvent) {
        guard let press else { return }
        self.press = nil
        updateHover()
        needsDisplay = true
        let point = convert(event.locationInWindow, from: nil)
        guard target(at: point) == press.target, event.clickCount <= 1 else { return }
        if case .button(let button)? = press.target { return self.press(button) }
        guard hypot(point.x - press.at.x, point.y - press.at.y) < Self.clickTravel else { return }
        switch press.target {
        case .overflow?: openOverflow()
        case .tab(let i)?: select(i, via: .click)
        case .button?: break
        case nil: select(strip.selected, via: .click)
        }
    }

    private func press(_ button: TabStripButton) {
        switch button {
        case .closeGroup: onAction?(.closeGroup(strip.group))
        case .minimizeGroup: onAction?(.minimizeGroup(strip.group))
        case .floatGroup, .dockGroup: onAction?(.toggleGroupFloat(strip.group))
        }
    }

    private func select(_ i: Int, via source: TabSelectSource) {
        guard strip.members.indices.contains(i) else { return }
        onAction?(.select(strip.members[i], via: source))
    }

    /// The members not in the strip, in group order (16 pt icon + title, the app name when untitled), below the button.
    private func openOverflow() {
        guard let overflow = layout.overflow else { return }
        let menu = NSMenu()
        for i in overflow.hidden {
            let item = NSMenuItem(title: title(i), action: #selector(chooseOverflow(_:)), keyEquivalent: "")
            item.target = self
            item.tag = i
            if let icon = Self.icon(strip.members[i].pid)?.copy() as? NSImage {
                icon.size = NSSize(width: 16, height: 16)
                item.image = icon
            }
            menu.addItem(item)
        }
        let button = Self.ns(overflow.button)
        menu.popUp(positioning: nil, at: NSPoint(x: button.minX, y: button.maxY), in: self)
    }

    @objc private func chooseOverflow(_ item: NSMenuItem) { select(item.tag, via: .overflow) }

    private static var icons: [Int32: NSImage] = [:]

    private static func icon(_ pid: Int32) -> NSImage? {
        if let icon = icons[pid] { return icon }
        let icon = NSRunningApplication(processIdentifier: pid)?.icon
        icons[pid] = icon
        return icon
    }

    /// The untruncated app name; `TabCopy` truncates it.
    private static func appName(_ window: TransomModel.WindowRef) -> String {
        NSRunningApplication(processIdentifier: window.pid)?.localizedName ?? window.bundleID
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
    /// Per display, the Space its shown strips belong to.
    private var spaces: [String: UInt64] = [:]
    private static let logger = Logger(subsystem: "com.eightabyte.transom", category: "tabs")

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
    func show(_ strips: [TabStrip], on displayUUID: String, space: UInt64?) {
        spaces[displayUUID] = space
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

    /// Orders this group's strip front (one of its members was just selected). A strip out for a Space change stays out.
    func raise(_ group: GroupKey) {
        shown.values.joined().first { $0.isVisible && Self.view($0)?.strip.group == group }?.orderFrontRegardless()
    }

    /// The display now shows `space`, before the Arranger re-plans (UI-SPEC Surface 2, Space changes): its strips are
    /// ordered out at once (macOS is animating), or faded back in when they belong to `space`, which covers a return
    /// while arranging is paused and no new strips come. The replan's strips for the new desk then replace them.
    func spaceChanged(displayUUID: String, to space: UInt64?) {
        guard let space else { return }  // Spaces unknown: macOS keeps each strip on its own Space
        let panels = shown[displayUUID] ?? []
        if space == spaces[displayUUID] {
            for panel in panels where !panel.isVisible { fadeIn(panel) }
        } else {
            for panel in panels { panel.orderOut(nil) }
        }
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

    /// `panel`, or a new one with its strip when macOS left it, still ordered in, on another Space
    /// (`leftOnAnotherSpace`). Never asked of a hidden panel: an ordered-out one reports off the active Space too,
    /// and ordering it in brings it to the shown one (Pitfall 8, no churn).
    private func onShownSpace(_ panel: StripPanel, _ displayUUID: String) -> StripPanel {
        guard panel.isVisible, let view = Self.view(panel),
            panel.leftOnAnotherSpace("display \(displayUUID): tab strip for group \(view.strip.group.node)")
        else { return panel }
        Self.logger.info("strip for group \(view.strip.group.node, privacy: .public) replaced: left on another Space")
        panel.orderOut(nil)
        let new = makePanel(view.strip)
        new.setFrame(panel.frame, display: false)
        return new
    }

    private static func view(_ panel: StripPanel) -> TabStripView? { panel.contentView as? TabStripView }
}

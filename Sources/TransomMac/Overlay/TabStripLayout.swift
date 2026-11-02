import TransomModel

/// A group button on the strip (UI-SPEC Surface 2), left to right.
nonisolated enum TabStripButton: Equatable, Sendable {
    case closeGroup, minimizeGroup, floatGroup, dockGroup
}

/// The strip's geometry in points, top-left inside the strip (UI-SPEC Surface 2, Spacing exceptions): group buttons,
/// then equal tabs 4 pt apart; under 96 pt a tab drops its title, under 32 pt the overflow button takes the right end
/// and the tabs that do not fit go to its menu, the selected one always kept. No AppKit, so it is unit-tested.
nonisolated struct TabStripLayout {
    enum Mode: Equatable { case titled, iconOnly }

    static let minimumTitledWidth = 96.0
    static let minimumIconWidth = 32.0
    /// 4 + 3 × 20 + 2 × 4 + 8 + 32 + 4: under it the group buttons hide.
    static let minimumButtonsWidth = 116.0
    private static let padding = 4.0
    private static let control = 20.0

    var buttonRects: [Rect] = []
    /// The tabs in the strip, by member index.
    var tabRects: [Int: Rect] = [:]
    var mode = Mode.titled
    var overflow: (button: Rect, hidden: [Int])?

    init(width: Double, tabCount: Int, selected: Int, buttons: [TabStripButton]) {
        let p = Self.padding, size = Self.control
        if width >= Self.minimumButtonsWidth {
            buttonRects = buttons.indices.map { Rect(x: p + Double($0) * (size + p), y: p, width: size, height: size) }
        }
        let start = buttonRects.last.map { $0.x + size + 8 } ?? p, end = width - p
        guard tabCount > 0 else { return }
        let n = Double(tabCount), equal = (end - start - p * (n - 1)) / n
        func tab(_ slot: Int, _ w: Double) -> Rect { Rect(x: start + Double(slot) * (w + p), y: p, width: w, height: size) }
        if equal >= Self.minimumIconWidth {
            mode = equal >= Self.minimumTitledWidth ? .titled : .iconOnly
            for i in 0..<tabCount { tabRects[i] = tab(i, equal) }
            return
        }
        mode = .iconOnly
        let button = Rect(x: end - size, y: p, width: size, height: size)
        // As many 32 pt tabs, 4 pt apart, as fit before the 4 pt gap left of the button.
        let slots = min(tabCount, max(1, Int((button.x - start) / (Self.minimumIconWidth + p))))
        var visible = Array(0..<slots)
        if !visible.contains(selected), tabCount > selected, selected >= 0 { visible[slots - 1] = selected }
        for (slot, i) in visible.enumerated() { tabRects[i] = tab(slot, Self.minimumIconWidth) }
        overflow = (button, (0..<tabCount).filter { !visible.contains($0) })
    }
}

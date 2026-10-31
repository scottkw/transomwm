import TransomModel

/// A key that moves the overview's selection (06 UI-SPEC Surface 3).
public enum OverviewKey: Sendable {
    case left, right, up, down, tab, backTab
}

/// The overview's one selection across every display (D-04, 06 UI-SPEC Surface 3), shared by the pointer and the keys.
public struct OverviewSelection: Equatable, Sendable {
    public var selected: OverviewItem?
    /// The display the selected item is on.
    public var display: String?

    public init(selected: OverviewItem? = nil, display: String? = nil) {
        self.selected = selected
        self.display = display
    }

    /// The selection when the overview opens: the focused window if it is shown, else the largest tile on the pointer's
    /// display.
    public static func initial(layout: OverviewLayout, focused: WindowRef?, pointer: Point?) -> OverviewSelection {
        if let focused, let display = layout.displays.first(where: { $0.tiles.contains { $0.window == focused } }) {
            return OverviewSelection(selected: .tile(focused), display: display.uuid)
        }
        guard let pointer, let display = layout.display(at: pointer), let tile = largest(display.tiles) else { return OverviewSelection() }
        return OverviewSelection(selected: .tile(tile.window), display: display.uuid)
    }

    /// Moves the selection as `key` asks; at an edge nothing changes (no beep: repeat-safe).
    public mutating func reselect(afterRemoving window: WindowRef, in layout: OverviewLayout) {}

    public mutating func move(_ key: OverviewKey, in layout: OverviewLayout, focused: WindowRef? = nil) {
        guard case .tile(let window)? = selected, let display = layout.displays.first(where: { $0.uuid == self.display }),
            let from = display.tiles.first(where: { $0.window == window }),
            let next = Self.nearest(from: from.rect, toward: key, among: display.tiles.filter { $0.window != window })
        else { return }
        selected = .tile(next.window)
    }

    /// The Phase 3 focus-direction rule: the nearest centre within 45° of `key`'s direction, else the nearest centre on
    /// that side. `candidates` are back to front, so on equal distances the later (front-most) one wins.
    static func nearest(from rect: Rect, toward key: OverviewKey, among candidates: [OverviewTile]) -> OverviewTile? {
        let (dx, dy): (Double, Double)
        switch key {
        case .left: (dx, dy) = (-1, 0)
        case .right: (dx, dy) = (1, 0)
        case .up: (dx, dy) = (0, -1)
        case .down: (dx, dy) = (0, 1)
        case .tab, .backTab: return nil
        }
        var cone: (distance: Double, index: Int)?, side: (distance: Double, index: Int)?
        for (index, candidate) in candidates.enumerated() {
            let vx = candidate.rect.midX - rect.midX, vy = candidate.rect.midY - rect.midY
            let along = vx * dx + vy * dy
            guard along > 0 else { continue }
            let distance = (vx * vx + vy * vy).squareRoot()
            if abs(vx * dy - vy * dx) <= along, distance <= (cone?.distance ?? .infinity) + tolerance { cone = (distance, index) }
            if distance <= (side?.distance ?? .infinity) + tolerance { side = (distance, index) }
        }
        return (cone ?? side).map { candidates[$0.index] }
    }

    /// The largest tile by area; on equal areas the front-most.
    static func largest(_ tiles: [OverviewTile]) -> OverviewTile? {
        tiles.reduce(nil) { best, tile in
            tile.rect.width * tile.rect.height >= (best.map { $0.rect.width * $0.rect.height } ?? 0) - tolerance ? tile : best
        }
    }

    /// Distances and areas this close count as equal, so ties resolve the same way on every run.
    static let tolerance = 0.001
}

extension OverviewLayout {
    /// The display the pointer is on: the one whose visibleFrame holds it, else the nearest (the menu bar, the Dock).
    func display(at point: Point) -> OverviewDisplayLayout? {
        func distance(_ rect: Rect) -> Double {
            let dx = max(rect.minX - point.x, 0, point.x - rect.maxX), dy = max(rect.minY - point.y, 0, point.y - rect.maxY)
            return dx * dx + dy * dy
        }
        return displays.min { distance($0.visibleFrame) < distance($1.visibleFrame) }
    }
}

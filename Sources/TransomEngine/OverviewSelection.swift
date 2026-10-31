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

    /// The selection when the overview opens: the focused window if it is shown; else the pointer display's initial item
    /// (the tile under the pointer, its largest tile, its current-Space thumbnail); else the largest tile on the first
    /// display left to right that has one.
    public static func initial(layout: OverviewLayout, focused: WindowRef?, pointer: Point?) -> OverviewSelection {
        if let focused, let display = layout.displays.first(where: { $0.tiles.contains { $0.window == focused } }) {
            return OverviewSelection(selected: .tile(focused), display: display.uuid)
        }
        if let pointer, let display = layout.display(at: pointer), let item = initial(on: display, focused: nil, pointer: pointer) {
            return OverviewSelection(selected: item, display: display.uuid)
        }
        guard let display = layout.ordered.first(where: { !$0.tiles.isEmpty }), let tile = largest(display.tiles) else { return OverviewSelection() }
        return OverviewSelection(selected: .tile(tile.window), display: display.uuid)
    }

    /// One display's initial item: the focused window, the tile under the pointer, the largest tile, the current-Space
    /// thumbnail, in that order.
    static func initial(on display: OverviewDisplayLayout, focused: WindowRef?, pointer: Point?) -> OverviewItem? {
        if let focused, display.tiles.contains(where: { $0.window == focused }) { return .tile(focused) }
        if let pointer, let tile = display.tiles.last(where: { $0.rect.contains(pointer) }) { return .tile(tile.window) }
        if let tile = largest(display.tiles) { return .tile(tile.window) }
        return display.thumbnails.first(where: \.isCurrent).map { .thumbnail(space: $0.spaceID) }
    }

    /// Moves the selection as `key` asks; at an edge nothing changes (no beep: repeat-safe). Arrows stay on the selected
    /// item's display and never land on a mini tile; from a mini tile they act as from its thumbnail. Tab and ⇧Tab land on
    /// the next or previous display's initial item (`focused` counts there; the pointer does not).
    public mutating func move(_ key: OverviewKey, in layout: OverviewLayout, focused: WindowRef? = nil) {
        guard let selected, let display = layout.displays.first(where: { $0.uuid == self.display }) else { return }
        if key == .tab || key == .backTab { return tab(forward: key == .tab, from: display, in: layout, focused: focused) }
        switch selected {
        case .tile(let window):
            guard let from = display.tiles.first(where: { $0.window == window }) else { return }
            if let next = Self.nearest(from: from.rect, toward: key, among: display.tiles.filter { $0.window != window }) {
                self.selected = .tile(next.window)
            } else if key == .up, let thumb = Self.nearestInX(from.rect.midX, display.thumbnails, x: \.rect.midX) {
                self.selected = .thumbnail(space: thumb.spaceID)  // ↑ from the top row: into the strip
            }
        case .thumbnail(let space), .miniTile(_, let space):
            guard let index = display.thumbnails.firstIndex(where: { $0.spaceID == space }) else { return }
            let thumb = display.thumbnails[index]
            switch key {
            case .left where index > 0: self.selected = .thumbnail(space: display.thumbnails[index - 1].spaceID)
            case .right where index + 1 < display.thumbnails.count: self.selected = .thumbnail(space: display.thumbnails[index + 1].spaceID)
            case .down:
                if let tile = Self.nearestInX(thumb.rect.midX, display.tiles, x: \.rect.midX) { self.selected = .tile(tile.window) }
            default: break
            }
        }
    }

    private mutating func tab(forward: Bool, from display: OverviewDisplayLayout, in layout: OverviewLayout, focused: WindowRef?) {
        let order = layout.ordered
        guard let start = order.firstIndex(where: { $0.uuid == display.uuid }) else { return }
        for step in 1..<max(order.count, 1) {
            let next = order[(start + (forward ? step : order.count - step)) % order.count]
            if let item = Self.initial(on: next, focused: focused, pointer: nil) {
                (selected, self.display) = (item, next.uuid)
                return
            }
        }
    }

    /// The selected window closed while open: the nearest remaining tile on its display, else that display's current-Space
    /// thumbnail. A closed window shown as a mini tile leaves its thumbnail selected. Any other close changes nothing.
    public mutating func reselect(afterRemoving window: WindowRef, in layout: OverviewLayout) {
        guard let display = layout.displays.first(where: { $0.uuid == self.display }) else { return }
        switch selected {
        case .tile(window)?:
            let rest = display.tiles.filter { $0.window != window }
            if let from = display.tiles.first(where: { $0.window == window }), let tile = Self.nearestCentre(to: from.rect, among: rest) {
                selected = .tile(tile.window)
            } else {
                selected = display.thumbnails.first(where: \.isCurrent).map { .thumbnail(space: $0.spaceID) }
            }
        case .miniTile(window, let space)?: selected = .thumbnail(space: space)
        default: break
        }
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

    /// The nearest centre to `rect`'s; on equal distances the front-most.
    static func nearestCentre(to rect: Rect, among tiles: [OverviewTile]) -> OverviewTile? {
        func distance(_ tile: OverviewTile) -> Double {
            let dx = tile.rect.midX - rect.midX, dy = tile.rect.midY - rect.midY
            return (dx * dx + dy * dy).squareRoot()
        }
        return tiles.reduce(nil) { best, tile in distance(tile) <= (best.map(distance) ?? .infinity) + tolerance ? tile : best }
    }

    /// The item whose centre is nearest `target` in x; on equal distances the later (front-most) one.
    static func nearestInX<T>(_ target: Double, _ items: [T], x centre: (T) -> Double) -> T? {
        func distance(_ item: T) -> Double { abs(centre(item) - target) }
        return items.reduce(nil) { best, item in distance(item) <= (best.map(distance) ?? .infinity) + tolerance ? item : best }
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

    /// Displays left to right by frame; ties by top edge, then UUID (OVER-01 ordering edge).
    var ordered: [OverviewDisplayLayout] {
        displays.sorted {
            ($0.visibleFrame.minX, $0.visibleFrame.minY, $0.uuid) < ($1.visibleFrame.minX, $1.visibleFrame.minY, $1.uuid)
        }
    }
}

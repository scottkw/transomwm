import Foundation
import TransomModel

/// One saved view (D-02): the desk it was saved on and the identities of the windows inside it, or `home` for a
/// whole-desk view. Never a NodeID or a rect: going back finds the smallest node holding the windows still there.
public struct SavedView: Codable, Equatable, Sendable {
    public var slot: ViewSlot
    public var desk: DeskKey
    public var home: Bool
    /// Sorted.
    public var windows: [WindowIdentity]

    public init(slot: ViewSlot, desk: DeskKey, home: Bool, windows: [WindowIdentity]) {
        self.slot = slot
        self.desk = desk
        self.home = home
        self.windows = windows.sorted()
    }
}

/// The nine slots (D-01). A slot is only ever filled or replaced, never emptied (D-16).
public struct SavedViews: Equatable, Sendable {
    private var slots: [ViewSlot: SavedView] = [:]

    public init() {}

    public subscript(slot: ViewSlot) -> SavedView? { slots[slot] }

    /// Stores `view` in its slot; true when that replaced an earlier view (D-15).
    @discardableResult
    public mutating func save(_ view: SavedView) -> Bool {
        slots.updateValue(view, forKey: view.slot) != nil
    }

    /// By slot.
    public var sorted: [SavedView] { slots.values.sorted { $0.slot < $1.slot } }
}

import Foundation

/// A window floating on a desk's Desktop layer, with its frame in desk coordinates (the global
/// top-left space described in Geometry.swift).
public struct FloatingWindow: Codable, Equatable, Sendable {
    public let window: WindowRef
    public var frame: Rect
    public var state: WindowState
}

/// The floating windows of one desk, back to front. Every method checks before it mutates, so a
/// throwing call leaves the layer unchanged.
public struct DesktopLayer: Codable, Equatable, Sendable {
    public private(set) var windows: [FloatingWindow]

    public init() {
        windows = []
    }

    /// Adds `window` in front of the others, as `.present`.
    public mutating func add(_ window: WindowRef, frame: Rect) throws(LayoutError) {
        guard !contains(window) else { throw .duplicateWindow(window) }
        guard frame.isValidGeometry else { throw .invalidGeometry("floating frame of \(window) is not finite or out of range") }
        windows.append(FloatingWindow(window: window, frame: frame, state: .present))
    }

    public mutating func remove(_ window: WindowRef) throws(LayoutError) {
        guard let index = index(of: window) else { throw .windowNotFound(window) }
        windows.remove(at: index)
    }

    public mutating func setFrame(_ frame: Rect, for window: WindowRef) throws(LayoutError) {
        guard let index = index(of: window) else { throw .windowNotFound(window) }
        guard frame.isValidGeometry else { throw .invalidGeometry("floating frame of \(window) is not finite or out of range") }
        windows[index].frame = frame
    }

    /// Stores a lifecycle state, keeping the frame. `.closed` is not storable: `World.apply(.closed, …)`
    /// closes a floating window through `remove`, after the same two-source confirmation as docked windows.
    public mutating func setState(_ state: WindowState, for window: WindowRef) throws(LayoutError) {
        guard let index = index(of: window) else { throw .windowNotFound(window) }
        guard state != .closed else { throw .invariantViolated("closed is a transition, not a stored state; close \(window) through World.apply") }
        windows[index].state = state
    }

    /// Re-points a floating window to the ID macOS corrected it to (02-16), keeping its frame, state and
    /// place in the stacking order.
    public mutating func rekey(from: WindowRef, to: WindowRef) throws(LayoutError) {
        guard let index = index(of: from) else { throw .windowNotFound(from) }
        guard !contains(to) else { throw .duplicateWindow(to) }
        windows[index] = FloatingWindow(window: to, frame: windows[index].frame, state: windows[index].state)
    }

    /// Replaces each window's ref with `change(ref)`, which must keep its identity (World.withoutTitleHints).
    mutating func mapWindows(_ change: (WindowRef) -> WindowRef) {
        windows = windows.map { FloatingWindow(window: change($0.window), frame: $0.frame, state: $0.state) }
    }

    public func frame(of window: WindowRef) -> Rect? {
        index(of: window).map { windows[$0].frame }
    }

    public func contains(_ window: WindowRef) -> Bool { index(of: window) != nil }

    /// Unique identities, valid frames, and no stored `.closed` state. Decoding does not check
    /// this on its own; `World` validates every desk it is built from.
    public func validate() throws(LayoutError) {
        var seen: Set<WindowIdentity> = []
        for floating in windows {
            guard seen.insert(floating.window.identity).inserted else { throw .duplicateWindow(floating.window) }
            guard floating.frame.isValidGeometry else {
                throw .invalidGeometry("floating frame of \(floating.window) is not finite or out of range")
            }
            guard floating.state != .closed else {
                throw .invariantViolated("floating \(floating.window) is stored as closed; closed windows must be removed")
            }
        }
    }

    private func index(of window: WindowRef) -> Int? {
        windows.firstIndex { $0.window == window }
    }
}

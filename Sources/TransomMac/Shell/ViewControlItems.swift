import AppKit
import Observation
import TransomEngine
import os

/// A view control the user can put in the menu bar (D-13).
nonisolated enum MenuBarControl: String, Codable, CaseIterable, Sendable {
    case back, forward, views
}

nonisolated struct MenuBarItem: Codable, Equatable, Sendable {
    var control: MenuBarControl
    var enabled: Bool
}

/// Settings ▸ Menu Bar's choices (UI-SPEC Tab 6), kept in UserDefaults. The plist is user-writable (T-09-39): a stored
/// list that doesn't decode, or doesn't hold each control exactly once, is logged and removed.
@Observable @MainActor final class MenuBarPreference {
    static let itemsKey = "menuBar.items"
    static let iconOnlyKey = "menuBar.iconOnly"
    static let defaultItems = MenuBarControl.allCases.map { MenuBarItem(control: $0, enabled: false) }
    /// Left to right, as they show in the menu bar.
    private(set) var items: [MenuBarItem]
    private(set) var iconOnly: Bool
    /// Fires after every change.
    @ObservationIgnored var onChange: (() -> Void)?
    @ObservationIgnored private let defaults: UserDefaults
    private static let logger = Logger(subsystem: "com.eightabyte.transom", category: "preferences")

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        iconOnly = defaults.bool(forKey: Self.iconOnlyKey)
        items = Self.defaultItems
        guard let stored = defaults.object(forKey: Self.itemsKey) else { return }
        if let data = stored as? Data, let decoded = try? JSONDecoder().decode([MenuBarItem].self, from: data),
            Set(decoded.map(\.control)).count == MenuBarControl.allCases.count, decoded.count == MenuBarControl.allCases.count {
            items = decoded
        } else {
            Self.logger.error("removed a stored menu bar list that wasn't each control once")
            defaults.removeObject(forKey: Self.itemsKey)
        }
    }

    func setEnabled(_ control: MenuBarControl, _ enabled: Bool) {
        guard let index = items.firstIndex(where: { $0.control == control }), items[index].enabled != enabled else { return }
        items[index].enabled = enabled
        save()
    }

    func setIconOnly(_ on: Bool) {
        guard on != iconOnly else { return }
        iconOnly = on
        defaults.set(on, forKey: Self.iconOnlyKey)
        onChange?()
    }

    private func save() {
        // Encoding a fixed enum and a Bool can't fail.
        defaults.set(try! JSONEncoder().encode(items), forKey: Self.itemsKey)
        onChange?()
    }
}

/// One view-control status item: what it shows and does (UI-SPEC Surface 4).
nonisolated struct ViewControlSpec: Equatable, Sendable {
    enum Kind: Equatable, Sendable {
        case back, forward
        case view(Int)
    }

    var kind: Kind
    var symbol: String
    var description: String
    var appearsDisabled: Bool

    var command: Command {
        switch kind {
        case .back: .camera(.back)
        case .forward: .camera(.forward)
        case .view(let n): .camera(.view(ViewSlot(n)!))  // slots come from the engine's saved views, 1–9
        }
    }
}

/// The optional Back, Forward and saved-view status items, left of the Transom icon in the Settings order (SHIP-06,
/// RESEARCH Pattern 8). A click dispatches the hotkey's command, so refusal and history rules are the hotkey's (T-09-40).
@MainActor final class ViewControlItems: NSObject {
    private let dispatch: (Command) -> Void
    private var items: [NSStatusItem] = []
    private var shown: [ViewControlSpec] = []

    init(dispatch: @escaping (Command) -> Void) {
        self.dispatch = dispatch
    }

    /// The specs, left to right. Empty while zoom is off.
    nonisolated static func layout(
        items: [MenuBarItem], iconOnly: Bool, zoomOn: Bool, paused: Bool, slots: [Int], current: Int?, backAvailable: Bool,
        forwardAvailable: Bool
    ) -> [ViewControlSpec] {
        guard zoomOn else { return [] }
        return items.filter(\.enabled).flatMap { (item: MenuBarItem) -> [ViewControlSpec] in
            switch item.control {
            case .back: [ViewControlSpec(kind: .back, symbol: "chevron.backward", description: ViewCopy.back, appearsDisabled: false)]
            case .forward: [ViewControlSpec(kind: .forward, symbol: "chevron.forward", description: ViewCopy.forward, appearsDisabled: false)]
            case .views: []
            }
        }
    }

    /// Recreates the items when the specs change. New status items land left of existing ones, so they are made right to
    /// left. No saved position name: a ⌘-drag must not fight the Settings order (UI-SPEC planner note 6).
    func refresh(_ specs: [ViewControlSpec]) {
        guard specs != shown else { return }
        shown = specs
        for item in items { NSStatusBar.system.removeStatusItem(item) }
        items = []
        for (index, spec) in specs.enumerated().reversed() {
            let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
            if let button = item.button {
                // The default symbol size: a forced point size clips on 1x displays (quick 261106-bru).
                let image = NSImage(systemSymbolName: spec.symbol, accessibilityDescription: spec.description)
                image?.isTemplate = true
                button.image = image
                button.toolTip = spec.description
                button.setAccessibilityLabel(spec.description)
                button.appearsDisabled = spec.appearsDisabled
                button.tag = index
                button.target = self
                button.action = #selector(clicked)
            }
            items.append(item)
        }
    }

    @objc private func clicked(_ sender: NSStatusBarButton) {
        guard shown.indices.contains(sender.tag) else { return }
        dispatch(shown[sender.tag].command)
    }
}

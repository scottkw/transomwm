import AppKit
import KeyboardShortcuts
import TransomEngine
import TransomModel

/// The status menu's command items (TILE-09, D-09). Each is created once and given its hotkey once, so
/// KeyboardShortcuts' `setShortcut` observers never pile up across menu opens (RESEARCH Pattern 9); the menu
/// re-inserts these same items every time it opens. Every item calls `dispatch` with its Command, the same
/// call its hotkey makes. Later plans add their rows to `commands`.
@MainActor final class CommandMenu: NSObject, NSMenuItemValidation {
    /// Every command with a menu item, in no particular order: the status menu places them.
    static let commands: [Command] = [
        .dock, .float, .undo, .focus(.left), .focus(.right), .focus(.top), .focus(.bottom), .finderSplit,
        .togglePause, .toggleExcludeFrontmost, .moveOrSnap(.left), .moveOrSnap(.right), .moveOrSnap(.top), .moveOrSnap(.bottom),
        .swapPrevious, .growTile, .shrinkTile, .balanceSplit, .rotateSplit, .flipSplit, .snap(.leftThird), .snap(.centerThird),
        .snap(.rightThird), .snap(.topLeft), .snap(.topRight), .snap(.bottomLeft), .snap(.bottomRight), .snap(.maximize), .snap(.center),
        .arrangeAll, .floatAll, .restoreAll,
        .camera(.zoomOutAll), .camera(.stepOut), .camera(.stepIn), .camera(.back), .camera(.forward), .camera(.pan(.left)),
        .camera(.pan(.right)), .camera(.pan(.top)), .camera(.pan(.bottom)), .camera(.frameWindow),
        .camera(.overview), .tabs(.next), .tabs(.previous), .tabs(.moveOut),
    ] + halfColumns + halfRows + corners + thirdColumns + thirdRows + fourthColumns + fourthRows

    private static let halfColumns: [Command] = [.dockFourth(.firstHalf, .horizontal), .dockFourth(.secondHalf, .horizontal)]
    private static let halfRows: [Command] = [.dockFourth(.firstHalf, .vertical), .dockFourth(.secondHalf, .vertical)]
    private static let corners: [Command] = DockCorner.allCases.map { .dockCorner($0) }
    private static let thirdColumns: [Command] = thirdSlots.map { .dockFourth($0, .horizontal) }
    private static let thirdRows: [Command] = thirdSlots.map { .dockFourth($0, .vertical) }
    private static let thirdSlots: [FourthSlot] = [.firstThird, .middleThird, .lastThird]
    private static let fourthColumns: [Command] = fourthSlots.map { .dockFourth($0, .horizontal) }
    private static let fourthRows: [Command] = fourthSlots.map { .dockFourth($0, .vertical) }
    private static let fourthSlots: [FourthSlot] = [.first, .second, .third, .fourth, .middle]

    let focusMenu = NSMenuItem(title: "Focus", action: nil, keyEquivalent: "")
    let splitMenu = NSMenuItem(title: "Split", action: nil, keyEquivalent: "")
    let moveMenu = NSMenuItem(title: MenuCopy.moveMenu, action: nil, keyEquivalent: "")
    /// The first item of Arrange (08.1.1 UI-SPEC Surface 3): every docking position with its hotkey.
    let dockMenu = NSMenuItem(title: MenuCopy.fourthMenu, action: nil, keyEquivalent: "")
    let snapMenu = NSMenuItem(title: MenuCopy.snapMenu, action: nil, keyEquivalent: "")
    let moveViewMenu = NSMenuItem(title: ZoomCopy.moveViewMenu, action: nil, keyEquivalent: "")
    let tabsMenu = NSMenuItem(title: TabCopy.tabsMenu, action: nil, keyEquivalent: "")
    private let dispatch: (Command) -> Void
    private var items: [Command: NSMenuItem] = [:]
    /// Snap Floating Window's halves: the one deliberate duplicate (UI-SPEC). Each runs its Move Window item's command
    /// with the same shortcut; `update` enables only the one that matches the focused window.
    private var halfItems: [Edge: NSMenuItem] = [:]
    private static let edges: [Edge] = [.left, .right, .top, .bottom]
    private static let halves: [Edge: SnapTarget] = [.left: .leftHalf, .right: .rightHalf, .top: .topHalf, .bottom: .bottomHalf]

    init(dispatch: @escaping (Command) -> Void) {
        self.dispatch = dispatch
        super.init()
        for (index, command) in Self.commands.enumerated() {
            let item = NSMenuItem(title: MenuCopy.commandTitle(command), action: #selector(run), keyEquivalent: "")
            item.target = self
            item.tag = index
            if let name = Hotkeys.entries.first(where: { $0.command == command })?.name { item.setShortcut(for: name) }
            items[command] = item
        }
        for edge in Self.edges {
            guard let target = Self.halves[edge], let tag = Self.commands.firstIndex(of: .moveOrSnap(edge)) else { continue }
            let item = NSMenuItem(title: MenuCopy.snapTitle(target), action: #selector(run), keyEquivalent: "")
            item.target = self
            item.tag = tag
            if let name = Hotkeys.entries.first(where: { $0.command == .moveOrSnap(edge) })?.name { item.setShortcut(for: name) }
            halfItems[edge] = item
        }
        focusMenu.submenu = submenu("Focus", [.focus(.left), .focus(.right), .focus(.top), .focus(.bottom)])
        splitMenu.submenu = submenu("Split", [.growTile, .shrinkTile, nil, .balanceSplit, .rotateSplit, .flipSplit, nil, .finderSplit])
        moveMenu.submenu = submenu(MenuCopy.moveMenu, Self.edges.map { .moveOrSnap($0) })
        dockMenu.submenu = submenu(MenuCopy.fourthMenu, groups: [
            (nil, [.dock]), (MenuCopy.halvesHeader, Self.halfColumns + Self.halfRows), (MenuCopy.cornersHeader, Self.corners),
            (MenuCopy.thirdsHeader, Self.thirdColumns + Self.thirdRows), (MenuCopy.fourthsHeader, Self.fourthColumns + Self.fourthRows),
        ])
        let snap = submenu(MenuCopy.snapMenu, [
            nil, .snap(.leftThird), .snap(.centerThird), .snap(.rightThird), nil, .snap(.topLeft), .snap(.topRight), .snap(.bottomLeft),
            .snap(.bottomRight), nil, .snap(.maximize), .snap(.center),
        ])
        for (index, edge) in Self.edges.enumerated() { snap.insertItem(halfItem(edge), at: index) }
        snapMenu.submenu = snap
        moveViewMenu.submenu = submenu(ZoomCopy.moveViewMenu, Self.edges.map { .camera(.pan($0)) })
        tabsMenu.submenu = submenu(TabCopy.tabsMenu, [.tabs(.next), .tabs(.previous), .tabs(.moveOut)])
    }

    /// The Zoom section (UI-SPEC Surface 6; 06 Surface 4 puts Show Overview first): the header, the camera items, `previews` (nil while Screen Recording is
    /// granted) and `toggle`; with zoom off only the header and Turn On Zoom. Enabled states come from `update`.
    /// `takeover` is Replace Mission Control (O2), after Frame Focused Window.
    func zoomSection(enabled: Bool, framingWindow: Bool, takeover: NSMenuItem? = nil, previews: NSMenuItem?, toggle: NSMenuItem) -> [NSMenuItem] {
        toggle.title = enabled ? ZoomCopy.turnOffZoom : ZoomCopy.turnOnZoom
        guard enabled else { return [.sectionHeader(title: ZoomCopy.zoomSection), toggle] }
        item(for: .camera(.frameWindow)).state = framingWindow ? .on : .off
        let steps = [CameraCommand.overview, .zoomOutAll, .stepOut, .stepIn, .back, .forward].map { item(for: .camera($0)) }
        let frame = item(for: .camera(.frameWindow))
        return [.sectionHeader(title: ZoomCopy.zoomSection)] + steps + [moveViewMenu, frame] + [takeover, previews].compactMap { $0 } + [toggle]
    }

    func halfItem(_ edge: Edge) -> NSMenuItem {
        guard let item = halfItems[edge] else { preconditionFailure("no Snap Floating Window half for \(edge)") }
        return item
    }

    func item(for command: Command) -> NSMenuItem {
        guard let item = items[command] else { preconditionFailure("\(command) has no menu item; add it to CommandMenu.commands") }
        return item
    }

    /// Greys each item the availability rule refuses; titles stay as they are (UI-SPEC disabled-state rules). Of each
    /// Move Window item and its Snap Floating Window half, only the one for a floating (or docked) window is enabled.
    func update(focusedFloats: Bool = false, availability: (Command) -> Bool) {
        for (command, item) in items { item.isEnabled = availability(command) }
        for (edge, half) in halfItems {
            let available = availability(.moveOrSnap(edge))
            half.isEnabled = available && focusedFloats
            items[.moveOrSnap(edge)]?.isEnabled = available && !focusedFloats
        }
    }

    /// NSMenu re-validates on open and on key equivalents; the state `update` set is the answer.
    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        menuItem.isEnabled
    }

    @objc private func run(_ sender: NSMenuItem) {
        dispatch(Self.commands[sender.tag])
    }

    /// A preference in the menu (UI-SPEC Surface 1): a titled item with a radio submenu, rebuilt each time the menu
    /// opens. Each choice's `tag` is its index; no availability rule greys them, as with Gaps ▸.
    static func optionMenu(title: String, choices: [(title: String, toolTip: String, selected: Bool)], target: AnyObject, action: Selector) -> NSMenuItem {
        let submenu = NSMenu(title: title)
        for (index, choice) in choices.enumerated() {
            let item = NSMenuItem(title: choice.title, action: action, keyEquivalent: "")
            item.target = target
            item.tag = index
            item.state = choice.selected ? .on : .off
            item.toolTip = choice.toolTip
            submenu.addItem(item)
        }
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.submenu = submenu
        return item
    }

    /// nil adds a separator.
    private func submenu(_ title: String, _ commands: [Command?]) -> NSMenu {
        let menu = NSMenu(title: title)
        for command in commands { menu.addItem(command.map(item(for:)) ?? .separator()) }
        return menu
    }

    /// A separator and a section header (macOS 14) before each headed group.
    private func submenu(_ title: String, groups: [(header: String?, commands: [Command])]) -> NSMenu {
        let menu = NSMenu(title: title)
        for group in groups {
            if let header = group.header {
                menu.addItem(.separator())
                menu.addItem(.sectionHeader(title: header))
            }
            for command in group.commands { menu.addItem(item(for: command)) }
        }
        return menu
    }
}

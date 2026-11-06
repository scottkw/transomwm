import AppKit
import KeyboardShortcuts
import SwiftUI
import TransomEngine

/// The Shortcuts window's rows (UI-SPEC Surface 8): every hotkey name exactly once, in the Surface 8 sections.
enum ShortcutsModel {
    typealias Row = (title: String, name: KeyboardShortcuts.Name)
    /// Double-click a docked window's title bar frames it (Surface 9, read by 04-06's input); default on.
    static let doubleClickKey = "zoomTitleBarDoubleClick"
    /// The Zoom section's footer (06 UI-SPEC Surface 4).
    static let zoomFooter = OverviewCopy.shortcutsZoomFooter

    static let sections: [(title: String, rows: [Row])] = [
        (ZoomCopy.zoomSection, [
            .showOverview, .zoomOutAll, .stepOut, .stepIn, .zoomBack, .zoomForward, .panLeft, .panRight, .panUp, .panDown, .frameWindow,
        ]),
        (ViewCopy.savedViewsSection, [
            .view1, .view2, .view3, .view4, .view5, .view6, .view7, .view8, .view9,
            .saveView1, .saveView2, .saveView3, .saveView4, .saveView5, .saveView6, .saveView7, .saveView8, .saveView9,
        ]),
        (MenuCopy.arrangeSection, [
            .float, .swapPrevious, .undo, .focusLeft, .focusRight, .focusUp, .focusDown, .moveLeft, .moveRight, .moveUp, .moveDown,
            .arrangeAll, .floatAll,
        ]),
        (MenuCopy.fourthMenu, [
            .dock, .dockLeftHalf, .dockRightHalf, .dockTopHalf, .dockBottomHalf,
            .dockTopLeft, .dockTopRight, .dockBottomLeft, .dockBottomRight,
            .dockLeftThird, .dockCenterThird, .dockRightThird, .dockTopThird, .dockMiddleThird, .dockBottomThird,
            .dockColumn1, .dockColumn2, .dockColumn3, .dockColumn4, .dockColumnMiddle, .dockRow1, .dockRow2, .dockRow3, .dockRow4, .dockRowMiddle,
        ]),
        ("Split", [.growTile, .shrinkTile, .balanceSplit, .rotateSplit, .flipSplit, .finderSplit]),
        (MenuCopy.snapMenu, [
            .snapLeftThird, .snapCenterThird, .snapRightThird, .snapTopLeft, .snapTopRight, .snapBottomLeft, .snapBottomRight,
            .snapMaximize, .snapCenter,
        ]),
        (TabCopy.tabsMenu, [.nextTab, .previousTab, .moveOutOfGroup]),
        (MenuCopy.safetySection, [.togglePause, .restoreAll]),
        (MenuCopy.exclusionsSection, [.toggleExcludeFrontmost]),
    ].map { section in (section.0, section.1.map { (ZoomCopy.shortcutTitle(command(of: $0)), $0) }) }

    private static func command(of name: KeyboardShortcuts.Name) -> Command {
        guard let command = Hotkeys.entries.first(where: { $0.name == name })?.command else {
            preconditionFailure("\(name.rawValue) is not in Hotkeys.entries")
        }
        return command
    }

    /// The in-Transom duplicate message when another Transom command already has `shortcut`; nil otherwise.
    static func conflictMessage(for shortcut: KeyboardShortcuts.Shortcut, excluding name: KeyboardShortcuts.Name) -> String? {
        guard let other = Hotkeys.entries.first(where: { $0.name != name && KeyboardShortcuts.getShortcut(for: $0.name) == shortcut })
        else { return nil }
        return ZoomCopy.duplicateShortcut(usedBy: ZoomCopy.shortcutTitle(other.command))
    }
}

/// One Recorder per hotkey, the Mouse toggle and Restore Defaults. Bindings are read synchronously (no loading state);
/// a system conflict shows KeyboardShortcuts' own "Use Anyway" dialog (default ConflictPolicy).
struct ShortcutsView: View {
    @AppStorage(ZoomController.enabledKey) private var zoomEnabled = true
    @AppStorage(ShortcutsModel.doubleClickKey) private var doubleClick = true

    var body: some View {
        VStack(spacing: 0) {
            Form {
                ForEach(ShortcutsModel.sections.indices, id: \.self) { index in
                    let section = ShortcutsModel.sections[index]
                    Section {
                        ForEach(section.rows.indices, id: \.self) { row in
                            let name = section.rows[row].name
                            KeyboardShortcuts.Recorder(section.rows[row].title, name: name)
                                .shortcutValidation { ShortcutsModel.conflictMessage(for: $0, excluding: name).map { .disallow(reason: $0) } ?? .allow }
                        }
                    } header: {
                        Text(section.title)
                    } footer: {
                        if section.title == ZoomCopy.zoomSection { Text(ShortcutsModel.zoomFooter).font(.subheadline).foregroundStyle(.secondary) }
                        if section.title == ViewCopy.savedViewsSection { Text(ViewCopy.shortcutsFooter).font(.subheadline).foregroundStyle(.secondary) }
                    }
                }
                Section {
                    Toggle(ZoomCopy.doubleClickToggle, isOn: $doubleClick).disabled(!zoomEnabled)
                } header: {
                    Text(ZoomCopy.mouseSection)
                } footer: {
                    Text(zoomEnabled ? ZoomCopy.doubleClickFooterOn : ZoomCopy.doubleClickFooterZoomOff)
                        .font(.subheadline).foregroundStyle(.secondary)
                }
            }
            .formStyle(.grouped)
            HStack {
                Button(ZoomCopy.restoreDefaults) { ShortcutsWindowController.confirmRestoreDefaults() }
                Spacer()
            }
            .padding(20)
        }
    }
}

/// Owns the "Shortcuts" window (Surface 8): one window, reopened with its remembered frame.
@MainActor final class ShortcutsWindowController {
    private var window: NSWindow?

    func show() {
        let window = window ?? makeWindow()
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
    }

    private func makeWindow() -> NSWindow {
        let hosting = NSHostingController(rootView: ShortcutsView())
        hosting.sizingOptions = []  // the window decides the frame; the Form scrolls inside it
        let window = KeyClosableWindow(contentViewController: hosting)
        window.styleMask = [.titled, .closable, .resizable]
        window.title = ZoomCopy.shortcutsWindowTitle
        window.isReleasedWhenClosed = false
        window.setContentSize(NSSize(width: 480, height: 640))
        window.contentMinSize = NSSize(width: 480, height: 400)
        window.contentMaxSize = NSSize(width: 480, height: CGFloat.greatestFiniteMagnitude)  // width fixed
        if !window.setFrameUsingName("Shortcuts") { window.center() }
        window.setFrameAutosaveName("Shortcuts")
        self.window = window
        return window
    }

    /// The destructive confirmation (Copywriting Contract): Cancel is the default (Return and Esc); only a click on
    /// "Restore Defaults" resets, and only Transom's own names.
    static func confirmRestoreDefaults() {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = ZoomCopy.restoreDefaultsMessage
        alert.informativeText = ZoomCopy.restoreDefaultsInformative
        let restore = alert.addButton(withTitle: ZoomCopy.restoreDefaults)  // first button: rightmost
        restore.keyEquivalent = ""
        restore.hasDestructiveAction = true
        let cancel = alert.addButton(withTitle: "Cancel")
        cancel.keyEquivalent = "\r"
        // Cancel holds Return, so map Esc (key code 53) to it while the alert is up.
        let escape = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            guard event.keyCode == 53 else { return event }
            cancel.performClick(nil)
            return nil
        }
        let response = alert.runModal()
        if let escape { NSEvent.removeMonitor(escape) }
        guard response == .alertFirstButtonReturn else { return }
        KeyboardShortcuts.reset(Hotkeys.entries.map(\.name))
    }
}

import SwiftUI

/// Settings ▸ Menu Bar (09 UI-SPEC Tab 6): which view controls show left of the Transom icon, and in what order. Writes
/// only through `MenuBarPreference`, so its `onChange` refreshes the status items (D-02).
struct MenuBarTab: View {
    let preference: MenuBarPreference
    /// Read when the tab redraws: the Saved views footer explains where badges come from while none is saved.
    let hasSavedViews: () -> Bool

    static func label(_ control: MenuBarControl) -> String {
        switch control {
        case .back: ViewCopy.back
        case .forward: ViewCopy.forward
        case .views: ViewCopy.savedViewsSection
        }
    }

    static func glyph(_ control: MenuBarControl) -> String {
        switch control {
        case .back: "chevron.backward"
        case .forward: "chevron.forward"
        case .views: "1.square"
        }
    }

    /// Icon only's footer, plus where views come from while Saved Views is on and none is saved.
    static func savedViewsFooter(viewsEnabled: Bool, hasSavedViews: Bool) -> String {
        viewsEnabled && !hasSavedViews ? SettingsCopy.iconOnlyFooter + " " + SettingsCopy.noSavedViewsFooter : SettingsCopy.iconOnlyFooter
    }

    var body: some View {
        Form {
            Section {
                ForEach(preference.items, id: \.control) { (item: MenuBarItem) in
                    row(item)
                }
                .onMove { (source: IndexSet, destination: Int) -> Void in preference.move(fromOffsets: source, toOffset: destination) }
            } header: {
                Text(SettingsCopy.controlsSection)
            } footer: {
                Self.footer(ViewCopy.menuBarFooter)
            }
            Section {
                Toggle(SettingsCopy.iconOnly, isOn: Binding(get: { preference.iconOnly }, set: { (on: Bool) -> Void in preference.setIconOnly(on) }))
            } header: {
                Text(SettingsCopy.savedViewsSection)
            } footer: {
                let viewsEnabled = preference.items.contains { $0.control == .views && $0.enabled }
                Self.footer(Self.savedViewsFooter(viewsEnabled: viewsEnabled, hasSavedViews: hasSavedViews()))
            }
        }
        .formStyle(.grouped)
    }

    private func row(_ item: MenuBarItem) -> some View {
        let control = item.control
        return Toggle(isOn: Binding(get: { item.enabled }, set: { (on: Bool) -> Void in preference.setEnabled(control, on) })) {
            Label(Self.label(control), systemImage: Self.glyph(control))
        }
        .contextMenu {
            Button(SettingsCopy.moveUp) { preference.moveUp(control) }.disabled(!preference.canMoveUp(control))
            Button(SettingsCopy.moveDown) { preference.moveDown(control) }.disabled(!preference.canMoveDown(control))
        }
        // VoiceOver lists only the moves that can happen (UI-SPEC Accessibility).
        .accessibilityActions {
            if preference.canMoveUp(control) { Button(SettingsCopy.moveUp) { preference.moveUp(control) } }
            if preference.canMoveDown(control) { Button(SettingsCopy.moveDown) { preference.moveDown(control) } }
        }
    }

    private static func footer(_ text: String) -> some View {
        Text(text).font(.subheadline).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
    }
}

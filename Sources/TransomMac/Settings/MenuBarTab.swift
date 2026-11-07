import SwiftUI

/// Settings ▸ Menu Bar (09 UI-SPEC Tab 6): which view controls show left of the Transom icon, and in what order. Writes
/// only through `MenuBarPreference`, so its `onChange` refreshes the status items (D-02).
struct MenuBarTab: View {
    let preference: MenuBarPreference

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

    var body: some View {
        Form {
            Section {
                ForEach(preference.items, id: \.control) { (item: MenuBarItem) in
                    Toggle(isOn: Binding(get: { item.enabled }, set: { (on: Bool) -> Void in preference.setEnabled(item.control, on) })) {
                        Label(Self.label(item.control), systemImage: Self.glyph(item.control))
                    }
                }
            } footer: {
                Text(ViewCopy.menuBarFooter).font(.subheadline).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
        }
        .formStyle(.grouped)
    }
}

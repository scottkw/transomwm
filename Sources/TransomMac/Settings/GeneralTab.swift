import AppKit
import SwiftUI

/// Settings ▸ General (09 UI-SPEC Tab 1). Startup: launch at login through `loginItem` (SHIP-03), re-read every time the
/// tab shows. Appearance: the highlight follows the macOS accent or one custom colour (D-03); every write goes through
/// `HighlightColor.set`, which tells the overlays on screen to redraw.
struct GeneralTab: View {
    let loginItem: any LoginItemService
    @State private var login = LoginItemToggle(status: .notRegistered)
    @State private var custom = HighlightColor.override() != nil
    @State private var color = Color(nsColor: HighlightColor.current)

    private var mode: Binding<Bool> {
        Binding(
            get: { custom },
            set: { (on: Bool) -> Void in
                custom = on
                if on {
                    // The first choice of Custom seeds the well with the system accent at that moment.
                    let seed = HighlightColor.override() ?? HighlightColor.current
                    color = Color(nsColor: seed)
                    HighlightColor.set(seed)
                } else {
                    HighlightColor.set(nil)
                }
            })
    }

    private var well: Binding<Color> {
        Binding(
            get: { color },
            set: { (picked: Color) -> Void in
                color = picked
                HighlightColor.set(NSColor(picked))
            })
    }

    private var openAtLogin: Binding<Bool> {
        Binding(
            get: { login.isOn },
            set: { (on: Bool) -> Void in login = LoginItemToggle.toggled(on, service: loginItem) })
    }

    var body: some View {
        Form {
            Section {
                Toggle(SettingsCopy.openAtLogin, isOn: openAtLogin)
                if login.needsApproval {
                    HStack {
                        Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange).accessibilityHidden(true)
                        Text(SettingsCopy.needsApproval)
                        Spacer()
                        Button(SettingsCopy.openLoginItems) { loginItem.openSystemSettingsLoginItems() }
                    }
                }
            } header: {
                Text(SettingsCopy.startupSection)
            } footer: {
                if let footer = login.footer { Self.footer(footer) }
            }
            Section {
                HStack(alignment: .bottom) {
                    Picker(SettingsCopy.highlightColor, selection: mode) {
                        Text(SettingsCopy.matchSystemAccent).tag(false)
                        Text(SettingsCopy.customHighlight).tag(true)
                    }
                    .pickerStyle(.radioGroup)
                    ColorPicker(SettingsCopy.customHighlightWell, selection: well, supportsOpacity: false)
                        .labelsHidden()
                        .disabled(!custom)
                }
            } header: {
                Text(SettingsCopy.appearanceSection)
            } footer: {
                Self.footer(SettingsCopy.highlightFooter)
            }
        }
        .formStyle(.grouped)
        .onAppear { login = LoginItemToggle(status: loginItem.status) }
    }

    private static func footer(_ text: String) -> some View {
        Text(text).font(.subheadline).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
    }
}

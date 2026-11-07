import AppKit
import SwiftUI

/// Settings ▸ General (09 UI-SPEC Tab 1). Appearance: the highlight follows the macOS accent or one custom colour
/// (D-03); every write goes through `HighlightColor.set`, which tells the overlays on screen to redraw.
struct GeneralTab: View {
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

    var body: some View {
        Form {
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
                Text(SettingsCopy.highlightFooter).font(.subheadline).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .formStyle(.grouped)
    }
}

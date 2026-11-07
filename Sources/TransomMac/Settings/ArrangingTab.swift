import SwiftUI
import TransomEngine

/// Settings ▸ Arranging (09 UI-SPEC Tab 2). Every control binds to the instance the menu reads and writes only through
/// its `set(_:)`, so validation, the engine update and the announcement run once and menu and Settings never disagree
/// (D-02). No `@AppStorage` on these keys: it would skip all three.
struct ArrangingTab: View {
    let gaps: GapPreference
    let newWindows: NewWindowsPreference
    let dragToDock: DragToDockPreference
    let conflicts: ConflictController

    static func gapBinding(_ gaps: GapPreference) -> Binding<Double> {
        Binding(get: { gaps.value }, set: { (gap: Double) -> Void in _ = gaps.set(gap) })
    }

    var body: some View {
        Form {
            Section {
                Picker(SettingsCopy.gaps, selection: Self.gapBinding(gaps)) {
                    ForEach(GapPreference.allowed, id: \.self) { Text(MenuCopy.gapTitle($0)).tag($0) }
                }
                .pickerStyle(.menu)
            } header: {
                Text(SettingsCopy.layoutSection)
            }
        }
        .formStyle(.grouped)
    }
}

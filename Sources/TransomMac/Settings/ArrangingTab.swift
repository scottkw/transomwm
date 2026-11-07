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
    /// Read lazily by `CloseGroupConfirmation.isEnabled` on every Close Group, with no onChange, so `@AppStorage` is safe.
    @AppStorage(CloseGroupConfirmation.key) private var confirmCloseGroup = true

    static func gapBinding(_ gaps: GapPreference) -> Binding<Double> {
        Binding(get: { gaps.value }, set: { (gap: Double) -> Void in _ = gaps.set(gap) })
    }

    static func newWindowsBinding(_ newWindows: NewWindowsPreference) -> Binding<NewWindowsMode> {
        Binding(get: { newWindows.value }, set: { (mode: NewWindowsMode) -> Void in newWindows.set(mode) })
    }

    static func dragToDockBinding(_ dragToDock: DragToDockPreference) -> Binding<DragToDockMode> {
        Binding(get: { dragToDock.value }, set: { (mode: DragToDockMode) -> Void in dragToDock.set(mode) })
    }

    /// The selected mode's menu tooltip, verbatim (UI-SPEC Tab 2).
    static func footer(_ mode: NewWindowsMode) -> String { MenuCopy.newWindowsTooltip(mode) }
    static func footer(_ mode: DragToDockMode) -> String { MenuCopy.dragToDockTooltip(mode) }

    /// One row per conflicting macOS feature, in `Conflict.allCases` order.
    static func featureRows(_ conflicts: ConflictController) -> [(conflict: Conflict, name: String, detail: String, isOn: Bool)] {
        Conflict.allCases.map { ($0, SettingsCopy.featureName($0), ConflictCopy.tooltip($0), conflicts.active.contains($0)) }
    }

    var body: some View {
        Form {
            Section {
                Picker(SettingsCopy.gaps, selection: Self.gapBinding(gaps)) {
                    ForEach(GapPreference.allowed, id: \.self) { Text(MenuCopy.gapTitle($0)).tag($0) }
                }
                .pickerStyle(.menu)
                VStack(alignment: .leading) {
                    Picker(SettingsCopy.newWindows, selection: Self.newWindowsBinding(newWindows)) {
                        ForEach(NewWindowsMode.allCases, id: \.self) { Text(MenuCopy.newWindowsChoice($0)).tag($0) }
                    }
                    .pickerStyle(.radioGroup)
                    Self.rowFooter(Self.footer(newWindows.value))
                }
                VStack(alignment: .leading) {
                    Picker(SettingsCopy.dragToDock, selection: Self.dragToDockBinding(dragToDock)) {
                        ForEach(DragToDockMode.allCases, id: \.self) { Text(MenuCopy.dragToDockChoice($0)).tag($0) }
                    }
                    .pickerStyle(.radioGroup)
                    Self.rowFooter(Self.footer(dragToDock.value))
                }
            } header: {
                Text(SettingsCopy.layoutSection)
            }
            Section {
                Toggle(SettingsCopy.confirmCloseGroup, isOn: $confirmCloseGroup)
            } header: {
                Text(SettingsCopy.tabGroupsSection)
            } footer: {
                Self.rowFooter(SettingsCopy.confirmCloseGroupFooter)
            }
            Section {
                ForEach(Self.featureRows(conflicts), id: \.conflict) { row in
                    HStack {
                        VStack(alignment: .leading) {
                            Text(row.name)
                            Self.rowFooter(row.detail)
                        }
                        Spacer()
                        if row.isOn {
                            Text(SettingsCopy.featureOn)
                            // The menu line's immediate action (Phase 3 D-19).
                            Button(ConflictCopy.turnOffButton) { Task { await conflicts.turnOff(row.conflict) } }
                        } else {
                            Image(systemName: "checkmark.circle.fill").foregroundStyle(.green).accessibilityHidden(true)
                            Text(SettingsCopy.featureOff)
                        }
                    }
                }
                Button(ConflictCopy.restoreItem) { conflicts.restore() }.disabled(!conflicts.canRestore)
            } header: {
                Text(SettingsCopy.featuresSection)
            } footer: {
                Self.rowFooter(SettingsCopy.restoreFooter)
            }
        }
        .formStyle(.grouped)
    }

    private static func rowFooter(_ text: String) -> some View {
        Text(text).font(.subheadline).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
    }
}

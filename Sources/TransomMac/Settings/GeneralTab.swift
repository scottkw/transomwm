import AppKit
import SwiftUI
import TransomEngine

/// Settings ▸ General (09 UI-SPEC Tab 1). Startup: launch at login through `loginItem` (SHIP-03), re-read every time the
/// tab shows. Permissions: Accessibility from `permission`, Screen Recording only through the injected closures, because
/// `SnapshotCapture` counts every call and ZoomOffTests expects none from tests (RESEARCH Pitfall 5). Appearance: the highlight follows the macOS accent or one custom colour (D-03); every write goes through
/// `HighlightColor.set`, which tells the overlays on screen to redraw.
struct GeneralTab: View {
    let loginItem: any LoginItemService
    @ObservedObject var permission: PermissionController
    /// Opens Set Up Transom at its Accessibility step.
    let showSetup: () -> Void
    let screenRecordingGranted: () -> Bool
    /// The menu's Allow Window Previews… path.
    let allowScreenRecording: () -> Void
    @State private var login = LoginItemToggle(status: .notRegistered)
    @State private var recordingGranted = false
    @State private var cliPath: String?
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

    nonisolated static func accessibilityRow(_ state: PermissionState) -> (status: String, button: String?) {
        switch state.phase {
        case .ready: (SettingsCopy.featureOn, nil)
        case .staleTrustedButFailing, .resetting: (SettingsCopy.permissionNotWorking, SettingsCopy.fixButton)
        case .notTrusted, .waitingForGrant, .probing:
            state.showStaleFormB
                ? (SettingsCopy.permissionNotWorking, SettingsCopy.fixButton) : (SettingsCopy.featureOff, SettingsCopy.setUpButton)
        }
    }

    /// Where the `transom` tool is on `PATH`, Homebrew's Apple Silicon prefix first.
    nonisolated static func installedCLIPath(exists: (String) -> Bool) -> String? {
        ["/opt/homebrew/bin/transom", "/usr/local/bin/transom"].first(where: exists)
    }

    nonisolated static func screenRecordingRow(granted: Bool) -> (status: String, button: String?) {
        granted ? (SettingsCopy.featureOn, nil) : (SettingsCopy.featureOff, SettingsCopy.allowButton)
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
                Self.permissionRow(SettingsCopy.accessibility, Self.accessibilityRow(permission.state), action: showSetup)
                Self.permissionRow(
                    SettingsCopy.screenRecording, Self.screenRecordingRow(granted: recordingGranted), action: allowScreenRecording)
            } header: {
                Text(SettingsCopy.permissionsSection)
            } footer: {
                Self.footer(SettingsCopy.screenRecordingFooter)
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
            Section {
                HStack {
                    Text(SettingsCopy.cliRow)
                    Spacer()
                    if let cliPath {
                        Text(SettingsCopy.cliInstalled)
                        Text(cliPath).foregroundStyle(.secondary)
                    } else {
                        Text(SettingsCopy.cliNotInstalled)
                        Button(SettingsCopy.copyInstallCommand) {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(SettingsCopy.cliInstallCommand, forType: .string)
                        }
                    }
                }
            } header: {
                Text(SettingsCopy.cliSection)
            } footer: {
                VStack(alignment: .leading, spacing: 4) {
                    Self.footer(SettingsCopy.cliFooter)
                    if cliPath == nil {
                        Text(SettingsCopy.cliInstallCommand).font(.body.monospaced()).textSelection(.enabled)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
        .formStyle(.grouped)
        .onAppear {
            login = LoginItemToggle(status: loginItem.status)
            cliPath = Self.installedCLIPath(exists: { FileManager.default.fileExists(atPath: $0) })
        }
        .task {
            // Re-read once a second while the tab shows; SwiftUI cancels the task when it goes away.
            while !Task.isCancelled {
                recordingGranted = screenRecordingGranted()
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }

    private static func permissionRow(_ title: String, _ row: (status: String, button: String?), action: @escaping () -> Void)
        -> some View
    {
        HStack {
            Text(title)
            Spacer()
            if row.button == nil {
                Image(systemName: "checkmark.circle.fill").foregroundStyle(.green).accessibilityHidden(true)
            }
            Text(row.status)
            if let button = row.button { Button(button, action: action) }
        }
    }

    private static func footer(_ text: String) -> some View {
        Text(text).font(.subheadline).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
    }
}

import AppKit
import SwiftUI
import TransomEngine

/// Settings ▸ Updates (09 UI-SPEC Surface 3, D-09, D-10): the running version, the status line, the download progress
/// and the actions of the current state.
struct UpdatesTab: View {
    @ObservedObject var controller: UpdateController

    var body: some View {
        Form {
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Text(UpdateCopy.versionLine(controller.currentVersion, controller.build))
                    if let error = controller.error {
                        HStack(spacing: 6) {
                            Image(systemName: "xmark.octagon.fill").foregroundStyle(.red).accessibilityLabel("Error")
                            Text(UpdateCopy.errorLine(error)).accessibilityAddTraits(.updatesFrequently)
                        }
                    } else if let line = UpdateCopy.statusLine(controller.status, current: controller.currentVersion) {
                        HStack(spacing: 6) {
                            switch controller.status {
                            case .checking, .verifying: ProgressView().controlSize(.small)
                            case .current:
                                Image(systemName: "checkmark.circle.fill").foregroundStyle(.green).accessibilityHidden(true)
                            case .idle, .available, .downloading, .opened: EmptyView()
                            }
                            // A live region: each state change is spoken.
                            Text(line).accessibilityAddTraits(.updatesFrequently)
                        }
                    }
                    if case .downloading(_, let fraction) = controller.status {
                        // Linear; indeterminate while the size is unknown. A determinate bar reads out its percentage.
                        if let fraction {
                            ProgressView(value: fraction)
                        } else {
                            ProgressView().progressViewStyle(.linear)
                        }
                    }
                    if case .available = controller.status, controller.installedWithHomebrew {
                        Text(UpdateCopy.homebrewIntro)
                        Text(UpdateCopy.homebrewCommand).font(.body.monospaced()).textSelection(.enabled)
                    }
                    HStack {
                        switch controller.status {
                        case .available(let release):
                            if controller.installedWithHomebrew {
                                Button(UpdateCopy.copyCommand) {
                                    NSPasteboard.general.clearContents()
                                    NSPasteboard.general.setString(UpdateCopy.homebrewCommand, forType: .string)
                                }
                                .buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction)
                            } else {
                                Button(UpdateCopy.downloadAndOpen) { Task { await controller.downloadAndOpen() } }
                                    .buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction)
                            }
                            Link(UpdateCopy.releaseNotes, destination: release.notesURL)
                        case .opened:
                            Button(UpdateCopy.quitTransom) { NSApp.terminate(nil) }
                                .buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction)
                        case .idle, .checking, .current, .downloading, .verifying: EmptyView()
                        }
                        Button(UpdateCopy.checkForUpdates) { Task { await controller.checkNow() } }
                            .disabled(!controller.isEnabled || controller.machine.isBusy)
                    }
                }
            }
            Section {
                Toggle(UpdateCopy.automaticToggle, isOn: $controller.automatic)
            } footer: {
                Text(UpdateCopy.automaticFooter)
            }
        }
        .formStyle(.grouped)
    }
}

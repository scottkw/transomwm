import SwiftUI
import TransomEngine

/// Settings ▸ Updates (09 UI-SPEC Surface 3, D-09): the running version, the status line and Check for Updates.
struct UpdatesTab: View {
    @ObservedObject var controller: UpdateController

    var body: some View {
        Form {
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Text(UpdateCopy.versionLine(controller.currentVersion, controller.build))
                    if let line = UpdateCopy.statusLine(controller.status, current: controller.currentVersion) {
                        HStack(spacing: 6) {
                            switch controller.status {
                            case .checking: ProgressView().controlSize(.small)
                            case .current:
                                Image(systemName: "checkmark.circle.fill").foregroundStyle(.green).accessibilityHidden(true)
                            case .idle, .available: EmptyView()
                            }
                            // A live region: each state change is spoken.
                            Text(line).accessibilityAddTraits(.updatesFrequently)
                        }
                    }
                    HStack {
                        if case .available(let release) = controller.status {
                            Link(UpdateCopy.releaseNotes, destination: release.notesURL)
                        }
                        Button(UpdateCopy.checkForUpdates) { Task { await controller.checkNow() } }
                            .disabled(!controller.isEnabled || controller.status == .checking)
                    }
                }
            }
        }
        .formStyle(.grouped)
    }
}

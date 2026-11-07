import AppKit
import TransomEngine
import SwiftUI
import os

/// The steps the Set Up Transom window walks and the one it shows (09 UI-SPEC Surface 2).
final class OnboardingModel: ObservableObject {
    @Published var steps: [OnboardingStep]
    @Published var current: OnboardingStep
    /// Screen Recording step: Allow was clicked, and the last poll's answer.
    @Published var screenRecordingAsked = false
    @Published var screenRecordingOn = false
    /// Launch at login step: the toggle (on by default, D-07) and the outcome of a Continue that didn't enable it.
    @Published var launchAtLogin = true
    @Published var loginResult: LoginItemToggle?
    /// Move step: where Transom is running from, and the failure text after a copy that threw.
    @Published var place: InstallLocation.Place = .other
    @Published var moveFailure: String?

    init(steps: [OnboardingStep]) {
        self.steps = steps
        current = steps[0]
    }

    /// Move's copy: true when it landed; a throw keeps the step and shows the failure text (UI-SPEC callout E).
    func copyForMove(_ copy: () throws -> Void) -> Bool {
        do {
            try copy()
            moveFailure = nil
            return true
        } catch {
            Logger(subsystem: "com.eightabyte.transom", category: "onboarding")
                .error("move to Applications failed: \(error.localizedDescription, privacy: .public)")
            moveFailure = OnboardingCopy.moveFailed
            return false
        }
    }
}

/// The step container: Welcome, Screen Recording and Done render here; the Accessibility step is Phase 2's `SetupView`, unchanged
/// apart from its caption. Steps swap instantly and the window height follows the content.
struct OnboardingView: View {
    @ObservedObject var model: OnboardingModel
    let permission: PermissionController
    let conflicts: ConflictController?
    let appName: String
    let advance: () -> Void
    let back: () -> Void
    let allowScreenRecording: () -> Void
    let finish: () -> Void
    let openSettings: () -> Void
    let continueLaunchAtLogin: () -> Void
    let openLoginItems: () -> Void
    let close: () -> Void
    let moveToApplications: () -> Void
    @AccessibilityFocusState private var headingFocused: Bool

    var body: some View {
        let caption = OnboardingFlow.caption(for: model.current, in: model.steps)
            .map { (c: (number: Int, total: Int)) -> String in OnboardingCopy.caption(number: c.number, total: c.total) }
        switch model.current {
        case .move:
            page(caption: caption, heading: OnboardingCopy.moveHeading, text: OnboardingCopy.moveBody(model.place)) {
                Image(systemName: "folder")
                    .font(.system(size: 48))
                    .foregroundStyle(Color(nsColor: .secondaryLabelColor))
            } detail: {
                if let failure = model.moveFailure {
                    // Callout E styling, as SetupView's reset failure.
                    GroupBox {
                        HStack(alignment: .top, spacing: 8) {
                            Image(systemName: "xmark.octagon.fill")
                                .font(.system(size: 16))
                                .foregroundStyle(Color(nsColor: .systemRed))
                                .accessibilityLabel("Error")
                            Text(verbatim: failure).font(.body).fixedSize(horizontal: false, vertical: true)
                        }
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            } buttons: {
                Button(OnboardingCopy.moveQuitButton) { NSApp.terminate(nil) }
                defaultButton(OnboardingCopy.moveButton, action: moveToApplications)
            }
        case .welcome:
            page(caption: caption, heading: OnboardingCopy.welcomeHeading, text: OnboardingCopy.welcomeBody) {
                Image(nsImage: NSApplication.shared.applicationIconImage).resizable().frame(width: 64, height: 64)
            } detail: {
                EmptyView()
            } buttons: {
                Button(OnboardingCopy.quitButton) { NSApp.terminate(nil) }
                defaultButton(OnboardingCopy.continueButton, action: advance)
            }
        case .screenRecording:
            page(caption: caption, heading: OnboardingCopy.screenRecordingHeading, text: OnboardingCopy.screenRecordingBody, back: back) {
                Image(systemName: "rectangle.dashed.badge.record")
                    .font(.system(size: 48))
                    .foregroundStyle(Color(nsColor: .secondaryLabelColor))
            } detail: {
                secondary(OnboardingCopy.screenRecordingMonthly)
                if model.screenRecordingOn {
                    HStack(spacing: 8) {
                        Image(systemName: "checkmark.circle.fill").foregroundStyle(Color(nsColor: .systemGreen))
                            .accessibilityHidden(true)
                        Text(verbatim: OnboardingCopy.screenRecordingOn).font(.body)
                    }
                } else if model.screenRecordingAsked {
                    HStack(spacing: 8) {
                        ProgressView().controlSize(.small)
                        Text(verbatim: OnboardingCopy.screenRecordingWaiting).font(.caption)
                            .foregroundStyle(Color(nsColor: .secondaryLabelColor))
                    }
                    secondary(OnboardingCopy.screenRecordingWaitingHelp)
                }
            } buttons: {
                if model.screenRecordingAsked || model.screenRecordingOn {
                    defaultButton(OnboardingCopy.continueButton, action: advance)  // never blocked (D-06)
                } else {
                    Button(OnboardingCopy.skipButton, action: advance)
                    defaultButton(OnboardingCopy.allowScreenRecordingButton, action: allowScreenRecording)
                }
            }
        case .features:
            page(caption: caption, heading: OnboardingCopy.featuresHeading, text: OnboardingCopy.featuresBody, back: back) {
                Image(systemName: "macwindow.on.rectangle")
                    .font(.system(size: 48))
                    .foregroundStyle(Color(nsColor: .secondaryLabelColor))
            } detail: {
                if let conflicts { featureRows(conflicts) }
            } buttons: {
                defaultButton(OnboardingCopy.continueButton, action: advance)
            }
        case .launchAtLogin:
            page(caption: caption, heading: OnboardingCopy.launchHeading, text: nil, back: back) {
                Image(systemName: "power")
                    .font(.system(size: 48))
                    .foregroundStyle(Color(nsColor: .secondaryLabelColor))
            } detail: {
                Toggle(SettingsCopy.openAtLogin, isOn: $model.launchAtLogin)
                secondary(OnboardingCopy.launchBody)
                if let result = model.loginResult {
                    // The General tab's Startup message and button.
                    HStack(spacing: 8) {
                        if result.needsApproval {
                            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange).accessibilityHidden(true)
                        }
                        Text(verbatim: result.needsApproval ? SettingsCopy.needsApproval : SettingsCopy.loginItemFailed)
                            .font(.body).fixedSize(horizontal: false, vertical: true)
                    }
                    Button(SettingsCopy.openLoginItems, action: openLoginItems)
                }
            } buttons: {
                defaultButton(OnboardingCopy.continueButton, action: continueLaunchAtLogin)
            }
        case .done:
            page(caption: caption, heading: OnboardingCopy.doneHeading, text: OnboardingCopy.doneBody) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 48))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(Color(nsColor: .systemGreen))
            } detail: {
                EmptyView()
            } buttons: {
                Button(OnboardingCopy.openSettingsButton, action: openSettings)
                defaultButton(OnboardingCopy.doneButton, action: finish)
            }
        default:
            SetupView(permission: permission, appName: appName, caption: caption, close: close)
        }
    }

    /// All three features in fixed order, as Settings ▸ Arranging lists them. Turn Off is the menu line's immediate action
    /// (Phase 3 D-19), so Restore macOS Window Settings undoes it.
    private func featureRows(_ conflicts: ConflictController) -> some View {
        ForEach(ArrangingTab.featureRows(conflicts), id: \.conflict) { row in
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(verbatim: row.name).font(.headline)
                        secondary(row.detail)
                    }
                    Spacer()
                    if row.isOn {
                        Button(ConflictCopy.turnOffButton) { Task { await conflicts.turnOff(row.conflict) } }
                    } else {
                        HStack(spacing: 4) {
                            Image(systemName: "checkmark.circle.fill").foregroundStyle(Color(nsColor: .systemGreen))
                                .accessibilityHidden(true)
                            Text(verbatim: SettingsCopy.featureOff)
                        }
                    }
                }
                if row.isOn {
                    // x-apple.systempreferences:com.apple.Desktop-Settings.extension, through the controller's opener.
                    Button(OnboardingCopy.openDesktopDockButton) { conflicts.openSettings(ConflictController.desktopAndDock) }
                        .buttonStyle(.link)
                }
            }
        }
    }

    /// Phase 2's layout metrics: 48–64 pt hero, 16 pt stack, 12 pt text block, 24 pt above the buttons, 440 + 20 pt.
    private func page(
        caption: String?, heading: String, text: String?, back: (() -> Void)? = nil, @ViewBuilder hero: () -> some View,
        @ViewBuilder detail: () -> some View, @ViewBuilder buttons: () -> some View
    ) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            hero().accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 12) {
                if let caption {
                    Text(verbatim: caption).font(.subheadline).foregroundStyle(Color(nsColor: .secondaryLabelColor))
                }
                Text(verbatim: heading).font(.title).fontWeight(.semibold)
                    .accessibilityAddTraits(.isHeader)
                    .accessibilityFocused($headingFocused)
                if let text { secondary(text) }
                detail()
            }
            HStack(spacing: 12) {
                if let back { Button(OnboardingCopy.backButton, action: back) }  // leftmost on steps 3–5
                Spacer()
                buttons()
            }
            .padding(.top, 8)
        }
        .frame(width: 440, alignment: .leading)
        .padding(20)
        .onAppear { headingFocused = true }
    }

    private func secondary(_ text: String) -> some View {
        Text(verbatim: text).font(.body).foregroundStyle(Color(nsColor: .secondaryLabelColor))
            .fixedSize(horizontal: false, vertical: true)
    }

    private func defaultButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(title, action: action).keyboardShortcut(.defaultAction).buttonStyle(.borderedProminent)
    }
}

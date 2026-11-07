import AppKit
import TransomEngine
import SwiftUI

/// The steps the Set Up Transom window walks and the one it shows (09 UI-SPEC Surface 2).
final class OnboardingModel: ObservableObject {
    @Published var steps: [OnboardingStep]
    @Published var current: OnboardingStep
    /// Screen Recording step: Allow was clicked, and the last poll's answer.
    @Published var screenRecordingAsked = false
    @Published var screenRecordingOn = false

    init(steps: [OnboardingStep]) {
        self.steps = steps
        current = steps[0]
    }
}

/// The step container: Welcome, Screen Recording and Done render here; the Accessibility step is Phase 2's `SetupView`, unchanged
/// apart from its caption. Steps swap instantly and the window height follows the content.
struct OnboardingView: View {
    @ObservedObject var model: OnboardingModel
    let permission: PermissionController
    let appName: String
    let advance: () -> Void
    let back: () -> Void
    let allowScreenRecording: () -> Void
    let finish: () -> Void
    let openSettings: () -> Void
    let close: () -> Void
    @AccessibilityFocusState private var headingFocused: Bool

    var body: some View {
        let caption = OnboardingFlow.caption(for: model.current, in: model.steps)
            .map { (c: (number: Int, total: Int)) -> String in OnboardingCopy.caption(number: c.number, total: c.total) }
        switch model.current {
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
            page(caption: caption, heading: OnboardingCopy.screenRecordingHeading, text: OnboardingCopy.screenRecordingBody) {
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
                Button(OnboardingCopy.backButton, action: back)
                if model.screenRecordingAsked || model.screenRecordingOn {
                    defaultButton(OnboardingCopy.continueButton, action: advance)  // never blocked (D-06)
                } else {
                    Button(OnboardingCopy.skipButton, action: advance)
                    defaultButton(OnboardingCopy.allowScreenRecordingButton, action: allowScreenRecording)
                }
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

    /// Phase 2's layout metrics: 48–64 pt hero, 16 pt stack, 12 pt text block, 24 pt above the buttons, 440 + 20 pt.
    private func page(
        caption: String?, heading: String, text: String, @ViewBuilder hero: () -> some View,
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
                secondary(text)
                detail()
            }
            HStack(spacing: 12) {
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

import AppKit
import TransomEngine
import SwiftUI

/// Content of the "Set Up Transom" window for every permission state (02-UI-SPEC Surface 2 state matrix).
struct SetupView: View {
    @ObservedObject var permission: PermissionController
    /// `<App>` in the copy: CFBundleName, "Transom" or "Transom Debug".
    let appName: String
    let close: () -> Void

    var body: some View {
        let state = permission.state
        let resetting = state.phase == .resetting
        // While resetting, the window keeps showing the state the reset started from.
        let shown = resetting ? (state.phaseBeforeReset ?? .notTrusted) : state.phase
        let firstRun = (shown == .notTrusted || shown == .waitingForGrant) && !state.afterReset
        VStack(alignment: .leading, spacing: 16) {
            hero(shown)
            VStack(alignment: .leading, spacing: 12) {
                Text(verbatim: heading(shown, afterReset: state.afterReset)).font(.title).fontWeight(.semibold)
                if let text = bodyText(shown, afterReset: state.afterReset) { secondary(text) }
            }
            if firstRun { steps }
            if let caption = resetting ? "Resetting permission\u{2026}" : statusCaption(shown) { statusRow(caption) }
            if shown == .waitingForGrant && state.showStaleFormB { calloutB }
            if let code = state.resetFailedCode, shown != .ready { calloutE(code) }
            buttonRow(shown, resetFailed: state.resetFailedCode != nil)
                .padding(.top, 8)  // 16 pt stack spacing + 8 = the 24 pt gap above the button row
        }
        .disabled(resetting)
        .frame(width: 440, alignment: .leading)
        .padding(20)
    }

    // MARK: - Blocks

    private func hero(_ phase: PermissionPhase) -> some View {
        let (symbol, color): (String, NSColor) =
            switch phase {
            case .ready: ("checkmark.circle.fill", .systemGreen)
            case .staleTrustedButFailing: ("exclamationmark.triangle.fill", .systemOrange)
            default: ("rectangle.split.2x1", .secondaryLabelColor)
            }
        return Image(systemName: symbol)
            .font(.system(size: 48))  // the one fixed size: it sizes a glyph
            .symbolRenderingMode(.hierarchical)
            .foregroundStyle(Color(nsColor: color))
            .accessibilityHidden(true)
    }

    private var steps: some View {
        VStack(alignment: .leading, spacing: 8) {
            step("1. Click Open System Settings.")
            step("2. Turn on \u{201C}\(appName)\u{201D} in the Accessibility list. If macOS asks first, choose Open System Settings.")
            step("3. Come back here. Transom continues by itself.")
        }
    }

    private func statusRow(_ caption: String) -> some View {
        HStack(spacing: 8) {
            ProgressView().controlSize(.small)
            Text(verbatim: caption).font(.caption).foregroundStyle(Color(nsColor: .secondaryLabelColor))
        }
    }

    private var calloutB: some View {
        callout {
            Text("Already turned on?").font(.headline)
            secondary("If the switch next to \u{201C}\(appName)\u{201D} is on but Transom is still waiting, the entry belongs to an older build. Reset it, then turn \(appName) on again.")
            Button("Reset Permission") { permission.send(.resetClicked) }
        }
    }

    private func calloutE(_ code: Int32) -> some View {
        callout {
            HStack(spacing: 8) {
                Image(systemName: "xmark.octagon.fill")
                    .font(.system(size: 16))
                    .foregroundStyle(Color(nsColor: .systemRed))
                    .accessibilityLabel("Error")
                Text("Couldn't reset the permission").font(.headline)
            }
            secondary(MenuCopy.resetFailedBody(code: code, appName: appName))
            Button("Open System Settings", action: openSettings)
        }
    }

    @ViewBuilder private func buttonRow(_ phase: PermissionPhase, resetFailed: Bool) -> some View {
        HStack(spacing: 12) {
            Spacer()
            switch phase {
            case .ready:
                defaultButton("Done", action: close)
            case .probing:
                quitButton
            case .staleTrustedButFailing where !resetFailed:
                quitButton
                Button("Open System Settings", action: openSettings)
                defaultButton("Reset Permission") { permission.send(.resetClicked) }
            default:
                quitButton
                defaultButton("Open System Settings", action: openSettings)
            }
        }
    }

    // MARK: - Pieces

    private var quitButton: some View {
        Button("Quit Transom") { NSApp.terminate(nil) }
    }

    private func defaultButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(title, action: action).keyboardShortcut(.defaultAction).buttonStyle(.borderedProminent)
    }

    private func openSettings() {
        permission.send(.openSettingsClicked(at: permission.elapsed))
    }

    private func step(_ text: String) -> some View {
        Text(verbatim: text).font(.body).fixedSize(horizontal: false, vertical: true)
    }

    private func secondary(_ text: String) -> some View {
        Text(verbatim: text).font(.body).foregroundStyle(Color(nsColor: .secondaryLabelColor))
            .fixedSize(horizontal: false, vertical: true)
    }

    private func callout(@ViewBuilder _ content: () -> some View) -> some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 12, content: content)
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: - Copy (02-UI-SPEC "Setup window copy")

    private func heading(_ phase: PermissionPhase, afterReset: Bool) -> String {
        switch phase {
        case .ready: "Transom is ready"
        case .probing: "Checking access"
        case .staleTrustedButFailing: "Accessibility access isn't working"
        case .waitingForGrant where afterReset: "Turn Transom on again"
        default: "Let Transom arrange your windows"
        }
    }

    private func bodyText(_ phase: PermissionPhase, afterReset: Bool) -> String? {
        switch phase {
        case .ready:
            "Transom can see and move your windows. It lives in the menu bar: click its icon to see what it's tracking."
        case .probing:
            nil
        case .staleTrustedButFailing:
            "macOS lists \(appName) as allowed, but window requests are being refused. This usually happens after Transom is rebuilt or updated. Reset the permission, then turn \(appName) on again in System Settings."
        case .waitingForGrant where afterReset:
            "The old entry is gone. Turn on \u{201C}\(appName)\u{201D} in System Settings \u{25B8} Privacy & Security \u{25B8} Accessibility. Transom continues by itself."
        default:
            "Transom needs Accessibility access to see, move and resize other apps' windows. It doesn't read what's inside them."
        }
    }

    private func statusCaption(_ phase: PermissionPhase) -> String? {
        switch phase {
        case .waitingForGrant: "Waiting for access\u{2026}"
        case .probing: "Checking that Transom can reach your windows\u{2026}"
        default: nil
        }
    }
}

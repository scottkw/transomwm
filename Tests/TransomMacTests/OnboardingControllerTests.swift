import AppKit
import TransomEngine
@testable import TransomMac
import Testing

// The seam `overrideStateForTesting` exists in debug builds only.
#if DEBUG

/// SHIP-02, D-05, D-06: when Set Up Transom opens, which steps it shows, and what closing or a grant does mid-flow.
/// Like SetupWindowTests: throwaway defaults, `makeWindow()` only (never `show()`), and no `permission.send(_:)`.
@Suite @MainActor struct OnboardingControllerTests {
    @Test func aFirstRunShowsWelcomeEvenWhenTrusted() {
        let decision = SetupWindowController.launchDecision(completed: false, phase: .ready)
        #expect(decision.show)
        #expect(decision.steps.first == .welcome)
        let controller = SetupWindowController(permission: permission(.ready), defaults: throwawayDefaults())
        _ = controller.makeWindow()
        #expect(controller.model.current == .welcome)
    }

    @Test func afterCompletionOnlyAMissingGrantOpensTheSingleStep() {
        #expect(!SetupWindowController.launchDecision(completed: true, phase: .ready).show)
        let missing = SetupWindowController.launchDecision(completed: true, phase: .notTrusted)
        #expect(missing.show)
        #expect(missing.steps == [.accessibility])
        #expect(OnboardingFlow.caption(for: .accessibility, in: missing.steps) == nil)
    }

    @Test func closingBeforeTheEndLeavesTheFirstRunPending() {
        let defaults = throwawayDefaults()
        let controller = SetupWindowController(permission: permission(.notTrusted), defaults: defaults)
        let window = controller.makeWindow()
        let closing = Notification(name: NSWindow.willCloseNotification, object: window)
        controller.windowWillClose(closing)
        controller.advance()
        #expect(controller.model.current == .accessibility)
        controller.windowWillClose(closing)
        #expect(defaults.object(forKey: SetupWindowController.completedKey) == nil)
    }

    @Test func readyDuringOnboardingMovesOnByItself() {
        let permission = permission(.waitingForGrant)
        let controller = SetupWindowController(permission: permission, defaults: throwawayDefaults())
        let fake = FakeScreenRecording(controller)
        _ = controller.makeWindow()
        controller.advance()
        #expect(controller.model.current == .accessibility)
        var ready = PermissionState()
        ready.phase = .ready
        permission.overrideStateForTesting(ready)
        #expect(controller.model.current == .screenRecording)
        #expect(fake.requests == 0)
    }

    @Test func allowRequestsExactlyOncePerClick() {
        let (controller, fake) = atScreenRecording()
        #expect(fake.requests == 0)
        controller.allowScreenRecording()
        #expect(fake.requests == 1)
        #expect(controller.model.screenRecordingAsked)
    }

    @Test func theStepOnlyPollsAfterwards() {
        let (controller, fake) = atScreenRecording()
        controller.allowScreenRecording()
        let checksBefore = fake.checks
        for _ in 0..<5 { controller.pollScreenRecording() }
        #expect(fake.requests == 1)
        #expect(fake.checks >= checksBefore + 5)
        fake.granted = true
        controller.pollScreenRecording()
        #expect(controller.model.screenRecordingOn)
        #expect(fake.requests == 1)
    }

    @Test func continueIsNeverBlockedWhileWaiting() {
        let (controller, fake) = atScreenRecording()
        controller.allowScreenRecording()
        #expect(!controller.model.screenRecordingOn)
        controller.advance()
        #expect(controller.model.current == .launchAtLogin)
        controller.back()
        controller.back()
        #expect(controller.model.current == .accessibility)
        #expect(fake.requests == 1)
    }

    @Test func reachingTheStepMarksThePreviewsAlertAnswered() {
        let defaults = throwawayDefaults()
        let controller = SetupWindowController(permission: permission(.ready), defaults: defaults)
        _ = FakeScreenRecording(controller)
        #expect(!defaults.bool(forKey: ZoomController.explainerShownKey))
        controller.advance()
        #expect(controller.model.current == .screenRecording)
        #expect(defaults.bool(forKey: ZoomController.explainerShownKey))
    }

    @Test func closingFromScreenRecordingCompletes() {
        let defaults = throwawayDefaults()
        let (controller, _) = atScreenRecording(defaults)
        #expect(defaults.string(forKey: SetupWindowController.stepKey) == "screenRecording")
        controller.windowWillClose(Notification(name: NSWindow.willCloseNotification))
        #expect(defaults.bool(forKey: SetupWindowController.completedKey))
    }

    @Test func openSettingsCompletesAndOpensSettings() {
        let defaults = throwawayDefaults()
        let (controller, _) = atScreenRecording(defaults)
        var opened: [SettingsPane?] = []
        controller.openSettings = { opened.append($0) }
        controller.advance()
        controller.advance()
        #expect(controller.model.current == .done)
        controller.openSettingsFromDone()
        #expect(opened == [nil])
        #expect(defaults.bool(forKey: SetupWindowController.completedKey))
    }

    @Test func continueRegistersWhenTicked() {
        let (controller, login) = atLaunchAtLogin()
        #expect(controller.model.launchAtLogin, "ticked by default (D-07)")
        #expect(login.registers == 0, "nothing registers before Continue")
        controller.continueLaunchAtLogin()
        #expect(login.registers == 1)
        #expect(controller.model.current == .done)
    }

    @Test func untickedContinueRegistersNothing() {
        let (controller, login) = atLaunchAtLogin()
        controller.model.launchAtLogin = false
        controller.continueLaunchAtLogin()
        #expect(login.registers == 0)
        #expect(login.unregisters == 0)
        #expect(controller.model.current == .done)
    }

    @Test func needsApprovalStaysThenMovesOnSecondContinue() {
        let (controller, login) = atLaunchAtLogin()
        login.statusAfterRegister = .requiresApproval
        controller.continueLaunchAtLogin()
        #expect(controller.model.current == .launchAtLogin)
        #expect(controller.model.loginResult?.needsApproval == true)
        controller.continueLaunchAtLogin()
        #expect(controller.model.current == .done)
        #expect(login.registers == 1)
    }

    @Test func aRegisterErrorStaysThenMovesOn() {
        let (controller, login) = atLaunchAtLogin()
        login.registerError = FakeLoginItem.Refused()
        controller.continueLaunchAtLogin()
        #expect(controller.model.current == .launchAtLogin)
        #expect(controller.model.loginResult?.footer == SettingsCopy.loginItemFailed)
        controller.continueLaunchAtLogin()
        #expect(controller.model.current == .done)
    }

    /// A first-run controller on the Launch at login step, with its login item faked.
    private func atLaunchAtLogin() -> (SetupWindowController, FakeLoginItem) {
        let (controller, _) = atScreenRecording()
        let login = FakeLoginItem(status: .notRegistered)
        controller.loginItem = login
        controller.advance()
        return (controller, login)
    }

    /// A first-run controller on the Screen Recording step (ready access skips step 2), with fakes wired.
    private func atScreenRecording(_ defaults: UserDefaults? = nil) -> (SetupWindowController, FakeScreenRecording) {
        let controller = SetupWindowController(permission: permission(.ready), defaults: defaults ?? throwawayDefaults())
        let fake = FakeScreenRecording(controller)
        controller.loginItem = FakeLoginItem(status: .notRegistered)
        controller.advance()
        return (controller, fake)
    }

    private func permission(_ phase: PermissionPhase) -> PermissionController {
        let permission = PermissionController(system: AXWindowSystem())
        var state = PermissionState()
        state.phase = phase
        permission.overrideStateForTesting(state)
        return permission
    }

    /// Counts what onboarding asks Screen Recording, standing in for SnapshotCapture (ZoomOffTests counts its touches).
    @MainActor final class FakeScreenRecording {
        var granted = false
        var checks = 0
        var requests = 0

        init(_ controller: SetupWindowController) {
            controller.screenRecordingGranted = { [self] in
                checks += 1
                return granted
            }
            controller.requestScreenRecording = { [self] in
                requests += 1
                return granted
            }
        }
    }

    private func throwawayDefaults() -> UserDefaults {
        let name = "OnboardingControllerTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return defaults
    }
}
#endif

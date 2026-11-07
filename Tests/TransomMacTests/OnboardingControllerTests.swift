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
        _ = controller.makeWindow()
        controller.advance()
        #expect(controller.model.current == .accessibility)
        var ready = PermissionState()
        ready.phase = .ready
        permission.overrideStateForTesting(ready)
        #expect(controller.model.current == .done)
    }

    private func permission(_ phase: PermissionPhase) -> PermissionController {
        let permission = PermissionController(system: AXWindowSystem())
        var state = PermissionState()
        state.phase = phase
        permission.overrideStateForTesting(state)
        return permission
    }

    private func throwawayDefaults() -> UserDefaults {
        let name = "OnboardingControllerTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return defaults
    }
}
#endif

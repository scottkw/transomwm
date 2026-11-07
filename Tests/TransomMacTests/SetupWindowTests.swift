import AppKit
import TransomEngine
@testable import TransomMac
import Testing

// The seam `overrideStateForTesting` exists in debug builds only.
#if DEBUG

/// G-02-1 (WIN-01, D-02): with no Accessibility grant the Set Up Transom window opened at 1x28, a title bar with
/// no content. These tests build the window with `makeWindow()` and never show it, so they run headless. They
/// never call `permission.send(_:)` either: its effects are live (system prompt, System Settings, AX probe,
/// tracking), so the state is changed through `overrideStateForTesting(_:)` instead.
@Suite @MainActor struct SetupWindowTests {
    @Test func theSetupWindowHasItsContentSizeBeforeItIsShown() throws {
        let permission = PermissionController(system: AXWindowSystem())
        let window = SetupWindowController(permission: permission, defaults: completedDefaults()).makeWindow()
        let content = window.contentLayoutRect.size
        let fitting = try #require(window.contentViewController).view.fittingSize
        #expect(!window.isVisible)
        #expect(content.width > 1 && content.height > 1)
        #expect(abs(content.width - fitting.width) <= 1)
        #expect(abs(content.height - fitting.height) <= 1)
        if let screen = NSScreen.screens.first?.visibleFrame {
            #expect(abs(window.frame.midX - screen.midX) <= 1)
            #expect(abs(window.frame.midY - screen.midY) <= 1)
        }
    }

    @Test func theSetupWindowHeightFollowsAPermissionStateChange() async throws {
        let permission = PermissionController(system: AXWindowSystem())
        let window = SetupWindowController(permission: permission, defaults: completedDefaults()).makeWindow()
        let hostingView = try #require(window.contentViewController).view
        let before = window.contentLayoutRect.height
        let beforeFitting = hostingView.fittingSize.height
        var ready = PermissionState()
        ready.phase = .ready
        permission.overrideStateForTesting(ready)
        // Wait for SwiftUI to re-render the ready content, then for the window to follow it.
        let fitsNewContent = await waitFor {
            let fitting = hostingView.fittingSize.height
            return abs(fitting - beforeFitting) > 1 && abs(window.contentLayoutRect.height - fitting) <= 1
        }
        let after = hostingView.fittingSize.height
        // The ready content must differ in height, or the test would pass with a window that never resizes.
        try #require(abs(after - beforeFitting) > 1)
        #expect(abs(before - beforeFitting) <= 1)
        #expect(fitsNewContent)
        #expect(abs(window.contentLayoutRect.height - after) <= 1)
    }

    /// A throwaway suite with onboarding done, so the window is Phase 2's single Accessibility step.
    private func completedDefaults() -> UserDefaults {
        let name = "SetupWindowTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        defaults.set(true, forKey: SetupWindowController.completedKey)
        return defaults
    }

    private func waitFor(_ condition: () -> Bool) async -> Bool {
        for _ in 0..<200 where !condition() { try? await Task.sleep(for: .milliseconds(10)) }
        return condition()
    }
}
#endif

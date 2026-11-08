---
status: diagnosed
trigger: "G-02-1: With no Accessibility grant, launch opens a readable Set Up window with a default Open System Settings button. Actual: window exists at 1x28 (title bar only), never sized by its SwiftUI content."
created: 2026-10-27T20:00:00-05:00
updated: 2026-10-27T20:25:00-05:00
audit_acknowledged:
  milestone: v0.9.0
  at: 2026-11-08
  status: diagnosed
---

## Current Focus

hypothesis: CONFIRMED. `hosting.sizingOptions = [.intrinsicContentSize]` only sets the hosting view's intrinsicContentSize; NSWindow does not size itself from its content view's intrinsic size, so the window keeps the zero content size it got from `NSWindow(contentViewController:)` (frame 1x28) forever
test: done (scratch copy of makeWindow() in the VM, one variable changed per run)
expecting: n/a
next_action: none (diagnose-only); hand the fix direction to plan-phase --gaps
bug_class: Bohrbug (deterministic: every first show of the setup window)

reasoning_checkpoint:
  hypothesis: "The setup window is 1x28 because SetupWindowController.makeWindow sets NSHostingController.sizingOptions to [.intrinsicContentSize], which publishes the SwiftUI size only as the view's intrinsicContentSize. NSWindow ignores that for its content view, and nothing else (preferredContentSize, contentMinSize/MaxSize, setContentSize) gives it a size, so the window keeps the 0-pt content area it was created with."
  confirming_evidence:
    - "Scratch copy of makeWindow() (same sizingOptions, KeyClosableWindow(contentViewController:), styleMask, layoutIfNeeded, centring) in the VM: CG bounds 511.0,355.0 1.0x28.0, identical to the real Transom Debug#69"
    - "In that copy hosting.view.intrinsicContentSize and fittingSize are correct (480x324.5, then 480x225 after the state change) while window.frame stays 1x28 at every checkpoint up to 2.5 s"
    - "Changing only sizingOptions to [.preferredContentSize] (or [.minSize, .intrinsicContentSize, .maxSize]) sizes the window to 480x353 by the end of layoutIfNeeded, centres it, and follows the state change to 480x253"
  falsification_test: "If the window stayed 1x28 with [.preferredContentSize], or the copy with [.intrinsicContentSize] sized correctly, the hypothesis would be wrong. Neither happened."
  fix_rationale: "[.preferredContentSize] makes the hosting controller publish its SwiftUI size as preferredContentSize, which NSWindow applies to its contentViewController's window. That gives the window a real size before the centring code reads window.frame and keeps resizing it when the permission state changes the content, as the code comment intends."
  blind_spots: "Not run on macOS 27 (host is off limits for live runs); the lookalike view, not the real SetupView, was measured; the real app was not rebuilt with the change."
  candidate_causes:
    - "code: sizingOptions = [.intrinsicContentSize] never reaches the window (CONFIRMED)"
    - "config: styleMask [.titled, .closable] (no .resizable) blocks Auto Layout window resizing (ELIMINATED, variant B)"
    - "data: SwiftUI content measures 0 for the notTrusted state (ELIMINATED, intrinsic 480x324.5)"
    - "environment: macOS 15 vs 27 AppKit/SwiftUI difference (not tested; irrelevant to the fix, which works on 15)"
  and_gate: "no. Changing sizingOptions alone fixes it with the styleMask, centring and content unchanged."

## Symptoms

expected: Launching Transom Debug with no Accessibility grant shows the "Set Up Transom" window (SwiftUI SetupView in an NSHostingController, Sources/TransomMac/Permission/SetupWindowController.swift), sized to its content, centred, with a default Open System Settings button.
actual: The window exists but has no content. CGWindowList in the VM shows `Transom Debug#69 pid 1021 layer 0 bounds 511.0,355.0 1.0x28.0`, a title bar only, centred at the screen midpoint. It stayed 1x28 after the grant was given and tracking started; the menu-bar status item worked normally.
errors: none logged
reproduction: Tart VM pane-test (macOS 15.7.7). Install a Debug build (scripts/build-debug.sh), tccutil reset Accessibility com.eightabyte.transom.debug, open "/Applications/Transom Debug.app" from SSH, list windows with /tmp/cglist.
started: First live run of Phase 2 UAT test 1 (2026-10-27). Never observed before (UAT deferred). Tracked Windows window (KeyClosableWindow + NSHostingController) opens at 960x508.

## Eliminated

- hypothesis: The non-resizable styleMask ([.titled, .closable]) stops Auto Layout from growing the window
  evidence: Variant B keeps the default resizable mask from NSWindow(contentViewController:) and still stays 1x28 at every checkpoint
  timestamp: 2026-10-27T20:15:00-05:00

- hypothesis: SetupView measures zero (empty or failed body for the notTrusted state)
  evidence: In the copy, hosting.view.intrinsicContentSize and fittingSize are 480x324.5 (then 480x225 for the ready state) while the window stays 1x28
  timestamp: 2026-10-27T20:15:00-05:00

- hypothesis: The window is sized but too late for the centring code, which then places it with a stale size
  evidence: With [.intrinsicContentSize] the size never changes at all, not even 2.5 s after show; the problem is not ordering
  timestamp: 2026-10-27T20:15:00-05:00

## Evidence

- timestamp: 2026-10-27T20:00:00-05:00
  checked: knowledge-base.md
  found: one entry (safari-toolbar-drag-no-dock), no keyword overlap with window sizing / NSHostingController
  implication: no known-pattern candidate

- timestamp: 2026-10-27T20:00:00-05:00
  checked: SetupWindowController.makeWindow vs TrackedWindowsWindowController.makeWindow
  found: Setup uses `hosting.sizingOptions = [.intrinsicContentSize]` (line 44), `KeyClosableWindow(contentViewController:)`, styleMask [.titled, .closable], `layoutIfNeeded()`, then centres with `window.frame.size`; it never sets a content size. Tracked Windows uses `sizingOptions = []` plus an explicit `setContentSize(960x480)`.
  implication: the working window is sized by hand; the broken one depends entirely on SwiftUI-to-window size propagation, so the 960x508 comparison never exercised the failing path

- timestamp: 2026-10-27T20:12:00-05:00
  checked: Scratch app (scratchpad sizerepro/main.swift) copying makeWindow() line by line with a SetupView lookalike (VStack, 440-pt frame, 20-pt padding, fixedSize texts, ProgressView, borderedProminent default button), built with swiftc -target arm64-apple-macos14.0 and run in the VM (macOS 15.7.7) via `open`; logs window.frame, contentLayoutRect, hosting.view.intrinsicContentSize/fittingSize, preferredContentSize, contentMin/MaxSize after init, after layoutIfNeeded, after show, at 1 s, and at 2.5 s after switching the model to "ready"
  found: Variant A (exact copy): frame 1x28, content 1x0 at every checkpoint; intrinsic 480x324.5, then 480x225; CGWindowList `SizeRepro#308 ... bounds 511.0,355.0 1.0x28.0`, the same bounds as the real Transom Debug#69
  implication: the bug reproduces outside Transom with only the makeWindow() code, so it is in that code, not in PermissionController, SetupView or launch timing

- timestamp: 2026-10-27T20:14:00-05:00
  checked: Same scratch app, one change per variant
  found: |
    B [.intrinsicContentSize], resizable mask kept: 1x28 throughout
    C [.preferredContentSize]: 480x353 already after layoutIfNeeded; centred (CG 272,193); shrinks to 480x253 on the state change with the top edge fixed
    D [.minSize, .intrinsicContentSize, .maxSize]: 480x353 after layoutIfNeeded (contentMin = contentMax = 480x325); follows the state change to 480x253
    E [] (default): 1x28 throughout
    F/G explicit setContentSize(fittingSize): 480x353 at first, but stays 353 high after the state change (does not follow content)
  implication: NSWindow takes its size from the hosting controller's preferredContentSize or from contentMin/MaxSize, never from the content view's intrinsicContentSize; [.preferredContentSize] is the one-word fix that also keeps "height follows each state's content"

- timestamp: 2026-10-27T20:19:00-05:00
  checked: VM screenshot of variant C
  found: readable window with heading, body text and the Quit / Open System Settings button row
  implication: the content renders once the window has a size

## Resolution

root_cause: SetupWindowController.makeWindow() (Sources/TransomMac/Permission/SetupWindowController.swift:44) sets `hosting.sizingOptions = [.intrinsicContentSize]`, expecting the window to follow SwiftUI's size. That option only updates the hosting view's intrinsicContentSize. NSWindow does not size itself from its content view's intrinsic size, and the controller never sets preferredContentSize, contentMin/MaxSize or a content size. The window therefore keeps the 0-pt content area it got from `NSWindow(contentViewController:)` on an unsized hosting view: frame 1x28 (title bar only). The centring code then centres that 1x28 frame (hence 511,355 on the 1024x768 VM screen), and later state changes (grant, ready) update only the intrinsic size, so the window never grows.
confidence: high. The scratch copy of makeWindow() reproduces the exact CG bounds (511.0,355.0 1.0x28.0) on the same VM, and changing only sizingOptions fixes it.
fix: (suggested, not applied) change line 44 to `hosting.sizingOptions = [.preferredContentSize]` (the window applies the SwiftUI size before layoutIfNeeded returns, so the existing centring works, and it resizes with each permission state, top edge fixed). `[.minSize, .intrinsicContentSize, .maxSize]` also works but pins the content min/max size. Don't use a one-off setContentSize(fittingSize): it doesn't follow the state changes. Regression guard: in TransomMacTests (or a VM check), after makeWindow() + layoutIfNeeded, assert window.contentLayoutRect.size equals hosting.view.fittingSize (non-zero), then change the state and assert the height follows.
verification: diagnose-only; fix not applied
files_changed: []

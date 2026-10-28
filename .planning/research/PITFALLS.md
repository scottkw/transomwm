# Pitfalls Research

**Domain:** macOS window manager (Accessibility-driven, nested tiling, snapshot-overlay "zoom", private-API Spaces, gesture and Mission Control integration)
**Researched:** 2026-10-23
**Confidence:** MEDIUM overall. Most findings come straight from maintainer comments in the AeroSpace, yabai, Amethyst, Rectangle, Loop, AltTab and OpenMultitouchSupport issue trackers, read with `gh`. Primary sources, though usually one project's experience each. Where more than one project saw the same failure, it is marked "cross-checked". Claims that come only from web search are marked LOW.

Phase numbers refer to PLAN.md section 3: 1 Model, 2 Window control, 3 Tiling MVP, 4 Camera + zoom, 5 Gestures, 6 Overview + Spaces, 7 Tab groups, 8 Saved views + URL commands, 9 Polish + ship.

---

## Critical Pitfalls

### Pitfall 1: Making AX calls on the main thread (or one shared thread), so a single hung app freezes the whole WM

**What goes wrong:**
AX calls are synchronous IPC into the target app's main thread. If the app is busy (JetBrains IDEs, Godot, Unity, Emacs during `sleep`, LibreOffice), the call blocks for the messaging timeout, which defaults to about 6 s. Every focus change, reflow and drag then stalls behind it. AeroSpace issue #131 ("Delay/freeze when switching focus", 62 comments) is the standard example. The fix was a rewrite of the core into one thread per application, which took more than a year. #1615 shows the problem was still there in 2025: window detection waited on all app threads, so one slow app (Godot) still delayed new-window detection by up to 5 s.

**Why it happens:**
The AX API looks like ordinary property access, so developers call it from wherever. Apple doesn't document whether it is thread-safe. AeroSpace found by experiment that per-app threads work.

**How to avoid:**
- Give each `pid` a serial executor, meaning a dedicated thread running its own `CFRunLoop`. That thread owns the `AXUIElement`s and the `AXObserver` run-loop source. All AX traffic for the app goes through it.
- Call `AXUIElementSetMessagingTimeout` on each app element. Start around 0.5–1 s (AeroSpace uses 1 s) and back off for apps that keep timing out.
- Make the engine reactive. The main actor sends requests out and merges results as they arrive. It never waits on "all apps answered" (AeroSpace #1615).
- Coalesce frame writes: a new `setFrame` for a window cancels any pending one for the same window. AeroSpace keeps a `setFrameJobs[windowId]` map for this.
- Never send AX requests to Pane's own pid. AeroSpace notes these crash or deadlock.

**Warning signs:**
UI hitches that track one specific app. Main-thread hangs in Instruments showing `AXUIElementCopyAttributeValue` or `_AXUIElementSetAttributeValue`. Users saying "it's slow when IntelliJ is open."

**Phase to address:** Phase 2. This shapes the `WindowSystem` protocol: it has to be async from the start. Retrofitting it later is the rewrite AeroSpace went through.

**Confidence:** HIGH (cross-checked: AeroSpace #131/#1615, and AeroSpace cites yabai #599/#600/#2377).

---

### Pitfall 2: Treating "AX can't see the window right now" as "the window closed", which collapses the layout

**What goes wrong:**
The tree drops a window and reflows when the window still exists. Nested layouts get destroyed by ordinary events. The reverse also happens: ghost tiles hold space for windows that are really gone. The triggers seen in the wild:
- **Screen lock:** `_AXUIElementGetWindow` returns nil for every element while the screen is locked. On unlock, windows "close" and "reopen" with reused window IDs (AeroSpace #445, #771). Every window jumped to the focused workspace until 0.19.0 (AeroSpace #1216).
- **Slow app:** a timeout (`kAXErrorCannotComplete`, -25204) got treated as "dead window", so single windows jumped (AeroSpace #1216).
- **Native Spaces:** `kAXWindowsAttribute` doesn't list an app's windows on other Spaces (AltTab #447, maintainer: "this api doesn't list windows from other Spaces").
- **Unreliable notifications:** `kAXUIElementDestroyedNotification` is sometimes never delivered, for example when several windows close quickly. On Sequoia, some third-party AX apps (Contexts, Amazon Q) seemed to stop it entirely for everyone (AeroSpace #445, #514). Closed windows kept their tiles.
- **Ghost windows** from minimise/hide on some apps (AeroSpace #1615 comments, Amethyst #1896 "windows of a quit app are never removed, leaving a ghost half-screen", Amethyst #1350 Arc phantom window).

**Why it happens:**
"Present in AX" gets used as the definition of "exists". The AX notification stream gets trusted as complete.

**How to avoid:**
- Give each tracked window an explicit lifecycle state: `alive`, `minimized`, `appHidden`, `fullscreen`, `onOtherSpace`, `unresponsive`, `suspendedLock`, `closed`. Only `closed` removes a node from the tree.
- Confirm closure from two sources: an AX invalid-element error (`kAXErrorInvalidUIElement`, -25202) **and** the window ID missing from the CG/SkyLight window list. A timeout is never closure.
- Pause reconciliation between `com.apple.screenIsLocked` and `com.apple.screenIsUnlocked`, and across sleep/wake. Snapshot the tree before lock and restore it after.
- Run a periodic reconcile (AeroSpace's "refresh session" pattern) that finds new windows and garbage-collects dead ones. Keep it per-app and async so a hung app only delays its own GC.
- Keep a closed-window ID cache so a reused ID isn't mistaken for the old window.

**Warning signs:**
Empty tiles after closing windows. Layout reset after unlock. Windows jumping after a Space switch. Gaps that grow with each close.

**Phase to address:** Phase 1 (model states for a window that is "absent but not removed", and a reserved slot) and Phase 2 (lifecycle reconciliation). Phase 6 has to extend it to Spaces.

**Confidence:** HIGH (cross-checked across AeroSpace, Amethyst, AltTab).

---

### Pitfall 3: Parked or shrunk windows stranded when Pane exits, crashes or updates

**What goes wrong:**
Pane's zoom design parks off-view windows small and resizes real windows to match the camera. If Pane crashes, is force-quit, gets killed by a Sparkle update, or the Mac panics, those windows stay tiny or shoved into corners. The user has no idea where their work went. AeroSpace's guide warns about this: "if AeroSpace crashes badly you will still be able to manually 'unhide' the windows by dragging these few pixels". It also documents that macOS won't place a window fully off-screen, so a sliver always shows (#66, later cut to 1 px).

**Why it happens:**
The real window geometry only lives in memory. Teardown paths (signals, update relaunch, `applicationWillTerminate`) don't restore frames, or can't, because the process is already dead.

**How to avoid:**
- Persist each managed window's "home frame", its last user-meaningful frame, to disk whenever it changes (debounced). Key it by `(bundleID, windowID)` plus a title/frame fingerprint.
- On normal quit and before a Sparkle relaunch: synchronously restore every parked window, with a bounded timeout per app. AeroSpace has `setAxFrameForTermination` with a semaphore for this.
- On launch: if the previous session didn't shut down cleanly (a dirty flag in `UserDefaults`), restore every parked window found on screen before doing anything else.
- Add a "Restore all windows" item to the menu bar, plus a `pane://restore` command, so a hung Pane is recoverable from Raycast or Terminal.
- Park by **moving** at the current size where possible, and shrink only when you must. Shrinking forces reflow (Pitfall 9).

**Warning signs:**
QA finds 1-px slivers at the screen corner after `kill -9`. Bug reports saying "all my windows are tiny".

**Phase to address:** Phase 3 (home frames and restore-on-quit, the first time Pane moves windows), Phase 4 (parking makes it critical), Phase 9 (Sparkle relaunch path).

**Confidence:** HIGH (AeroSpace guide and #66; the parking risk follows from Pane's own design).

---

### Pitfall 4: Private APIs break every year, and the breakage looks like a Pane bug

**What goes wrong:**
Each major macOS release, and some point releases, quietly changes or locks down SkyLight/CGS, CoreDock or MultitouchSupport. Recent history:
- **macOS 14.5:** moving windows between Spaces without SIP stopped working. yabai maintainer: "Apple did Apple things and made the function protected" (yabai #2240). Amethyst and TotalSpaces broke the same way. Amethyst later dropped "throw to space" (discussion #1682).
- **Sequoia 15:** the SIP-enabled window-to-Space workaround broke again (yabai #2500). The remaining workaround fakes a mouse-down on the title bar plus a Space-switch hotkey, which needs a clickable title bar and can't target inactive Spaces.
- **Tahoe 26:** yabai's scripting addition broke (yabai #2634, 92 comments).
- **macOS 27 (current):** SIP-enabled instant Space switching broke (yabai #2822). MultitouchSupport's contact-frame callback now seems to honour its return value. A callback declared `void` leaves garbage in the return register, the system reads that as "consume", and system 3/4-finger gestures stop while the app streams touches (OpenMultitouchSupport #13).
- A wrong `dlsym` function-pointer signature is memory corruption, not a clean failure.

**Why it happens:**
These APIs have no contract. Apple changes them in betas that ship in June, and most maintainers only test on release day.

**How to avoid:**
- Put each private API in one file (already a project constraint). Resolve with `dlsym`, nil-check, and expose a capability flag (`spacesQueryAvailable`, `multitouchAvailable`, `missionControlTakeoverAvailable`).
- Every private-API feature needs a working public fallback, or it switches itself off cleanly:
  - SkyLight Spaces → no Spaces bar, overview of the current Space only
  - MultitouchSupport → hotkeys plus magnify gesture events (Pitfall 13)
  - CoreDock / symbolic hotkeys → leave Mission Control alone
- Add a crash canary, as proposed in AeroSpace #101. Set a `UserDefaults` flag before the first call into each risky API in a session and clear it after. If the app launches with the flag still set, turn that feature off and tell the user.
- Copy correct prototypes from several header lineages. For MultitouchSupport, declare the contact callback as returning `int32_t` and **return 0** (pass through).
- Never use private APIs to **move windows between Spaces**. That path has broken twice in two years and now needs SIP. Read Spaces only.
- Plan a "macOS beta compatibility" task every June–September. Keep a VM or partition on the current beta.

**Warning signs:**
`dlsym` returns NULL on a new OS. Features silently do nothing. Crash reports clustered on one OS build. Bug reports rising in the first week after a macOS release.

**Phase to address:** Phase 2 (the isolation pattern and capability registry for `_AXUIElementGetWindow`), Phases 5 and 6 (fallbacks and canaries for MultitouchSupport, SkyLight, CoreDock), Phase 9 (release checklist that includes testing on the current beta).

**Confidence:** HIGH (yabai #2240, #2500, #2634, #2822; Amethyst #1682; OMS #13 is one reporter on one beta, MEDIUM for that item).

---

### Pitfall 5: Event-tap callbacks that do real work, so the system disables the tap or lags input system-wide

**What goes wrong:**
macOS disables an event tap whose callback is too slow, and delivers a final `kCGEventTapDisabledByTimeout` event. Hotkeys, drag detection, green-button interception and the Mission Control takeover then die silently. Taps on high-frequency events (mouse moved, scroll, dragged) add latency to every app. Loop #626 had system-wide scroll lag after Loop had been running a while. Rectangle's README has a known issue where drag-snapping froze Notification Center for some users (#317). Loop #1159 suppressed Mission Control by calling `CGWarpMouseCursorPosition` on every drag event, which made the cursor stutter at the top edge.

**Why it happens:**
The obvious way to handle a green-button click or a title-bar drag is to hit-test inside the callback with `AXUIElementCopyElementAtPosition`. That is a synchronous AX call into a possibly hung app, from inside the tap callback.

**How to avoid:**
- No AX, file I/O, locks or logging inside tap callbacks. Copy the event fields into a lock-free queue and return.
- Handle `kCGEventTapDisabledByTimeout` by calling `CGEventTapEnable(tap, true)` and returning the event untouched. Also run a watchdog timer that checks `CGEventTapIsEnabled` every few seconds and re-enables the tap.
- Use the narrowest mask possible. Use listen-only taps or `NSEvent.addGlobalMonitorForEvents` for tracking that never needs to swallow events (drag detection). Use an active tap only for events Pane must eat (⌥-pinch magnify, green-button click, Mission Control keys).
- Don't decide "is this a title-bar drag?" by hit-testing on mouse-down. Watch for the focused window's frame changing while the button is held: AX moved notifications plus a cheap CG window bounds poll at drag rate. That also covers apps with custom title bars (Electron, Chrome tab strip). Loop #724 shows snapping failing on an Electron title bar.
- Detect Secure Input (`IsSecureEventInputEnabled()`, polled) and show it. AeroSpace added an indicator in 0.20 because users kept filing "hotkeys broken" bugs that were really Secure Input from a password field or 1Password (#1486; AltTab #3117).

**Warning signs:**
Hotkeys that "stop working after a while". `kCGEventTapDisabledByTimeout` in logs. Users reporting scroll or cursor lag only while Pane runs.

**Phase to address:** Phase 3 (drag detection and green button), Phase 5 (pinch tap), Phase 6 (Mission Control tap). Build the tap wrapper with re-enable and watchdog once, in Phase 3.

**Confidence:** HIGH for timeout behaviour and re-enable (Apple Cocoa-dev and SDL source cross-checked). MEDIUM for the lag examples (one project each).

---

### Pitfall 6: Fighting the app over its frame (minimum sizes, size increments, self-animation, AXEnhancedUserInterface)

**What goes wrong:**
Pane asks for a rect and the app gives back a different one. Tiles overlap, or Pane and the app loop: Pane resizes, the app snaps back, a moved/resized notification fires, Pane resizes again, at full CPU. Known causes:
- **Minimum sizes:** Rectangle documents a window with a 600 pt minimum that can't fit a 504 pt third. Rectangle "cannot override an app's minimum window size" and shows a HUD instead.
- **Size increments:** iTerm2 snaps to character cells (Rectangle README: `DisableWindowSizeSnap`). Terminal.app does too.
- **Position clamping:** macOS clamps positions to keep windows on screen. Moving a large window to a smaller or offset display before resizing it gives the wrong result. AeroSpace, Rectangle and yabai all use **size → position → size** (AeroSpace issues #143 and #335).
- **`AXEnhancedUserInterface`:** when an assistive app turns this on for a target app (macOS on-screen keyboard, Dragon dictation, Punto, others), AX frame changes animate. The next call cuts off the previous one, so final sizes are wrong. Turning it off is itself slow in Chrome (Rectangle #912, 50 comments). The usual approach is to turn it off around the frame write. Rectangle stopped turning it back on.
- **Native window tabs:** a new Terminal.app tab in a tiled window can make the window go fullscreen (Rectangle #1685).

**Why it happens:**
Layout code treats the requested frame as the actual frame.

**How to avoid:**
- After every write, read the frame back on the app's thread and report `(requested, actual)` to the engine. The model treats `actual > requested` as a learned minimum-size constraint for that window and re-solves the siblings. That way minimum sizes come from observation (Phase 1 already lists minimum sizes as a model feature).
- Give each window a fight budget: at most N corrective writes per second. Past that, accept the app's frame and mark the tile "constrained".
- Use size → position → size, with cancellation checks between the steps.
- Wrap frame writes in a check of `AXEnhancedUserInterface`: if it is on, turn it off. Make re-enabling a per-app setting, default off for Chromium.
- Never turn on `AXManualAccessibility` / `AXEnhancedUserInterface` to "help" Electron or Chrome. It makes them build their full accessibility tree, which costs CPU.

**Warning signs:**
Requested and actual frames disagree in logs (Rectangle's debug log prints both, which is worth copying). CPU spikes with no user input. Overlapping tiles in a layout that should never overlap.

**Phase to address:** Phase 1 (constraint-aware solver that accepts observed minimums) and Phase 2 (read-back, frame-write order, enhanced-UI wrapper). Phase 3 verifies it with Terminal, iTerm2, Chrome, VS Code, Slack and System Settings.

**Confidence:** HIGH (code and comments in AeroSpace, Rectangle and yabai agree).

---

### Pitfall 7: Classifying every AXWindow as a tile (popups, dialogs, native tabs, PiP, quick terminals)

**What goes wrong:**
Tooltips, context menus, find bars, Xcode's "Build succeeded" HUD, the screen-sharing "purple pill", 1Password mini windows, Chrome or Firefox Picture-in-Picture, Ghostty's quick terminal, IntelliJ dialogs, System Settings and the lock screen all show up as `AXWindow`. They get tiled and break the layout. AeroSpace guide: "A lot of apps don't implement this API or implement it improperly", and that includes some Apple dialogs. Native macOS tabs show up as separate windows in Finder, Terminal, TextEdit and IntelliJ (AeroSpace #68, still open; yabai #68, open since 2019, 77 comments). Titles often appear only after the window does, so title rules miss.

**Why it happens:**
Developers check role and subrole once at creation time and move on.

**How to avoid:**
- Copy AeroSpace's method, not its code: a **corpus of recorded AX attribute dumps** per app/window type (`axDumps/*.json5`, about 100 cases, from Chrome PiP to the Emacs child frame) with unit tests over the classifier. That fits the plan nicely, since the classifier is pure and testable in `PaneEngine`.
- Classify on a settle delay (around 100–300 ms) and re-check when the title or subrole changes. Re-classify when fullscreen-button enablement changes. AeroSpace notes a race in Chrome tab drag-out.
- Signals that work: subrole is `AXStandardWindow`; fullscreen button present and enabled (no fullscreen button usually means "not designed to be big", so float it); close/min/zoom buttons present; window level is normal. Keep per-bundle-ID overrides for terminals and other apps that hide decorations (Alacritty, kitty, WezTerm, iTerm2, Emacs, VS Code with `nativeFullScreen: false`).
- Native tabs: several AX windows from one app with the same frame, only one visible. Collapse them into one tile, or into a Pane tab group, which suits Phase 7.
- Ship a default floating/exclusion list and a "float this app/window" toggle from day one.

**Warning signs:**
Tiles that appear when a context menu opens. Empty tiles next to apps using native tabs. "Phantom third window" reports (Amethyst #1350).

**Phase to address:** Phase 2 (classifier plus the dump-corpus test harness), Phase 3 (default exclusions), Phase 7 (native-tab handling, alongside Pane's own tab groups).

**Confidence:** HIGH (AeroSpace source, guide and issues; yabai #68; Amethyst #1350).

---

### Pitfall 8: Native fullscreen, Spaces and "Displays have separate Spaces" handled as an afterthought

**What goes wrong:**
- A native fullscreen window moves to its own Space. AX frame writes on it fail or are ignored. When it leaves fullscreen, the app's exit animation fights Pane's re-tile (yabai #36, "Exit native fullscreen: no resizing").
- With "Displays have separate Spaces" **on**: focus goes to the wrong window across monitors, an Apple API bug (AeroSpace #101; AeroSpace's own fix only held for 2 monitors, not 3). macOS randomly switches focus back (#289). Moving a window between monitors also moves it between Spaces. With it **off**: a second monitor goes black while the first is fullscreen, and windows can't span displays. Changing the setting requires logging out.
- AX doesn't list windows on other Spaces (Pitfall 2). An "overview of every window on every Space" therefore needs SkyLight window enumeration, and those windows have no `AXUIElement`, so there's no title, subrole or focus action. AltTab's workarounds are "janky" (#447).
- Switching Spaces always animates, and the animation can't be turned off without the SIP-disabled scripting addition (AeroSpace guide).

**Why it happens:**
The layout model gets designed around "one screen, one tree". Spaces and fullscreen then get bolted on.

**How to avoid:**
- Settle the open question in PLAN §5 now: **key layout state by `(displayUUID, spaceID)`**, and treat the native Space as read-only context. Pane never moves windows between Spaces (Pitfall 4). A window seen on another Space is `onOtherSpace` and keeps its tile.
- Fullscreen: watch the `AXFullScreen` attribute and resize notifications. Mark the tile `fullscreen` and reserve its slot. On exit, wait for the frame to settle (a few hundred ms with no resize events) before applying the tile frame.
- The overview shows non-current-Space windows from SkyLight data (bounds, owner) with app icon and colour, and accepts that it can't focus them directly. To focus one, switch to that Space first, the public way.
- Detect `NSScreen.screensHaveSeparateSpaces` at launch and in onboarding. Explain the trade-off rather than silently assuming one value. Test both.

**Warning signs:**
Tiles collapse when a window goes fullscreen. A window comes back from fullscreen at the wrong size. Wrong-window focus on multiple monitors.

**Phase to address:** Phase 1 (state keying, reserved slots), Phase 2 (fullscreen state), Phase 6 (Spaces read-only, overview data sources, both "separate Spaces" modes).

**Confidence:** HIGH (AeroSpace guide and issues, yabai #36, AltTab #447).

---

### Pitfall 9: Treating the zoom illusion as a rendering problem when it's a resize-storm and capture-cost problem

**What goes wrong:**
When the camera settles, Pane resizes many real windows over AX. Each resize makes the app re-layout: browsers reflow, Electron apps are slow (Rectangle #912; AeroSpace #149 "windows flash-resize"), and terminals **re-wrap scrollback** whenever their width changes. Doing this for every visible window on every settle, plus parking off-view windows "small", means large CPU spikes, seconds of visible flicker, and changed app state. Meanwhile frequent ScreenCaptureKit captures grow `WindowServer` and `replayd` memory into gigabytes. AltTab #4255 (90 comments): WindowServer at 5.5 GB, 2.5 GB freed on quit. AltTab #4194: replayd above 2 GB. Loop #745: WindowServer at 8–10 GB. The maintainers couldn't fix it from their side. Apple's own advice is "use ScreenCaptureKit", and that still doesn't avoid it.

**Why it happens:**
"Resize real windows to match the camera" sounds cheap, and each capture call looks harmless.

**How to avoid:**
- Animate only the overlay, never real windows. AX is far too slow for 60 fps (yabai needed the scripting addition for animations, #148). Write one final frame per window when the camera settles.
- On settle, resize only windows whose target rect actually changed and that are visible at a useful size. Leave off-view windows at full size and move them away. Shrink only when a window would otherwise overlap the view.
- Per-window snapshot cache: capture at the size actually displayed (`SCStreamConfiguration` width/height scaled to the on-screen thumbnail), refresh on content-change signals, and **capture before parking or shrinking**. A parked window's snapshot would show the parked state.
- Use one-shot `SCScreenshotManager` (macOS 14+) captures, not long-running `SCStream`s, outside active zoom. Running streams show the system "sharing your screen" indicator (AltTab #2606) and keep `replayd` busy.
- Put a budget on captures per second and on cache bytes. Evict least-recently-used entries. Track `WindowServer` RSS in a long-running soak test.
- Make `redraw-settle delay` adaptive per app: measure how long each app takes after a resize before its next frame looks stable.

**Warning signs:**
Settle takes more than 500 ms with 15+ windows. Terminal scrollback rewrapped after zooming. WindowServer RSS above 2 GB after an 8-hour soak.

**Phase to address:** Phase 4. Add an explicit soak-test success criterion, and do a feasibility spike before committing to the full design.

**Confidence:** MEDIUM. The resize costs are cross-checked. Memory growth is reported in several projects but the cause is unclear. Terminal re-wrap is known terminal behaviour applied to Pane's design.

---

### Pitfall 10: Screen Recording treated as required, and the macOS 15 recurring prompt treated as a one-time grant

**What goes wrong:**
On Sequoia, apps using ScreenCaptureKit without the system picker get a recurring "…is requesting to bypass the system private window picker and directly access your screen" alert with "Allow For One Month". 9to5Mac developers confirmed it fires for apps using only modern SCK APIs, and the only way around it is the system picker, which doesn't fit a WM. Apple said in the 15.1 beta that regularly used apps would see fewer prompts. How the final shipped versions behave is only partly confirmed (LOW–MEDIUM). Without the permission, `CGWindowListCopyWindowInfo` also returns **no window titles**, and SCK captures fail. Separately, after app updates or OS upgrades, apps stay listed as "enabled" in Accessibility while AX fails. Loop #418 ("every launch asks"), Amethyst #1856 on Tahoe 26.3, and yabai #2688 (macOS 26.1: path-based TCC clients don't appear in System Settings) all fixed it with `tccutil reset Accessibility <bundle-id>`.

**Why it happens:**
Permission checks run once at onboarding, and `AXIsProcessTrusted()` gets trusted as true.

**How to avoid:**
- Keep Screen Recording optional (already planned). The colour-and-icon fallback must look good on its own, because many users will decline or let the monthly grant lapse.
- Take titles from AX, never from `kCGWindowName`.
- Check permissions **continuously**, not once: at launch, on wake, and when an AX call returns `kAXErrorAPIDisabled` (-25211). Use a real probe, such as reading the system-wide focused application, not just `AXIsProcessTrusted()`.
- When the probe fails but the grant shows as on, show a "stale permission" screen with a copyable `tccutil reset Accessibility <bundle-id>` and a "remove with −, then re-add" walkthrough.
- If SCK capture starts failing in the middle of a session (the monthly grant expired), switch to icon snapshots without crashing or spamming alerts.

**Warning signs:**
Snapshots go blank about 30 days after install. "Keeps asking for accessibility" reports right after a Pane or macOS update.

**Phase to address:** Phase 2 (AX permission probe and stale-grant UX), Phase 4 (SCK optional path and fallback), Phase 9 (onboarding copy that explains the monthly prompt).

**Confidence:** MEDIUM. The monthly prompt is cross-checked across 9to5Mac, TidBITS and TechRadar; the final 15.1+ behaviour is LOW. Stale grants are cross-checked across Loop, Amethyst and yabai.

---

### Pitfall 11: Code-signing identity changes that reset TCC, or a revoked certificate that bricks installs

**What goes wrong:**
TCC grants are tied to the code signature's designated requirement plus bundle ID (and, for bare binaries, the path). Change the Team ID, bundle ID or signing certificate type, or ship an ad-hoc-signed build, and every user loses Accessibility and Screen Recording on update. Dev builds signed differently from release builds clash on the developer's own machine. AeroSpace #167: Apple revoked the maintainer's certificate twice (Apple Development certificate), and AeroSpace stopped starting for everyone. The maintainer changed the bundle ID and later moved to a self-issued certificate. Homebrew: from 2026-09-01, casks that fail Gatekeeper are disabled, and `--no-quarantine` is deprecated or removed (Homebrew 5.0; LOW–MEDIUM on exact status).

**Why it happens:**
Signing gets set up late, in a hurry, in the "polish" phase.

**How to avoid:**
- Choose the final bundle ID (`app.pane.Pane` or similar) **in Phase 2** and never change it. Use a separate bundle ID for debug builds (`…Pane.dev`) so dev and release grants don't collide. AeroSpace ships an `aerospace-dev` cask.
- Sign release builds with a **Developer ID Application** certificate (not Apple Development), hardened runtime, notarised and stapled, from the very first public build, including the first Homebrew cask. CI should check `codesign -d -r-` output against a committed expected designated requirement, so a signing change fails the build.
- Notarisation doesn't reject private API use. Only App Store review does. `dlopen` of Apple-signed private frameworks works under hardened runtime.
- Keep the Sparkle EdDSA private key in two offline places. Losing it strands every installed user.
- Detect App Translocation (running from Downloads or a DMG) and ask the user to move Pane to /Applications before granting permissions. Grants made at the translocated path don't carry over, and `SMAppService` login items expect a stable location.

**Warning signs:**
Permission prompts on every update. Users with Pane "enabled" in Settings but not working. Gatekeeper "cannot check for malicious software" reports.

**Phase to address:** Phase 2 (bundle ID and dev/release split, first time permissions are requested), Phase 9 (Developer ID, notarisation, Sparkle, cask). Do a minimal signed-and-notarised pipeline early, alongside the Phase 3 "first usable release".

**Confidence:** MEDIUM–HIGH (AeroSpace #167, Loop #418, Rectangle README `tccutil` advice; Homebrew policy is LOW–MEDIUM).

---

### Pitfall 12: Mission Control takeover that leaves the user without Mission Control

**What goes wrong:**
Pane disables system symbolic hotkeys (Mission Control, App Exposé) with `CGSSetSymbolicHotKeyEnabled` and triggers or replaces them via event tap and CoreDock. If Pane crashes or is killed, the hotkeys stay disabled for the session. The user's F3 / ⌃↑ do nothing and they blame macOS or Pane. TotalSpaces had "loses hotkeys" reports. The trackpad 3/4-finger "swipe up" is a Dock gesture, not a symbolic hotkey, so disabling hotkeys doesn't intercept it. Dragging a window to the top edge also opens Mission Control on its own, which collides with a top-edge dock target (Loop #609 and #1159). CoreDock notifications are private and change across releases.

**Why it happens:**
The happy path gets tested, the crash path doesn't.

**How to avoid:**
- Make takeover opt-in (already "optional"). Store the original enabled state of each symbolic hotkey you touch.
- Restore on: normal quit, `SIGTERM`, before a Sparkle relaunch, and **at every launch** if the dirty flag is set. A tiny launchd `KeepAlive` helper or the login item can restore hotkeys if the main app dies.
- Don't promise gesture takeover. Document that "swipe up with three fingers" has to be turned off in Trackpad settings, and link the user there.
- For the top-edge drop target: use a drop zone a few points below the top edge, or one inside the menu-bar band, so the pointer never needs to press the very top pixel row. Don't warp the cursor (Loop #1159).

**Warning signs:**
After a test crash, F3 does nothing. Cursor jitter when dragging windows to the top.

**Phase to address:** Phase 6 (takeover and restore paths), Phase 3 (top-edge drop-zone geometry), Phase 9 (helper and update path).

**Confidence:** MEDIUM. The session-scoped state of symbolic hotkeys after a crash is inferred from TotalSpaces reports and API semantics. It should be checked with a deliberate crash test in Phase 6.

---

### Pitfall 13: Gesture input that hijacks or doubles system gestures

**What goes wrong:**
- With MultitouchSupport you can't stop the app under the pointer from also receiving the pinch. Safari or Preview zoom their content while Pane zooms the camera.
- macOS 27 now treats the callback's return value as "consume", so a wrong prototype silences the system's own gestures (OMS #13).
- The default-device API only sees one trackpad. Magic Trackpad hot-plug and multiple devices need `MTDeviceCreateList` plus re-enumeration (OMS #6). Some wrappers crashed after sleep; the workaround was to not release the device (OMS #2).
- Nothing tells you when Bluetooth trackpads reconnect.

**Why it happens:**
Raw touch frames look like a complete gesture source. In fact, the high-level gesture events still reach apps separately.

**How to avoid:**
- Pair raw touch (for responsiveness) with an **active event tap on gesture/magnify event types** that swallows magnify events while ⌥ is held or the pointer is over bare desktop. Fallback when MultitouchSupport is unavailable: drive the camera from the magnify events alone. This is public-ish, works on every OS, and gives worse but usable quality.
- Re-enumerate devices on wake and on IOKit HID add/remove notifications.
- Declare the callback with an `int32_t` return and return 0 (pass through) unless you deliberately consume.

**Warning signs:**
Content zooms under the overlay. System Mission Control swipe stops working while Pane runs. Pinch dead after sleep or trackpad reconnect.

**Phase to address:** Phase 5.

**Confidence:** MEDIUM (OMS issues are single reports; double-delivery follows from how the APIs work).

---

### Pitfall 14: Multi-display coordinate and identity bugs

**What goes wrong:**
- AX uses a top-left-origin global space anchored on the **primary** display. `NSScreen` uses bottom-left. Mixing them sends windows to the wrong monitor, especially with displays arranged above or left of the primary (negative coordinates).
- `CGDirectDisplayID` isn't a durable identity across reboots (Apple docs). It can be null during reconfiguration (Zed source).
- Display reconfiguration callbacks fire several times (begin/end, per display), and `NSScreen.screens` can be stale while they run.
- On wake or unplug, macOS moves and resizes windows itself, asynchronously (Amethyst #1167, "windows get moved to other monitors after waking"). Re-tiling at the same time causes a tug of war.
- Moving between displays with different scale factors flash-resizes windows (AeroSpace #149).
- Hidden or parked windows show on neighbouring monitors unless every display has a free corner (AeroSpace guide §4.1).
- `visibleFrame` changes with Dock auto-hide (Rectangle #1922), the notch, and the menu bar on non-main displays.

**Why it happens:**
Developers test on a single laptop screen.

**How to avoid:**
- Pick one canonical coordinate space in `PaneModel` (AX top-left global). Convert only at the AppKit edge, in one tested function, with unit tests for displays above, left and right of the primary.
- Key display state by `CGDisplayCreateUUIDFromDisplayID`. Keep per-display trees alive when their display goes away, as orphaned trees that re-attach when the same UUID comes back. Don't merge them into the remaining display's tree on the first event.
- Debounce reconfiguration (roughly 500 ms of quiet), then re-read the screens, then re-layout once. Treat sleep/wake the same way.
- Choose the park corner per display so the sliver can't land on a neighbouring screen.

**Warning signs:**
Windows on the wrong monitor only on some arrangements. Layouts lost after closing the lid. Jitter right after waking.

**Phase to address:** Phase 1 (coordinate conventions and orphaned-tree model), Phase 3 (single display done right), Phase 6 (multi-display), Phase 8 (saved views keyed by display UUID).

**Confidence:** HIGH for the coordinate conventions and debounce need. MEDIUM for the specific issue citations.

---

## Moderate Pitfalls

### Pitfall 15: Conflicting macOS features (Stage Manager, Sequoia edge tiling, click-wallpaper-to-reveal)

**What goes wrong:**
- **Sequoia edge tiling:** the system shows its own preview and snaps windows when they are dragged to an edge. Dragging to the top edge fills the screen. Both effects collide with Pane's drop preview.
- **Stage Manager:** groups windows and reserves a strip. Rectangle needed several releases to account for it (0.57, 0.74, 0.77; #1087).
- **Click wallpaper to reveal desktop (Sonoma+):** sweeps every window aside when the user clicks bare desktop, which collides with "pinch on bare desktop".

These settings live in undocumented `com.apple.WindowManager` keys: `GloballyEnabled` (Stage Manager), `EnableStandardClickToShowDesktop`, and edge-tiling keys believed to be `EnableTilingByEdgeDrag` / `EnableTopTilingByEdgeDrag` (LOW, unverified).

**How to avoid:**
Detect the settings at launch and on `NSWorkspace`/defaults change. Offer a one-click "turn off" that **records the original values** and puts them back on uninstall or when the toggle is turned off. Verify the write took effect by reading it back, and fall back to deep-linking the System Settings pane. Don't `killall WindowManager` without asking.

**Phase:** Phase 3 (detect edge tiling, since it directly conflicts with drag-to-dock), Phase 9 (full "disable conflicting features" UI).
**Confidence:** MEDIUM (feature behaviour well documented; key names LOW).

### Pitfall 16: ⌥-based default hotkeys that block typing on non-US layouts, plus Sequoia hotkey restrictions

**What goes wrong:**
Saved views on ⌥1–9 take over keys that produce essential characters on many layouts. On the German Mac layout, ⌥5/6/7/8/9 type `[ ] | { }`. AeroSpace gets "keys not registering" reports (#732), and Rectangle has "Shortcuts with option stop working" (#1592). macOS 15 blocks Option-only and Option+Shift global hotkeys for **sandboxed** apps (AeroSpace #514 maintainer; Maccy #872). Pane isn't sandboxed, so it's unaffected, but it must stay unsandboxed.

**How to avoid:**
Register hotkeys by key code. Check at first run whether the default chord produces a printable character on the current input source (`UCKeyTranslate`) and offer a different default if it does. Make every binding remappable. Never sandbox.

**Phase:** Phase 4 (first hotkeys), Phase 8 (⌥1–9), Phase 9 (onboarding).
**Confidence:** MEDIUM–HIGH.

### Pitfall 17: AXObserver lifetime and callback crashes

**What goes wrong:**
Use-after-free when an observer or its refcon is released while notifications are still queued. Amethyst #1900: a daily SIGSEGV in `observerCallback → _Block_copy`, still happening on macOS 27. Crashes also come from removing observers on a different thread from the run loop they were added on.

**How to avoid:**
Create, register, remove and destroy each observer on its app's thread, in reverse order of creation (AeroSpace destroys subscriptions → windows → app element in that order). The refcon is a retained box that is invalidated before release, and callbacks check validity first. Fuzz-test by launching and quitting apps rapidly.

**Phase:** Phase 2.
**Confidence:** MEDIUM.

### Pitfall 18: Overlay windows that steal clicks, jump Spaces, or get captured

**What goes wrong:**
Full-screen overlays (stage, drop preview, gap handles, tab strips) eat clicks when they shouldn't (Loop #755: "cursor can't click on sections of the screen"). They vanish over fullscreen apps or follow the user to the wrong Space. They also show up in Pane's own ScreenCaptureKit snapshots and in Pane's own AX window list.

**How to avoid:**
Use `NSPanel` set to non-activating, `ignoresMouseEvents = true` except when interacting, and the right `collectionBehavior` (`.canJoinAllSpaces`, `.fullScreenAuxiliary`, `.stationary`, `.ignoresCycle`). Exclude Pane's own pid from tracking and from SCK content filters.

**Phase:** Phase 3 (drop preview and gap handles), Phase 4 (stage), Phase 7 (tab strip).
**Confidence:** MEDIUM–HIGH.

### Pitfall 19: Tab strip and gap handles that lag behind window moves

**What goes wrong:**
AX moved/resized notifications are coalesced and arrive late, so a tab-strip overlay trails a dragged window. Hiding non-selected tabs runs into the same limit as AeroSpace #66: there's no public "hide one window" API. Minimising animates and goes to the Dock. Moving off-screen leaves a sliver.

**How to avoid:**
While a drag is active, poll the group leader's CG bounds at display refresh rate (cheap, no AX). Hide the strip during fast drags and show it again on settle. Hide non-selected tabs by parking them at full size behind the selected tab's frame, or in the park corner. Never minimise.

**Phase:** Phase 7.
**Confidence:** MEDIUM.

### Pitfall 20: Saved views and persistence that assume window IDs survive restarts

**What goes wrong:**
Window IDs are per-session. When an app relaunches its windows get new IDs, and `AXUIElement`s can't be serialised. Saved views 1–9 "restore" into empty tiles.

**How to avoid:**
Persist window identity as `(bundleID, window title pattern, AXIdentifier if present, last frame, creation order)`, and match on restore with a score threshold. Persist the tree shape even when no window matches, so newly opened windows fill the empty slots.

**Phase:** Phase 1 (Codable identity type), Phase 8.
**Confidence:** MEDIUM.

### Pitfall 21: `pane://` URL commands as an attack surface

**What goes wrong:**
Any web page or app can open a custom URL scheme; browsers ask once and then remember the choice. A malicious page could repeatedly trigger destructive or disruptive commands: close windows, rearrange, toggle the Mission Control takeover.

**How to avoid:**
Only accept non-destructive navigation and layout commands. Validate every parameter. Rate-limit. Never pass URL data to a shell or AppleScript. Require confirmation for anything that closes windows or changes system settings.

**Phase:** Phase 8.
**Confidence:** MEDIUM (general URL-scheme risk applied to this app).

---

## Minor Pitfalls

### Pitfall 22: Window-opening animations and macOS defaults
Chrome and others play opening animations that make the first frame read wrong. AeroSpace suggests `NSAutomaticWindowAnimationsEnabled = false` to users. Pane should wait for the frame to settle after creation rather than recommending global defaults. **Phase 2–3.**

### Pitfall 23: Apps with their own window-management assumptions
Ghostty's quick terminal and iTerm2's hotkey window manage their own frames (AeroSpace #103). CleanShot X has helper windows on other monitors (AeroSpace #221). Zoom.us jumps when given a 1-px offset (AeroSpace #527). Teams, Outlook reminders and PiP windows need special cases. Put all of this in the per-bundle rule table, covered by dump tests (Pitfall 7). **Phase 2–3.**

### Pitfall 24: App menu unreachable when the app's windows are on a non-menu-bar display
AeroSpace #594 ("Application menu is unusable when application is not on the monitor that contains menubar"). This applies to zoom states where the focused window ends up parked or on another display. **Phase 6.**

### Pitfall 25: Notarised but not stapled, or Sparkle feed without HTTPS and EdDSA
Offline first launch fails Gatekeeper, or updates become a supply-chain risk. **Phase 9.**

---

## Technical Debt Patterns

| Shortcut | Immediate Benefit | Long-term Cost | When Acceptable |
|----------|-------------------|----------------|-----------------|
| Synchronous AX calls on the main actor | Simple code, fast prototype | One hung app freezes everything. AeroSpace needed a core rewrite (#131) | Only in a throwaway Phase 2 spike. Never in a merged `AXWindowSystem` |
| Removing windows from the tree on `kAXUIElementDestroyedNotification` alone | Easy lifecycle | Ghost tiles, lost layouts on lock/Spaces/slow apps | Never |
| Trusting requested frame == actual frame | Simpler solver | Overlaps, fight loops, wrong min sizes | Never. Read back from Phase 2 |
| Hard-coding app quirks inline | Fast fixes | Untestable heuristics drift apart | Only if each quirk comes with an AX-dump test case |
| Calling private APIs directly (linked, not `dlsym`) | Less boilerplate | Launch crash on a macOS that drops the symbol | Never. `_AXUIElementGetWindow` (very stable) is the only one that could be weak-linked, and it still needs a nil fallback |
| Ad-hoc or Apple Development signing for public builds | No paid account needed | TCC resets on every build, certificate revocations (AeroSpace #167), Homebrew disabling the cask | Local dev only |
| Long-running `SCStream` for snapshots | Always-fresh thumbnails | Purple "sharing" indicator, WindowServer/replayd memory growth | Only while the camera is moving, if it's ever needed |
| Writing `com.apple.WindowManager` defaults without saving originals | One-line "disable Stage Manager" | Users can't get their settings back after uninstall | Never |

## Integration Gotchas

| Integration | Common Mistake | Correct Approach |
|-------------|----------------|------------------|
| AX frame writes | `position` then `size` | `size → position → size`, cancellable between steps, with `AXEnhancedUserInterface` turned off around the write |
| AX messaging timeout | Default ~6 s system-wide | `AXUIElementSetMessagingTimeout` per app element (~1 s) with backoff. Treat -25204 as "busy", not "dead" |
| `_AXUIElementGetWindow` | Assuming it always returns an ID | Nil while screen locked. IDs are reused after unlock. Cross-check with the CG window list |
| `kAXWindowsAttribute` | Assuming it lists all windows | Current Space only. Use SkyLight/CG enumeration for other Spaces, without AX handles |
| `CGWindowListCopyWindowInfo` | Using `kCGWindowName` for titles | Empty without Screen Recording. Use the AX title |
| CGEventTap | Ignoring `kCGEventTapDisabledByTimeout` | Re-enable in the callback, plus a watchdog timer. No AX inside callbacks |
| Secure Input | Treating dead hotkeys as a Pane bug | Poll `IsSecureEventInputEnabled()` and show an indicator (AeroSpace 0.20) |
| ScreenCaptureKit | Assuming permission is permanent | Monthly re-prompt on 15+. Fail soft to icon snapshots |
| ScreenCaptureKit | Capturing parked, minimised or other-Space windows | Capture before parking. Minimised/other-Space windows fall back to the cached or icon snapshot |
| MultitouchSupport | `void` contact callback, default device only | `int32_t` return, return 0. Enumerate the device list. Re-enumerate on wake and hot-plug |
| `CGSSetSymbolicHotKeyEnabled` | Not restoring on crash | Persist originals. Restore at launch, quit and update |
| Display identity | Keying by `CGDirectDisplayID` | Key by `CGDisplayCreateUUIDFromDisplayID`. Handle null during reconfiguration |
| Sparkle | Relaunching with windows parked | Restore home frames before handing control to the updater |
| `SMAppService` login item | Registering from a translocated path | Require /Applications, then register |

## Performance Traps

| Trap | Symptoms | Prevention | When It Breaks |
|------|----------|------------|----------------|
| Sequential AX across all apps on each refresh | Focus lag, delayed new-window detection | Per-app threads, reactive merge (AeroSpace #1615) | Any one slow app (Godot, IntelliJ), or about 100 windows (AeroSpace #131 maintainer) |
| Resizing every window on camera settle | Multi-second flicker, CPU spikes, terminal re-wrap | Resize only changed, visible targets. Move rather than shrink off-view windows | About 10–15 windows, Electron-heavy setups |
| Snapshot churn | WindowServer/replayd in GBs over hours | Capture at display size, budget captures per second, LRU cache, one-shot API | Hours of uptime with 25+ windows (AltTab #4255) |
| Wide event-tap masks (mouseMoved/scroll) | System-wide scroll or cursor lag | Narrow masks, listen-only where possible | After running for a while (Loop #626) |
| Hit-testing (`AXUIElementCopyElementAtPosition`) on every mouse-down | Tap disabled by timeout, click lag | Detect drags from frame deltas, async hit-tests only | Any unresponsive app under the cursor |
| Unthrottled reconcile on notification storms | CPU burns during app launch or display change | Debounce (about 50–100 ms for AX, about 500 ms for displays) | App launches that open many windows, docking/undocking |

## Security Mistakes

| Mistake | Risk | Prevention |
|---------|------|------------|
| Destructive `pane://` commands with no confirmation | Web pages or other apps closing or rearranging user windows | Allow-list of non-destructive commands, parameter validation, rate limits, confirmation for destructive actions |
| Passing URL or config data to shell, AppleScript or `exec` | Code execution with an Accessibility-privileged process | Never. Pane has no "run command" feature in v1 |
| Mis-typed `dlsym` function pointers | Memory corruption in a process with AX rights | Prototypes checked against several header lineages. Unit-call them behind canaries |
| Sparkle feed without HTTPS + EdDSA, or a lost key | Malicious update, or stranded users | HTTPS appcast, EdDSA signatures, offline key backups |
| Logging window titles verbosely | Leaking document names and private info in bug reports | Redact titles in logs by default. Opt-in verbose mode |
| Sandboxing "for safety" | Breaks AX entirely, and the macOS 15 ⌥-hotkey restriction applies | Ship unsandboxed with hardened runtime (as AeroSpace does) |

## UX Pitfalls

| Pitfall | User Impact | Better Approach |
|---------|-------------|-----------------|
| Windows stranded tiny or off-screen after a crash | "Pane ate my windows". Uninstalls | Restore at launch, a "Restore all windows" menu item, `pane://restore` |
| Silent hotkey failure under Secure Input | Bug reports, distrust | Visible indicator while Secure Input is on |
| Stale Accessibility grant after an update | Endless prompts | Probe-based detection with a guided `tccutil reset` |
| ⌥-digit defaults on non-US layouts | Can't type brackets | Layout-aware default chords, fully remappable |
| Screen Recording forced at onboarding, then the monthly nag | Users decline and see a broken zoom | Make it optional. Design the icon/colour fallback first |
| Fighting app minimum sizes silently | Overlapping "non-overlapping" tiles | Show a "minimum size reached" hint (Rectangle does this) and re-solve siblings |
| Taking over Mission Control with no clear exit | Users lose a system feature | Opt-in, one-click restore, restore on crash |
| Disabling Stage Manager or edge tiling without recording originals | Settings lost after uninstall | Record and restore. Be clear about what was changed |
| Tiling dialogs and popups | Layout jumps on every context menu | Classifier with a settle delay, default float list |

## "Looks Done But Isn't" Checklist

- [ ] **Window tracking:** often missing lock/unlock handling. Lock the screen with 10 windows tiled, unlock, and check that the tree is unchanged.
- [ ] **Window tracking:** often missing hung-app isolation. Run `kill -STOP <pid>` on one app and check that tiling other apps still works within 1 s.
- [ ] **Window tracking:** often missing ghost GC. Close 5 windows in under a second and check that no empty tiles remain after the next reconcile.
- [ ] **Tiling:** often missing minimum-size handling. Tile System Settings and a 600-pt-minimum app into narrow slots, and check there's no overlap and no CPU loop.
- [ ] **Tiling:** often missing native tabs. Open 3 Finder or Terminal tabs and check they become one tile.
- [ ] **Tiling:** often missing fullscreen exit. Fullscreen a tiled window, exit, and check it returns to its tile at the right size.
- [ ] **Drag-to-dock:** often missing Electron/Chrome custom title bars. Drag VS Code, Slack and Chrome by their tab strips.
- [ ] **Drag-to-dock:** often missing the Sequoia edge-tiling conflict. With system edge tiling on, check there's only one preview and the user gets a prompt.
- [ ] **Zoom:** often missing crash recovery. `kill -9` Pane while zoomed out, relaunch, and check all windows return to their home frames.
- [ ] **Zoom:** often missing the no-permission path. Revoke Screen Recording in the middle of a session and check icon snapshots appear without an alert loop.
- [ ] **Zoom:** often missing a soak test. Run 8 hours with 30 windows and check WindowServer RSS growth stays under the agreed limit.
- [ ] **Event taps:** often missing timeout recovery. Add an artificial 2 s stall in the callback and check the tap re-enables.
- [ ] **Gestures:** often missing system-gesture coexistence on macOS 27. While streaming touches, check that 3-finger swipe between Spaces still works.
- [ ] **Gestures:** often missing sleep/hot-plug. Sleep, wake, reconnect the Magic Trackpad, and check pinch still works.
- [ ] **Mission Control takeover:** often missing crash restore. Enable takeover, `kill -9`, and check F3 works again after relaunch, or at least after logout.
- [ ] **Multi-display:** often missing negative coordinates. Put the secondary display above and left of the primary and check tiling and drop targets.
- [ ] **Multi-display:** often missing unplug/replug. Unplug the external display, replug it, and check its tree is restored by UUID.
- [ ] **Saved views:** often missing cross-restart matching. Quit all apps, relaunch them, recall view 1, and check windows are matched.
- [ ] **Updates:** often missing TCC persistence. Update via Sparkle from N to N+1 and check no permission prompt appears.
- [ ] **Updates:** often missing parked-window restore before relaunch. Update while zoomed out and check windows are restored.

## Recovery Strategies

| Pitfall | Recovery Cost | Recovery Steps |
|---------|---------------|----------------|
| Synchronous AX architecture shipped | HIGH | Put per-app executors behind the existing `WindowSystem` protocol. That only works if the protocol was async from the start, which is why it goes in Phase 2 |
| Layout destroyed by false "closed" | MEDIUM | Add lifecycle states and the reserved-slot model. Restore from the last persisted tree snapshot |
| Stranded windows in the field | LOW (if home frames are persisted) / HIGH (if not) | Ship a hotfix that restores at launch. Publish a recovery AppleScript and `pane://restore` |
| Private API broke on a new macOS | LOW–MEDIUM | Capability flag off by default for that OS build, plus a point release. Users keep tiling |
| TCC reset by a signing change | MEDIUM | Can't undo. Ship a guided re-grant screen and release notes. Fix the designated-requirement check in CI |
| Mission Control hotkeys left disabled | LOW | Restore at next launch. Document `killall Dock` / logout |
| WindowServer memory growth | MEDIUM | Lower the capture budget, reduce capture resolution, offer a "low-memory snapshots" setting |

## Pitfall-to-Phase Mapping

| Pitfall | Prevention Phase | Verification |
|---------|------------------|--------------|
| 1 AX blocking / per-app threads | Phase 2 | `kill -STOP` test: other apps still tile within 1 s |
| 2 False "closed" / ghost windows | Phase 1 (states) + Phase 2 (reconcile) + Phase 6 (Spaces) | Lock/unlock, rapid-close and Space-switch tests keep the tree intact |
| 3 Stranded parked windows | Phase 3 (home frames) + Phase 4 (parking) + Phase 9 (Sparkle) | `kill -9` and update-while-zoomed tests |
| 4 Private API breakage | Phase 2 (pattern) + Phases 5–6 (canaries, fallbacks) + Phase 9 (beta checklist) | Each private API can be turned off with a flag, and the app still tiles |
| 5 Event-tap timeouts / lag | Phase 3 (tap wrapper) + Phases 5–6 | Artificial-stall test; no AX symbols in tap callbacks (code review) |
| 6 Frame fights / min sizes | Phase 1 (solver) + Phase 2 (read-back) | Min-size and iTerm2 increment tests, no CPU loop |
| 7 Window classification | Phase 2 (classifier + AX-dump corpus) + Phase 7 (native tabs) | Dump-corpus unit tests pass. Context menus never tile |
| 8 Fullscreen / Spaces | Phase 1 + Phase 2 + Phase 6 | Fullscreen round-trip; both "separate Spaces" modes tested |
| 9 Resize storms / capture cost | Phase 4 | Settle under 500 ms at 15 windows; 8 h soak memory limit |
| 10 Screen Recording / stale TCC | Phase 2 + Phase 4 + Phase 9 | Revoke-in-session test; stale-grant probe test |
| 11 Signing / TCC identity | Phase 2 (bundle ID) + Phase 9 (Developer ID) | CI designated-requirement check; N→N+1 update with no prompt |
| 12 Mission Control takeover | Phase 6 + Phase 3 (top-edge zone) | Crash-restore test; no cursor warping |
| 13 Gesture conflicts | Phase 5 | Content doesn't zoom under ⌥-pinch; system swipes still work on 27 |
| 14 Multi-display | Phase 1 + Phase 3 + Phase 6 + Phase 8 | Negative-coordinate and unplug/replug tests |
| 15 Conflicting macOS features | Phase 3 (detect) + Phase 9 (disable/restore UI) | Originals restored after toggle-off |
| 16 Hotkey layout conflicts | Phase 4 + Phase 8 + Phase 9 | German-layout test: `[ ] { }` still typeable |
| 17 AXObserver lifetime | Phase 2 | Rapid launch/quit fuzz for 30 min, no crash |
| 18 Overlay behaviour | Phases 3, 4, 7 | Click-through test; overlays absent from own captures |
| 19 Tab strip lag / hiding | Phase 7 | Strip follows a dragged window within 1 frame at settle |
| 20 Persistence identity | Phase 1 + Phase 8 | Cross-restart restore test |
| 21 URL scheme abuse | Phase 8 | Destructive commands rejected without confirmation |

## Sources

Primary sources: GitHub issues and code, read with `gh` on 2026-10-23. Maintainer comments quoted where noted.
- AeroSpace: [#131 freeze/AX threading](https://github.com/nikitabobko/AeroSpace/issues/131), [#445 ghost windows](https://github.com/nikitabobko/AeroSpace/issues/445), [#1615 blocked detection](https://github.com/nikitabobko/AeroSpace/issues/1615), [#1216 windows jump](https://github.com/nikitabobko/AeroSpace/issues/1216), [#771 unlock crash / ID reuse](https://github.com/nikitabobko/AeroSpace/issues/771), [#68 native tabs](https://github.com/nikitabobko/AeroSpace/issues/68), [#66 can't truly hide windows](https://github.com/nikitabobko/AeroSpace/issues/66), [#101 multi-monitor focus bug and crash-canary idea](https://github.com/nikitabobko/AeroSpace/issues/101), [#514 Sequoia (⌥ hotkeys, sandbox)](https://github.com/nikitabobko/AeroSpace/issues/514), [#1486 Secure Input indicator](https://github.com/nikitabobko/AeroSpace/issues/1486), [#167 certificate revoked](https://github.com/nikitabobko/AeroSpace/issues/167); source files `Sources/AppBundle/tree/MacApp.swift` (per-app threads, size→position→size, AXEnhancedUserInterface), `Sources/AppBundle/model/AxUiElementWindowType.swift` and `axDumps/` (classifier + dump corpus); [Guide](https://nikitabobko.github.io/AeroSpace/guide), [Goodies](https://nikitabobko.github.io/AeroSpace/goodies)
- yabai: [#2240 macOS 14.5 Space move protected](https://github.com/asmvik/yabai/issues/2240), [#2500 Sequoia SIP-less move broken](https://github.com/asmvik/yabai/issues/2500), [#2634 Tahoe SA](https://github.com/asmvik/yabai/issues/2634), [#2822 macOS 27 Space switching](https://github.com/asmvik/yabai/issues/2822), [#2688 macOS 26.1 TCC UI](https://github.com/asmvik/yabai/issues/2688), [#68 native tabs](https://github.com/asmvik/yabai/issues/68), [#36 fullscreen exit](https://github.com/asmvik/yabai/issues/36), [#148 animations](https://github.com/asmvik/yabai/issues/148)
- Amethyst: [#1900 observerCallback crash on macOS 27](https://github.com/ianyh/Amethyst/issues/1900), [#1856 repeated AX prompts on Tahoe](https://github.com/ianyh/Amethyst/issues/1856), [#1896 ghost half-screen](https://github.com/ianyh/Amethyst/issues/1896), [#1350 Arc phantom windows](https://github.com/ianyh/Amethyst/issues/1350), [#1167 windows moved after wake](https://github.com/ianyh/Amethyst/issues/1167), [Discussion #1682 space-throwing deprecation](https://github.com/ianyh/Amethyst/discussions/1682)
- Rectangle: [README "Common Known Issues"/Troubleshooting](https://github.com/rxhanson/Rectangle), [#912 AXEnhancedUserInterface/Chrome](https://github.com/rxhanson/Rectangle/issues/912), [#1087 Stage Manager](https://github.com/rxhanson/Rectangle/issues/1087), [#1685 Terminal tab fullscreen](https://github.com/rxhanson/Rectangle/issues/1685), [#1922 Dock autohide](https://github.com/rxhanson/Rectangle/issues/1922)
- Loop: [#626 system-wide scroll lag](https://github.com/MrKai77/Loop/issues/626), [#745 WindowServer memory](https://github.com/MrKai77/Loop/issues/745), [#418 AX permission after update](https://github.com/MrKai77/Loop/issues/418), [#1159 cursor warp / Mission Control](https://github.com/MrKai77/Loop/issues/1159), [#724 Electron title bar](https://github.com/MrKai77/Loop/issues/724), [#755 overlay blocks clicks](https://github.com/MrKai77/Loop/issues/755)
- AltTab: [#447 other-Space windows invisible to AX](https://github.com/lwouis/alt-tab-macos/issues/447), [#4255 WindowServer memory](https://github.com/lwouis/alt-tab-macos/issues/4255), [#4194 replayd memory](https://github.com/lwouis/alt-tab-macos/issues/4194), [#2606 sharing indicator](https://github.com/lwouis/alt-tab-macos/issues/2606)
- OpenMultitouchSupport: [#13 macOS 27 callback return value](https://github.com/Kyome22/OpenMultitouchSupport/issues/13), [#2 crash after sleep](https://github.com/Kyome22/OpenMultitouchSupport/issues/2), [#6 non-default device](https://github.com/Kyome22/OpenMultitouchSupport/issues/6)

Secondary sources (web, LOW–MEDIUM):
- Sequoia Screen Recording prompts: [9to5Mac monthly](https://9to5mac.com/2024/08/14/macos-sequoia-screen-recording-prompt-monthly/), [9to5Mac Oct 2024](https://9to5mac.com/2024/10/07/macos-sequoia-screen-recording-popups/), [TidBITS](https://tidbits.com/2024/08/19/apple-reduces-excessive-sequoia-permission-requests-shifts-to-monthly), [TechRadar](https://www.techradar.com/computing/mac-os/on-macos-sequoia-youll-only-have-to-deal-with-screen-recording-permission-pop-ups-once-a-month-rather-than-once-a-week), [heise 15.1](https://heise.de/-9973354)
- Event tap timeout: [Cocoa-dev 2010](https://lists.apple.com/archives/Cocoa-dev/2010/Sep/msg00890.html), [SDL commit](https://git.axiodl.com/encounter/SDL/commit/51ccc9ed8cab7bf1e3ea293328f2e382eceaf273)
- Display identity: [Apple CGDirectDisplayID docs](https://developer.apple.com/documentation/coregraphics/cgdirectdisplayid), [Zed screen.rs](https://git.secluded.site/zed/blob/v0.101.1/crates/gpui/src/platform/mac/screen.rs?raw=1)
- TCC/signing: [OpenClaw macOS permissions doc](https://docs.openclaw.ai/platforms/mac/permissions)
- Homebrew Gatekeeper policy: [TomatoBar #102](https://github.com/ivoronin/TomatoBar/issues/102), [Workbrew on Homebrew 5.0](https://workbrew.com/blog/homebrew-5-0-0)
- Stage Manager defaults keys: [Hexnode script](https://www.hexnode.com/mobile-device-management/help/script-to-enable-disable-stage-manager-on-mac/)
- Sequoia edge tiling: [Michael Tsai](https://mjtsai.com/blog/2024/06/11/window-tiling-and-snapping-in-sequoia), [AppleInsider](https://appleinsider.com/articles/24/06/11/tiled-window-management-comes-to-macos-sequoia-but-its-hidden)

Clean-room note: no TrellisWM binary, strings or code were used. Only public MIT-licensed prior art and public discussion. AeroSpace source was read to learn approaches, not to copy.

---
*Pitfalls research for: macOS zoomable nested-tiling window manager (Pane)*
*Researched: 2026-10-23*

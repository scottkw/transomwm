# Phase 6 Spike: Spaces, Mission Control Takeover and Space Switching (06-01)

**Run:** 2026-10-31, Tart VM `pane-test` through `scripts/vm-spike.sh` with `SPIKE_PRODUCT=transom-spaces-spike`, one run at a time under `.build/transom-vm.lock`. No agent ran any spike subcommand on the host. `swipe-check` is left for the user (below).
**Harness:** `transom-spaces-spike` (Debug build, `Sources/transom-spaces-spike/main.swift`). Spaces are read through the product path `SkyLightSpaces.managedDisplaySpaces()` → `SpacesProvider.snapshot()` → `SpacesSnapshot.parse`; hotkeys through `TransomPrivate/SymbolicHotKeys.swift`, Mission Control through `TransomPrivate/CoreDock.swift`. `hotkeys`, `takeover-crash`, `switch` and `ghost` refuse to run unless `kern.hv_vmm_present` is 1.
**Raw data:** JSON lines in `out.jsonl` under each `.build/spike/spaces-*` directory named below (git-ignored, host only).

## Environment

| Item | Value |
|---|---|
| Host | macOS 27.2 (26B123), Xcode 27.1 / Swift 6.4. Built here, nothing run here |
| Guest | macOS 15.7.7 (24G720), 1 display `2CF16D4B-4447-496C-9769-FC71618690D3`, separate Spaces on (`SLSGetSpaceManagementMode` 1, `screensHaveSeparateSpaces` true with NSApplication) |
| Guest Spaces | Two desktops: **IDs 1 and 3** (the plan said 1 and 41; the VM has 1 and 3 today). Desktop 1's uuid is **empty** (`""`) |
| Guest permissions | `sshd-keygen-wrapper` holds Accessibility; posting events and AX worked |
| macOS 14 | Not covered (RESEARCH Open Question 4: VM 15.7.7 + host 27.2 accepted as evidence) |

## Results at a glance

| Question | Answer | Evidence |
|---|---|---|
| F2 symbols on 15.7.7 | **25 of 25 resolve** (23 SkyLight, 2 HIServices) | spaces-dump |
| A5 empty uuid | **Real on 15.7.7**: Desktop 1 has `uuid = ""`; the parser keys it `default:2CF16D4B-…`. `Main` not seen (separate Spaces mode) | spaces-dump |
| A1 F3 = hotkey 108 | **Yes**: posted key code 160 + fn opens Mission Control with 108 enabled, not with it disabled | hotkeys |
| Takeover ID set | **32, 108 and 113** (113 = ⇧F3 still opens Mission Control with 32/108 off); 34 (⌃⇧↑) does not | hotkeys |
| A2 abort persistence | **The disabled state outlives `abort()`**, and the Dock honours it (F3 does nothing) until restored | takeover-crash |
| A3 CoreDock | **Opens Mission Control with 32/108 disabled; a second send closes it** | hotkeys |
| Carbon on freed chords | **Both fire** (⌃↑ and key code 160) after the disable | hotkeys |
| A4 switch method | **Posted ⌃→/⌃← switch Spaces in ~555-660 ms, but only with the fn flag (0x800000) set**; without it nothing happens | switch |
| AX after switch | Fixture window on the other Space: **not AX-listed before the switch, listed after**; focus 3 ms | switch |
| A7 G-03-9 ghost | Closed Safari window's element answers **invalidElement (-25202)**; the lingering CG entry was **not reproduced** (gone within 1 s, 2 runs) | ghost |
| Hidden windows' Spaces | Minimised: **[3]**; ⌘H-hidden app: **[3]**; hidden native tab: **[]** (empty) | ghost |
| A8 reboot | **UUIDs and numeric IDs both unchanged** across `tart stop`/`tart run` (1 and 3); current Space resets to Desktop 1 | reboot diff |
| Swipe (D-05) | **skip → kept**: the user skipped the host check; the four-finger swipe stays with macOS ([swipe kept]) | below |
| Schema decision | **schema-2** (user, 2026-10-31) | below |

## spaces-dump

Directory `.build/spike/spaces-spaces-dump-20261031-104613` (Task 1 tracer). Symbol table: every F2 name `true` (`SLSMainConnectionID` … `SLPSPostEventRecordTo`, `CGS*`/`SLS*` symbolic-hotkey getters and setters, `_SLPSSetFrontProcessWithOptions`, and in HIServices `CoreDockSendNotification`, `_AXUIElementGetWindow`).

Raw `SLSCopyManagedDisplaySpaces` (one display):

```
[{"Current Space": {"id64": 1, "ManagedSpaceID": 1, "type": 0, "uuid": ""},
  "Display Identifier": "2CF16D4B-4447-496C-9769-FC71618690D3",
  "Spaces": [{"id64": 1, "ManagedSpaceID": 1, "type": 0, "uuid": ""},
             {"id64": 3, "ManagedSpaceID": 3, "type": 0, "uuid": "7AE365C9-B9C4-437C-847F-FBF914CF11A6"}]}]
```

Parsed: display `2CF16D4B-…`, current 1; Space 1 desktop #1 `default:2CF16D4B-4447-496C-9769-FC71618690D3`; Space 3 desktop #2 `7AE365C9-…`; skipped 0. `managementMode` 1 agrees with `screensHaveSeparateSpaces` true. No Space carried its own `Display Identifier` here. A type-4 full-screen dictionary was not captured (the `fullscreen.json` fixture stays synthetic).

## hotkeys

Directory `.build/spike/spaces-hotkeys-20261031-105911` (`--seconds 90`). 228 IDs in 0..<400 have a value. Values on 15.7.7:

| ID | Enabled | vk | NX flags | Meaning |
|---|---|---|---|---|
| 32 | yes | 126 | 0x840000 | ⌃↑ Mission Control |
| 33 | yes | 125 | 0x840000 | ⌃↓ Application windows (never touched) |
| 34 | yes | 126 | 0x860000 | ⌃⇧↑ |
| 79 / 81 | yes | 123 / 124 | 0x840000 | ⌃← / ⌃→ move a Space (host 27.2 has 0x940000) |
| 108 | yes | 160 | 0x800000 | Mission Control key (F3) |
| 113 | yes | 160 | 0x820000 | ⇧F3 |
| 118-120 | no | 18-20 | 0x40000 | ⌃1-⌃3 Switch to Desktop n (off by default) |

Posted chords (Dock on-screen window count 2 → 4 means Mission Control opened; closed again with Escape):

| Step | Chord | No fn flag | With fn flag (0x800000) |
|---|---|---|---|
| baseline (all enabled) | 108: vk 160 | not opened | **opened** |
| baseline | 32: ⌃↑ | not opened | **opened** |
| 32 + 108 disabled (read back false, false) | 108: vk 160 | not opened | not opened |
| 32 + 108 disabled | 32: ⌃↑ | not opened | not opened |
| variant, 32 + 108 disabled | 34: ⌃⇧↑ | not opened | not opened |
| variant, 32 + 108 disabled | 113: ⇧ vk 160 | not opened | **opened** |

Carbon (`KeyboardShortcuts.events(for: Shortcut)`) with 32/108 disabled: ⌃↑ (carbon 126 / controlKey 4096) **fired**; key code 160 (no modifiers) **fired**. The harness posted without, then with, the fn flag and did not record which post fired.

Summary line (last line): `restored` 32 and 108 `original true, readBack true, setOK true`; `final` 32 and 108 enabled.

### Takeover ID set

**32 and 108 always, plus 113.** With only 32/108 disabled, posted ⇧F3 (113) still opened Mission Control, so it is an independent hotkey and 06-10 must take it too (Carbon chord: key code 160 + shiftKey). 34 (⌃⇧↑) did not open Mission Control with 32 disabled, so it is not taken. 33, 35, 79-82, 115 and 117 are never touched (D-08). 109-112 and 114-117 were not posted (outside the plan's 34/113 question).

### CoreDock

`CoreDockSendNotification("com.apple.expose.awake", 0)` with 32/108 disabled: **Mission Control opened** (Dock windows 2 → 4) and **a second send closed it** (→ 2). A3 holds on 15.7.7: the takeover's fallback works while the keys are taken.

## takeover-crash

Directory `.build/spike/spaces-takeover-crash-20261031-105937` (`originals.json` beside `out.jsonl`). The parent stored `{"32": true, "108": true}`, the child disabled both and called `abort()` (ended by signal 6).

### Abort persistence

| Reading | 32 | 108 |
|---|---|---|
| Immediately after the child died | disabled | disabled |
| One second later | disabled | disabled |
| Posted F3 (with and without fn) while left disabled | — | Mission Control **not opened** |
| After restore from `originals.json` | enabled | enabled |
| Posted F3 + fn after restore | — | Mission Control **opened** |

A2 confirmed: the WindowServer flag outlives the process that set it, and the Dock honours it live. The launch-time restore from stored originals (06-10) is required, not defensive.

## switch

Directory `.build/spike/spaces-switch-20261031-110019` (`--seconds 90`). Latency is from posting the chord (`CGEventSource(.hidSystemState)`, `.cghidEventTap`, explicit flags) to `NSWorkspace.activeSpaceDidChangeNotification`.

### Switch method

| Chord | Flags 0x40000 (⌃ only) | Flags 0x840000 (⌃ + fn) |
|---|---|---|
| ⌃→ (1 → 3) | no change in 2 s | **577 ms** |
| ⌃← (3 → 1) | no change in 2 s | **566 ms** |
| further ⌃→/⌃← (4 runs) | no change in 2 s, every time | 542-658 ms |

- **The fn flag is required.** RESEARCH Pattern 3 / Code Examples say to post without the 0x800000 bit; on 15.7.7 that switches nothing. 06-07 must post the hotkey's own NX flags including 0x800000 (the value the getter returns for 79/81). Same for posted ⌃↑/F3 above.
- AX after switch: TransomFixtureApp window 102 on Space 3 was **not** in the app's `AXWindows` while Desktop 1 showed, and **was** listed after the switch; focusing it (AXMain + AXRaise + activate) made the app frontmost in **3 ms** (the fixture may already have been frontmost; indicative only).
- Activation-only (fixture's only window on Desktop 2, activating the app from Desktop 1): the Space changed after **409 ms with `AppleSpacesSwitchOnActivate` = 0** and **398 ms with 1**. The guest's original value was absent and was restored to absent. For an app whose only window is on another Space, activation switches regardless of the setting.
- Multi-display behaviour of a posted chord (A4 second half, Pitfall 11) is not observable with one display: user hardware checklist item 7. The SLPS front-process route was not built.
- Harness bug found and fixed during the run: the end-of-run "back to the first desktop" cleanup posted ⌃← without fn, so it did nothing and the guest stayed on Desktop 2 until the reboot below reset it.

## ghost

Directories `.build/spike/spaces-ghost-20261031-110134` and `.build/spike/spaces-ghost-20261031-110259` (the second adds an 8 s dwell before the close and fixes the fixture window read). Safari was not running; the spike launched it and quit it at the end. A window was opened through File ▸ New Window (AX press) and closed with its close button (AX press).

### G-03-9 ghost

| Run | Window | AX answer, every second for 30 s | CG optionAll | SkyLight Spaces |
|---|---|---|---|---|
| 1 (closed at once) | 151 | invalidElement × 30 | present at +0 s (layer 0, off-screen), gone from +1 s | [] |
| 2 (open 8 s first) | 167 | invalidElement × 30 | present at +0 s (layer 0, off-screen), gone from +1 s | [] |

- The cached element answers **invalidElement (-25202)**, A7's expectation. The UAT ghost (CG entry lingering for minutes) **did not reproduce** in two runs: the entry left within a second. So the close landed on CloseRule's `(.alive, .invalidElement, false) → .closed` row. If the ghost reappears with its CG entry kept, it is the `(.alive, .invalidElement, true)` row (`.recheck`, or `.state(.absent)` for a tab member): 06-02's narrow fix applies there, with an empty Space set as the separating fact.
- Hidden windows' Space sets (fixture: `standard`, `standard`, `tabs:2` = windows 153, 154, 155, 156 on Space 3):

| Window | Shown | Window 153 minimised | App hidden (⌘H) |
|---|---|---|---|
| 153 | [3] | **[3]** (CG layer 0, off-screen) | [3] |
| 154 | [3] | — | [3] |
| 155 (selected tab) | [3] | — | [3] |
| 156 (hidden tab) | **[]** | — | **[]** |

Minimised and ⌘H-hidden windows keep their Space; only the hidden native tab reports an empty set (as 02-14 found). An "empty Space set" ghost rule must keep the tab-member guard (Pitfall 10).

## Reboot diff

Before: `.build/spike/spaces-spaces-dump-20261031-110322` (label `before-reboot`). `tart stop pane-test`, `tart run --no-graphics pane-test` in the background, SSH and Dock back after ~45 s. After: `.build/spike/spaces-spaces-dump-20261031-110536` (label `after-reboot`).

| | Space IDs | UUIDs | Current |
|---|---|---|---|
| Before | 1, 3 | `""`, `7AE365C9-B9C4-437C-847F-FBF914CF11A6` | 3 |
| After | 1, 3 | `""`, `7AE365C9-B9C4-437C-847F-FBF914CF11A6` | 1 |

A8: on 15.7.7 with two Spaces, both UUIDs **and** numeric IDs survived the reboot (one sample; the UUID side table stays the correctness mechanism). The empty Desktop 1 uuid also persisted, so `default:<displayUUID>` is a stable key. The current Space reset to Desktop 1.

## Swipe check (user, host)

Optional (D-05). Quit Transom first, give your terminal Accessibility, run this on your Mac (30 s), swipe with four fingers as prompted, then remove the terminal's Accessibility grant:

```
swift build --product transom-spaces-spike && .build/debug/transom-spaces-spike swipe-check --i-am-on-the-host --seconds 30
```

Phase 1 (10 s) listens to Dock-control events (type 30) while you swipe up, left and right. Phase 2 (about 17 s) runs only if one field separates swipe-up from horizontal swipes, and then consumes only swipe-up events while you swipe up, left, right, up. The tap goes away when the command ends. Reply with the printed `out.jsonl` path and whether swipe-up did nothing while left/right still switched Spaces, or "skip".

**Verdict:** skip → kept. The user replied "skip" on 2026-10-31; swipe-check was not run. UI copy uses the [swipe kept] variant, and 06-11 does not create `SwipeTakeoverTap.swift`.

## Schema decision

**Decision:** schema-2

The user chose it on 2026-10-31: bump layout.json to schema 2. Schema-1 files migrate in memory on first load and are saved as 2; a downgraded (schema-1) Transom then refuses to overwrite the file (T-03-18), so layout sets and the Space-UUID table are never silently dropped. Plan 06-03 implements it.

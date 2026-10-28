# Phase 4 Spike: Zoom Camera Feasibility (04-01)

**Run:** 2026-10-27/28, Tart VM `pane-test` only, through `scripts/vm-spike.sh`. Nothing ran live on the host.
**Harness:** `transom-zoom-spike` (Debug build) on the product's own write path (`AXWindowSystem.perform` → `AXAppThread` → `FrameWriter`, `frameApplied` read-backs), the product's `SnapshotCapture.swift` and `StagePanel.swift`.
**Raw data:** JSON lines in `out.jsonl` under each `.build/spike/` directory named below (git-ignored, host only). Recordings and stills were deleted from the guest after copying.

## Environment

| Item | Value |
|---|---|
| Guest | macOS 15.7.7 (24G720), Apple M3 (Virtual), 4 CPUs, 8 GB RAM, paravirtualized GPU |
| Display | 1 display, 1024 x 768 pt at 2x, 60 Hz (`maximumFramesPerSecond` 60) |
| Host | macOS 27.0.1, Xcode 27.1 / Swift 6.4 (build only) |
| Apps | VS Code 1.143.1 (Electron; installed for this spike, `spctl`: "accepted, source=Notarized Developer ID, origin=Developer ID Application: Microsoft Corporation (UBF8T346G9)"), Safari 18.6, Terminal 2.14, TextEdit 1.20, TransomFixtureApp |
| Permissions | `sshd-keygen-wrapper` holds Accessibility and Screen Recording; `SnapshotCapture.isGranted()` was true in every run |
| G1 window set | 15 windows: 8 TransomFixtureApp, 2 VS Code, 2 Safari, 2 Terminal (`less` on long lines), 1 TextEdit |

**Layouts.** Home is a 4 x 4 grid of the 15 windows in the visibleFrame. The view gives VS Code, Terminal and Safari (one window each) a third of the visibleFrame each, and parks the other 12 with `DisplayInfo.parkedFrame` (bottom-right visibleFrame corner, A8). "in" means home → view and "out" means view → home. Every batch writes all 15 windows in one `perform`, parks first.

**G1 definition (RESEARCH, flagged ZOOM-07 probe).** From just before `perform` to the last `frameApplied` of the batch. It excludes the 120 ms capture budget and the 250 ms animation. End to end from a keypress in the VM, the worst move is about 120 + 250 + 280 + 50 + 120 (fade) ≈ 820 ms.

## Results at a glance

| Gate | Result | Headline |
|---|---|---|
| G1 settle | **PASS** | p95 205.1 ms in, 93.1 ms out (15 windows, Electron included); max 280.3 ms |
| G2 no stale flash | **PASS** | 0 geometric mismatches and 0 unstranded parks in 40 moves; 10 recorded reveals show every window in place, none blank |
| G3 soak | **PASS** | WindowServer +7.5 MB over 60 min (`top` MEM, 389–402 MB); replayd +1.6 MB (11–13 MB), well under the 200 MB flag |
| G4 CA layers | **FAIL on a strict per-run reading (VM, indicative)** | Animated move: 20/20 runs at ≥ 100% of expected frames, max gap 20.6 ms. Crossfade: 58/60 runs pass; 2 runs stalled (172 ms, 51.8 ms) |
| G5 level vs menus | Reported | Open menu (layer 101), menu bar, Dock and the re-ordered toast all above the stage (layer 3) |
| G6 terminal re-wrap | Reported | The Terminal in the view re-wraps 33 → 45 → 33 columns |
| G7 represented state | Reported (refused size only) | A 900x700 minimum in a 341x345 tile reads back 900x700 in 8.7 ms; the collapsed-block UX is not built yet: no observation |
| G8 capture costs | Reported | SCShareableContent fetch 52–64 ms; one capture 20–30 ms (p50); 6.3 of 15 captured within the 120 ms budget on average; a parked VS Code window captures whole |

No mitigation ladder step was applied: G1 passed without one, and `Sources/TransomMac/AX` is unchanged.

## G1: settle latency

Final run: `.build/spike/settle-20261028-000855` (`settle --stage --runs 20 --fixtures 8 --apps vscode,safari,terminal,textedit --record 10`), 20 runs each way, 15 windows, 0 missing read-backs.

| Direction | n | p50 | p95 | max | Pass (p95 ≤ 500 ms) |
|---|---|---|---|---|---|
| in (home → view) | 20 | 64.8 ms | 205.1 ms | 280.3 ms | PASS |
| out (view → home) | 20 | 58.0 ms | 93.1 ms | 110.3 ms | PASS |

Per bundle (the slowest window of that bundle in each batch):

| Bundle | in p50 / p95 / max (ms) | out p50 / p95 / max (ms) |
|---|---|---|
| com.microsoft.VSCode (Electron) | 64.8 / 145.4 / 280.3 | 55.0 / 78.0 / 105.5 |
| com.apple.Safari | 57.9 / 186.0 / 200.3 | 36.6 / 79.8 / 81.4 |
| com.apple.Terminal | 15.3 / 48.9 / 60.6 | 11.2 / 29.2 / 66.9 |
| com.apple.TextEdit | 6.7 / 16.0 / 34.2 | 6.4 / 12.7 / 15.3 |
| TransomFixtureApp (8 windows, one app thread) | 18.7 / 204.6 / 205.1 | 21.0 / 93.1 / 110.3 |

Supporting runs: `settle-20261028-000349` (14 windows, TextEdit missing because it re-opened an already-open document: in p95 149.5 ms, out p95 108.8 ms); `settle-20261027-235234` (15-window smoke, 1 run: in 260.3 ms, out 57.3 ms); `settle-20261027-231616` (tracer, 4 fixture windows: 5.5–12.2 ms).

## G2: no stale flash

**Geometric half (same final run).** At reveal start (every write returned + 50 ms, cap 1500 ms) each written window's CG bounds were compared with its read-back (≤ 2 pt) and each parked window was checked with `Recovery.isStranded`: **0 mismatches, 0 unstranded parks in 40 moves.** The supporting 14-window run had 1 mismatch in 40 moves (run 0, out; which window was not logged then, so the harness now logs per-window detail; the final run had none).

**Visual half.** `screencapture -v` recorded the first 10 reveals in the guest (`g2-1.mov` … `g2-10.mov`). A capturable marker panel turns from red to green at reveal start. The harness decoded each recording at 60 fps in the guest and wrote the frame before the change plus frames 1, 4, 8 … 24 after it (`g2-N-r1-*.png`). Reveal start was found in all 10 recordings.
- Every `after4` frame (about 67 ms after reveal start) for recordings 1–10, and `after8` for 9 and 10, was inspected. Each window is at its new rect with its content drawn. **No frame shows a window at its old rect or blank.**
- During the 120 ms fade the stage's snapshot ghosts over the real window (most visible on Safari's tile, whose snapshot was taken at the other size). By `after12` (about 200 ms) the screen is clean. This is the designed crossfade, not a stale layout.
- **Finding:** on macOS 15.7 the screen recording **does** contain the stage, even though `sharingType = .none` and the Debug capturable switch was off: the `before` frames show the stage's tiles over the backdrop. `sharingType = .none` therefore does not hide the stage from ScreenCaptureKit-based screen capture or sharing on macOS 15. Transom's own captures are unaffected, because `SnapshotCapture` uses single-window filters. RESEARCH Pattern 6 / Pitfall 7 and UI-SPEC's "never captured by screen sharing" need this caveat.
- **Finding:** at zoom-in only about 6 of 15 snapshots arrive within the 120 ms budget (G8). In the recordings the three view tiles were drawn as fill colour because they were not captured in time. 04-04's cache is needed for snapshot tiles to show on the first move.

## G3: WindowServer and replayd over a 1-hour soak

Directory `soak-20261028-012908` (`soak --minutes 60 --interval 10 --fixtures 8 --apps vscode,safari,terminal,textedit`), the same 15 windows. One move every 10 s, alternating in and out (343 moves). Before each move it captured the windows visible at the start (120 ms budget), and after settle it refreshed captures of the windows visible at the end (2 s deadline). Memory was sampled every 60 s (61 samples, minutes 0–60) with `top -l 1 -pid <pid> -stats mem` (physical footprint, Pitfall 6), with `ps -o rss=` beside it for reference only.

| Process | First 10 min mean | Last 10 min mean | Growth | Range | Pass |
|---|---|---|---|---|---|
| WindowServer (`top` MEM) | about 394 MB | about 401 MB | **+7.5 MB** | 389–402 MB | PASS (< 200 MB) |
| replayd (`top` MEM) | about 11.5 MB | about 13 MB | **+1.6 MB** | 11–13 MB | not flagged (< 200 MB) |
| WindowServer (`ps` RSS, reference) | 121,744 KB at minute 0 | 130,048 KB at minute 60 | +8 MB | — | — |

The curve is flat with noise (minute 0: 401, 12: 394, 30: 396, 48: 396, 54: 401, 60: 402 MB). The last few minutes edge up by about 5 MB, which an hour can't separate from noise. A longer soak on the host would, if wanted. No capture timed out or failed.

## G4: Core Animation with 120 tiles

Real `StagePanel`, 120 tiles of 480x300 px generated CGImages in a 11 x 11 grid, animated 250 ms to a 2x zoom (alternating directions). `NSView.displayLink` callbacks counted between animation start and the CATransaction completion. Expected = 0.25 s x 60 Hz = 15 frames. Pass per run: ≥ 90% of expected and no gap above 2 refresh periods (33.3 ms). **VM numbers are indicative only** (virtual GPU, CONTEXT E).

| Set | Directory | Runs passing | frames/expected min / mean | Largest gap |
|---|---|---|---|---|
| Animated (position + bounds) | `layers-20261028-001648` | 20/20 | 1.00 / 1.04 | 20.6 ms |
| Crossfade (Reduce Motion), set 1 | `layers-20261028-002630` | 19/20 | 0.33 / 1.00 | 172 ms (run 2: 5 frames) |
| Crossfade, set 2 | `layers-20261028-002734` | 19/20 | 0.93 / 1.03 | 51.8 ms (one run) |
| Crossfade, set 3 | `layers-20261028-002823` | 20/20 | 1.00 / 1.03 | 20.7 ms |
| Animated smoke | `layers-20261027-234830` | 2/2 | 1.00 / 1.00 | 20.6 ms |

On a strict reading of the per-run rule, G4 fails: 2 of 82 runs stalled, both crossfades. The stalls do not repeat between sets (set 3 is clean), and they are not at the first frame: set 3 logged where the largest gap fell, and it was spread over the animation. That points to VM main-thread scheduling, not to layer creation. A display-link count measures main-thread frame delivery; it does not measure Core Animation's render-server throughput directly. Plan rule if this is judged a fail: draw only tiles that intersect the display, and downsample images. Metal stays deferred. A host confirmation run (RESEARCH Open Question 4) would settle it; it needs your explicit permission.

## G5: stage level vs open menus and a toast

Directory `menus-20261027-234844`, run with `TRANSOM_STAGE_CAPTURABLE=1` (Debug only). A harness status item's menu was opened (`performClick`). A timer in `.common` run-loop mode showed and animated the stage while the menu was open, re-ordered a toast-style panel front (as UI-SPEC says), read the CG window order, and took `g5-menu-stage.png`.

- Front-to-back order of the harness's own windows: menu (layer 101), status item (25), toast (3, ordered after the stage), stage (3, 1024x768). `popUpMenu` = 101, stage `.floating` = 3.
- The still shows the open menu, the menu bar, the Dock and the toast above the stage. A dark system HUD panel in the top right is also above the stage.
- A9 holds: an executable started over SSH shows panels in the console session and gets display-link callbacks.

## G6: Terminal re-wrap

Final run, run 0. Terminal window 1 is in the view; window 2 is parked. Columns are read with `stty size </dev/tty` inside each window.

| Moment | Window 1 cols | Window 2 cols | Still |
|---|---|---|---|
| Before zoom-in (home tile 256 pt wide) | 33 | 33 | `g6-before.png` |
| After zoom-in (view column 341 pt wide) | 45 | 33 | `g6-in.png` |
| After zoom-out | 33 | 33 | `g6-out.png` |

Scrollback and `less` re-wrap on every size change, both ways (Pitfall 8; it can't be avoided for windows whose size changes). The parked window keeps its size, so it doesn't re-wrap. In the 14-window run's frames, Terminal once briefly kept fragments of the old wrap on two lines while `less` redrew.

## G7: represented state (window with a minimum above its tile)

Directory `minsize-20261028-002637`. Fixture windows `standard, standard, minsize:900x700` laid out in three columns at half height. The minsize window was asked for 341.3 x 344.5 and **read back 900 x 700 (refused) in 8.7 ms** (the whole batch also took 8.7 ms). The collapsed-block display and double-click-to-zoom (ZOOM-13) don't exist yet, so the UX half of G7 is **no observation**. 04-02/04-05 cover it.

## G8: capture costs

Directory `capture-20261028-001631`, same 15-window set.

| Measure | Value |
|---|---|
| `SnapshotCapture.refreshShareable()` (SCShareableContent fetch), 10 samples | 52.2–63.8 ms (median about 56 ms): keep it off the move's critical path, as designed |
| One capture at 25 / 50 / 100% of native size, p50 per bundle | 19.5–29.8 ms at every size; size barely matters in the VM |
| Slowest single capture | 131.8 ms (a fixture window, 25%) |
| Captures within the 120 ms move budget at zoom-in (settle run, concurrency 4) | mean 6.3 of 15 (budgetMissed mean 8.7); at zoom-out 3 of 3 |
| Parked window (VS Code, `ignoreGlobalClipSingleWindow = true`) | captured 800 x 540 as requested, not blank, while stranded: **A3 confirmed**, so entering tiles can use fresh captures |

Every capture returned an image (no timeouts or errors).

## Ladder

None applied. G1 passed at p95 205.1 ms, so neither `FrameWriter.move` nor the per-drain `AXEnhancedUserInterface` read was needed. `git status -- Sources/TransomMac/AX` is clean.

## Verdict

**Recommendation: GO with conditions** (awaiting your decision at the checkpoint; this section records your reply before any later plan starts).

Gates against the RESEARCH thresholds:
- G1 PASS: p95 205.1 ms in and 93.1 ms out for 15 windows with Electron; no ladder needed.
- G2 PASS: 0 mismatches in 40 moves; 10 recorded reveals clean after the fade.
- G3 PASS: WindowServer +7.5 MB, replayd +1.6 MB over 60 minutes.
- G4 FAIL on a strict per-run reading, VM indicative: animated moves 20/20; crossfade 58/60, with 2 sporadic stalls.
- G5–G8 reported with numbers and stills. G7's UX half is "no observation" (not built yet).

Conditions proposed:
1. **G4 crossfade stalls.** Either accept them as VM noise (2 of 60 Reduce Motion runs, not repeatable, none in 22 animated runs), or allow one bounded host confirmation run of G4 (and G1) on macOS 27 (RESEARCH Open Question 4; host runs need your explicit permission). If they are treated as real, 04-04 applies the G4 rule: draw only tiles that intersect the display, and downsample images.
2. **Snapshot budget.** In the VM only about 6 of 15 captures land inside the 120 ms budget on a zoom-in, so the first move after a change shows fallback tiles for most windows. 04-04's per-window cache, refreshed after settle, is required, not optional.
3. **`sharingType = .none` does not hide the stage from screen recording on macOS 15.7.** Update the UI-SPEC / threat-model wording ("never captured by screen sharing") to "excluded from Transom's own snapshots; may appear in system screen recordings on macOS 15+". The Debug capturable switch is then mainly useful on older systems. Transom's single-window captures never contain it.
4. **ZOOM-07 budget definition.** The 500 ms gate measured the first write to the last read-back, as RESEARCH defines it. End to end from a keypress, the worst VM move is about 820 ms (capture 120 + animation 250 + settle 280 + 50 + fade 120). Confirm the RESEARCH definition, or say if ZOOM-07 means end to end.

**User decision:** _pending (checkpoint Task 3)_

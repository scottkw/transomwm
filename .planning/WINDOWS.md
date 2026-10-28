---
schema_version: 1
open_count: 3
waived_count: 0
fixed_count: 2
total_count: 5
last_updated: 2026-10-28T16:36:34.074Z
---

# Broken Windows Ledger

> Cross-phase defect register. With `workflow.windows_enforce` enabled, `/gsd-ship` blocks while `open_count > 0`.
> Waive with `gsd-tools windows waive <id> "<reason>"` (reason required).
> Mark fixed with `gsd-tools windows fixed <id>`.

| id | phase | kind | file | line | description | status | reason | recorded_at | resolved_at |
|----|-------|------|------|------|-------------|--------|--------|-------------|-------------|
| 1 | 1 | deviation | Sources/PaneModel/TreeEdits.swift | 64 | n-ary insert scales sibling weights without a minWeight clamp; 01-02 normalize() adds it | fixed |  | 2026-10-24T04:55:49.599Z | 2026-10-24T05:03:53.145Z |
| 2 | 2 | stub | Sources/PaneMac/AXWindowSystem.swift | 64 | AXWindowSystem.perform logs and drops commands until the frame write pipeline (Plan 02-12) | open |  | 2026-10-24T15:21:12.256Z |  |
| 3 | 2 | unrun-verify | Sources/PaneMac/SessionGate.swift |  | 02-09 human-check: real screen lock (30 s) and system sleep (1 min) with 10 windows open; rows survive and footer shows Refreshing after wake (end-of-phase UAT) | open |  | 2026-10-24T17:17:32.790Z |  |
| 4 | 04 | stub | Sources/TransomMac/Zoom/ZoomInput.swift |  | collapsed blocks are not pick targets until 04-07 gives them panels | fixed |  | 2026-10-28T15:48:11.183Z | 2026-10-28T16:09:06.891Z |
| 5 | 4 | unrun-verify | Tests/TransomMacIntegrationTests/RecoveryIntegrationTests.swift |  | 04-08 human-check (end-of-phase VM UAT): kill -9 Transom Debug while zoomed then relaunch (no window parked, N2 shows); Safari cmd-shift-click new tab; fn-ctrl-opt-cmd-left pans without macOS tiling; desktop icon vs wallpaper double-click; Reduce Motion crossfade; fallback tiles legible light/dark without Screen Recording; menu above the stage | open |  | 2026-10-28T16:36:34.074Z |  |

````json
[
  {
    "id": 1,
    "kind": "deviation",
    "phase": "1",
    "file": "Sources/PaneModel/TreeEdits.swift",
    "line": 64,
    "description": "n-ary insert scales sibling weights without a minWeight clamp; 01-02 normalize() adds it",
    "status": "fixed",
    "reason": "",
    "recorded_at": "2026-10-24T04:55:49.599Z",
    "resolved_at": "2026-10-24T05:03:53.145Z",
    "milestone": null
  },
  {
    "id": 2,
    "kind": "stub",
    "phase": "2",
    "file": "Sources/PaneMac/AXWindowSystem.swift",
    "line": 64,
    "description": "AXWindowSystem.perform logs and drops commands until the frame write pipeline (Plan 02-12)",
    "status": "open",
    "reason": "",
    "recorded_at": "2026-10-24T15:21:12.256Z",
    "resolved_at": null,
    "milestone": null
  },
  {
    "id": 3,
    "kind": "unrun-verify",
    "phase": "2",
    "file": "Sources/PaneMac/SessionGate.swift",
    "line": null,
    "description": "02-09 human-check: real screen lock (30 s) and system sleep (1 min) with 10 windows open; rows survive and footer shows Refreshing after wake (end-of-phase UAT)",
    "status": "open",
    "reason": "",
    "recorded_at": "2026-10-24T17:17:32.790Z",
    "resolved_at": null,
    "milestone": null
  },
  {
    "id": 4,
    "kind": "stub",
    "phase": "04",
    "file": "Sources/TransomMac/Zoom/ZoomInput.swift",
    "line": null,
    "description": "collapsed blocks are not pick targets until 04-07 gives them panels",
    "status": "fixed",
    "reason": "",
    "recorded_at": "2026-10-28T15:48:11.183Z",
    "resolved_at": "2026-10-28T16:09:06.891Z",
    "milestone": null
  },
  {
    "id": 5,
    "kind": "unrun-verify",
    "phase": "4",
    "file": "Tests/TransomMacIntegrationTests/RecoveryIntegrationTests.swift",
    "line": null,
    "description": "04-08 human-check (end-of-phase VM UAT): kill -9 Transom Debug while zoomed then relaunch (no window parked, N2 shows); Safari cmd-shift-click new tab; fn-ctrl-opt-cmd-left pans without macOS tiling; desktop icon vs wallpaper double-click; Reduce Motion crossfade; fallback tiles legible light/dark without Screen Recording; menu above the stage",
    "status": "open",
    "reason": "",
    "recorded_at": "2026-10-28T16:36:34.074Z",
    "resolved_at": null,
    "milestone": null
  }
]
````

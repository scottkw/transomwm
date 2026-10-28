---
schema_version: 1
open_count: 2
waived_count: 0
fixed_count: 1
total_count: 3
last_updated: 2026-10-24T17:17:32.790Z
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
  }
]
````

---
schema_version: 1
open_count: 1
waived_count: 0
fixed_count: 0
total_count: 1
last_updated: 2026-10-24T04:55:49.599Z
---

# Broken Windows Ledger

> Cross-phase defect register. With `workflow.windows_enforce` enabled, `/gsd-ship` blocks while `open_count > 0`.
> Waive with `gsd-tools windows waive <id> "<reason>"` (reason required).
> Mark fixed with `gsd-tools windows fixed <id>`.

| id | phase | kind | file | line | description | status | reason | recorded_at | resolved_at |
|----|-------|------|------|------|-------------|--------|--------|-------------|-------------|
| 1 | 1 | deviation | Sources/PaneModel/TreeEdits.swift | 64 | n-ary insert scales sibling weights without a minWeight clamp; 01-02 normalize() adds it | open |  | 2026-10-24T04:55:49.599Z |  |

````json
[
  {
    "id": 1,
    "kind": "deviation",
    "phase": "1",
    "file": "Sources/PaneModel/TreeEdits.swift",
    "line": 64,
    "description": "n-ary insert scales sibling weights without a minWeight clamp; 01-02 normalize() adds it",
    "status": "open",
    "reason": "",
    "recorded_at": "2026-10-24T04:55:49.599Z",
    "resolved_at": null,
    "milestone": null
  }
]
````

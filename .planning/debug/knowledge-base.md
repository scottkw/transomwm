# GSD Debug Knowledge Base

Resolved debug sessions. Used by `gsd-debugger` to surface known-pattern hypotheses at the start of new investigations.

---

## safari-toolbar-drag-no-dock — an app's windows "never dock by drag" (Safari, unified toolbar); not reproducible
- **Date:** 2026-10-26
- **Error patterns:** drag to dock, no preview, stays floating, Safari, unified toolbar, title bar drag, TextEdit works
- **Root cause(s):** unknown; not reproducible at bb67b5d. Most likely the first report came from a session whose tap was not running (WR-02, tracking started only after a relaunch) or from drops outside every drop zone
- **Fix:** none needed; drag logging kept at debug level (`log stream --level debug --predicate 'subsystem == "com.eightabyte.pane" AND category == "drag"'`): one press line (session or why not, AX and CG start frames) and one release line (kind, travel, dragged events, polls, first/last CG, decision, preview)
- **Files changed:** Sources/PaneEngine/DragSession.swift, Sources/PaneMac/ArrangeController.swift (diagnostics only)
- **Why not caught:** no gate existed for this class: live drags are human UAT, and the first report had no log to tell "no session" from "miss" from a misclassification
- **Recurrence guard:** the "drag" debug log above. Read it before changing the drag classifier; first confirm the tap is running (permission -> ready in the log) and that the press logged a "start" line
---


# Spaces fixtures

`SLSCopyManagedDisplaySpaces` answers, written as JSON for `SpacesSnapshotTests`. Shapes are copied from the local
read-only probe on macOS 27.2 (06-RESEARCH "Verified Facts" F1); UUIDs other than the probe's display and first
Spaces are made up.

| File | Source | What it pins |
|---|---|---|
| `separate-one-display.json` | F1 probe output (Spaces 3, 4, 149 on the built-in display) | separate Spaces, three desktops in order, a Space carrying its own `Display Identifier` |
| `spans-main.json` | synthetic, F1 shape with `"Display Identifier": "Main"` (06-RESEARCH A5, Pitfall 6) | spans mode maps `Main` to the main display's UUID |
| `empty-uuid.json` | synthetic, F1 shape with `uuid = ""` on Desktop 1 (ianyh.com blog, Pitfall 6) | empty uuid becomes `default:<displayUUID>` |
| `fullscreen.json` | synthetic, F1 shape with a type-4 full-screen and a type-2 system Space (yabai `space.c` type values) | full screen kept with index 0, system Space skipped |

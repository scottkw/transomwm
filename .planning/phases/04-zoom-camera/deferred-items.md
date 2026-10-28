# Phase 4 deferred items

## FreezeTestTests.itResumesByItself fails under the full parallel suite (found during 04-03)

- **Test:** `Tests/TransomMacTests/FreezeTestTests.swift` `itResumesByItself`
- **Symptom:** under the full `swift test`, the recorder never sees SIGCONT within the test's 1 s wall-clock deadline (3 issues). It passes 8/8 when `--filter FreezeTestTests` runs alone.
- **Pre-existing:** a full `swift test` at `dd2bd51` (before 04-03) fails in exactly the same way.
- **Likely cause:** the 50 ms `Task.sleep` resume in `FreezeTest` competes with the rest of the parallel TransomMac suite, and the test busy-waits on wall time.
- **Not fixed:** out of scope for 04-03, which touches no FreezeTest code. A later plan can give the test an injected clock or a longer deadline.


## Found during 08.1-06

- `Tests/TransomMacTests/FreezeTestTests.swift` `itResumesByItself` failed once in a full `swift test` run (`.build/081-06-t3-full.log`): its 1 s deadline passed before a 50 ms resume timer ran. It passed 3 of 3 alone and in a full re-run. Likely timing under load, not reproduced, not fixed. 08.1-06 didn't touch this code.

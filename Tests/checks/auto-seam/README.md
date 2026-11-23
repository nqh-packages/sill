# `auto-seam`

**Checks:** the seam around Auto (docs/adaptive-quality-plan.md, "codebase-design check"), declared as three rules in `seam.py` and enforced over every Swift file: `lowerBitrate(` is called only from `StreamCoordinator+Auto.swift` (and defined in `HEVCEncoder.swift`), `autoRunning` is assigned only inside `commitRunning`, and `AutoQuality(` is constructed only by the coordinator's Auto file, the auto-quality check and the pacing harness; a failure prints the file and line, the rule and a `fix:` line, fixtures prove each rule fires and stays quiet where it should, and every allow-list names files that exist

**Compiles:** nothing: Python only, it reads `Sources`, `Scripts`, `Tests` and `iOSClient`; to widen a rule edit `RULES` in `seam.py` in the same commit, never skip the check

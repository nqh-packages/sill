**Auto quality, and the dock above the keyboard (2026-11-23, branch `feat/tactile-ui-redesign-1` from main at c33d105).**

- **The dock above the keyboard** (c8a73323): the floating dock and trackpad took their bottom margin from
  the full screen, so with the software keyboard up a trailing dock sat over the key row. Both now take it
  from `StreamWorkspaceState.chromeBottomClearance` with the live keyboard height; tactile-workspace checks
  it, `.jev-lint/rules/floating-chrome-clears-keyboard.md` guards it.
- **Auto quality**: the plan, decisions, evidence, design and each slice's results are
  docs/adaptive-quality-plan.md; the design package docs/design/adaptive-quality/. Auto is the default
  Quality; the host lowers the encoder's bitrate live one rung at a time and climbs by restart
  (`AutoQuality`, `StreamCoordinator+Auto.swift`, `HEVCEncoder.lowerBitrate`), guarded by
  Tests/checks/auto-seam.
- **Learned**: the hardware HEVC encoder follows a one-preset live decrease without drops, not a raise
  (`Scripts/encoder-check/verify-hardware.sh ratelive`, docs/evidence/adaptive-quality). Low-latency rate
  control follows both ways but drops to ~37 fps under a tight budget: not used.
- **Verified**: Tests/checks/run-all.sh all passed on the merged build; `swift build -c release` and the iOS
  simulator build; pacing `autodown`, `autodrift`, `autoclimb`, `autostill` pass; a headless
  `--synthetic --auto-quality` host through `sillrelay.py --rate-mbps 5` started at Extreme · Retina and
  capped to Low · Standard in one restart; the client saw `autoScale` 2 → 1.
- **Untested, for Noah**: a live lower on the hardware encoder inside Sill (only `ratelive` measured the
  properties); the iOS Quality menu and the resolution notice on a device or simulator (the agents' Duo and
  iPad simulators do not exist; mocks `-SillSettingsCase auto` and `autolowered` are ready); a real Wi-Fi
  and away session.

**The screen's rounded corners (2026-11-24).** Huy's photo: the picture ran under the iPhone's bottom
corners (controls shown: the root ignores the bottom safe area and the canvas had no inset). Grilled: no Mac
pixel hidden; the strips filled with the picture's edges; the radius from iOS 27's public API. Now
`ScreenCorners` (FullScreenPolicy.swift) pulls the picture's place in until its corners clear the curve, shown
and hidden, and `PictureEdgesExtended` fills the strips (docs/full-screen-plan.md, "The screen's rounded
corners"). Verified: Tests/checks/full-screen (3,000 random rects: every corner on the screen, never larger,
a clear one unchanged; mutants K1–K6 caught); the simulator build. **Untested, on a device:** whether
`concentricCornerRadii` answers at the root (the console's "corners: …" line says; else the cautious 62 pt),
whether the extension effect draws the video layer, and its cost per frame.

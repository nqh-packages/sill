# Adaptive quality ("Auto")

Status: decided 2026-11-23 (Huy, in a grilling session), design next. Reverses
docs/remote-bundle-plan.md open question 2 ("Automatic step-down: off") on Huy's decision.

## Decisions

1. **Auto is a new Quality choice and the default.** Low … Extreme stay fixed and never adapt.
   Every Mac moves to Auto once on update; picking a preset again fixes the rate.
2. **How it adapts.** Down: the encoder's bitrate is lowered on the running session, one preset
   step at a time, no restart. Up: one restart per step (a brief keyframe blip), only after the link
   has been clean. Below Low, Retina drops to Standard (one restart), and comes back the same way.
3. **Ceiling:** Extreme, at home and away.
4. **Start:** at home at the ceiling's top (Extreme is capped by the link the first seconds show);
   away at Low, climbing.
5. **Pace:** conservative both ways: LinkJudge's timing (behind at 3 short seconds of 5; a climb
   only after 5 clean seconds in a row).
6. **Two devices:** with any device at home, Auto adapts to the home devices only and away devices
   keep today's per-device frame dropping. With every device away, it adapts to the slowest.
7. **What people see:** bitrate changes are silent. A resolution drop shows a short notice on the
   device. While Auto is on, the "The link can't carry ‹Pro›" callout and its button do not show
   (Auto is acting on it). The Mac's log keeps its "Link to …" lines and logs each Auto step.
8. **Compatibility:** Auto crosses the wire as a new optional field, sent only to devices that said
   they take it. An older device sees the running rate as its nearest preset; a pick from it fixes
   the rate. Older devices stop getting the suggestion while Auto runs, which they skip unharmed.

## Evidence: the encoder and a live bitrate

`Scripts/encoder-check/verify-hardware.sh ratelive` (raw output: docs/evidence/adaptive-quality/),
M2 Pro, 2026-11-23, 60 fps, a still desktop with a moving band of text-like blocks:

- The hardware HEVC encoder (`ave.hevc`) follows one-preset steps **down** on a live session
  without drops (3024×1964: 40 → 25 → 15 Mbps, 0 dropped). A 5× step down (40 → 8) drops ~41
  frames in the next second. Steps **up** follow only partly and unreliably (8 → 40 reached 28;
  25 → 40 stayed at 17.5). The encoder's output runs at ~0.7 of AverageBitRate.
- `EnableLowLatencyRateControl` runs another encoder (`hevc.rtvc`), follows every change within a
  second, but holds a tight budget by dropping to ~37 fps. Not used.
- This refines StreamCoordinator.restartNeeded's 2026-09-25 note ("a new bitrate needs a new
  encoder session"): true upward, not for one-step decreases.

## Grounding (what exists, file:line at commit 2340c65a)

- **Settings:** `HostConfig` (Sources/SillHost/HostConfig.swift:9) holds `bitrate`, `captureScale`,
  `awayBitrate`, `awayCaptureScale`, `maxFPS`; `effective(away:)` :214. Saved by
  Sources/SillMenuBar/HostSettings.swift (UserDefaults keys "bitrate", "awayBitrate", …, :43).
  `QualityPreset` (Sources/StreamProtocol/HostSettings.swift:310) is an Int enum of bits/s.
- **Wire:** kind 16 `HostSettingsState` (:185) host → device with `settings: StreamSettings` (:64),
  `away?`, `link?: LinkReport` (:147, suggestion fields); kind 17 `HostSettingsChange` (:243) device
  → host. New fields optional; the hand-kept checklist at HostSettings.swift:24–40 lists every place
  a setting must be added. `DeviceSettings.accepted` (Sources/SillHost/DeviceSettings.swift:79)
  whitelists preset bitrates only.
- **Coordinator** (Sources/SillHost/StreamCoordinator.swift): `setTarget` :965 → `applyPending`
  :992 → `restartNeeded` :1053 (any bitrate change restarts) → `select` / `adopt` :1068.
  Home/away: `awayWanted`/`awayRunning` :350, `routesChanged` :1012, AwayPolicy.
- **Encoder:** `HEVCEncoder.makeSession` (Sources/SillHost/HEVCEncoder.swift:149) sets
  AverageBitRate and DataRateLimits once; `bitrate` is a `let`; no live setter.
- **LinkJudge** (Sources/SillHost/LinkJudge.swift): per device per second (`StreamServer.sweep`,
  StreamServer.swift:1358), states fine/behind/stalled, `carriedKbps`, `suggestion` :170 (highest
  preset under 70 % of the carried rate). `judgedAfresh`/`reset` clear it on a bitrate change, and
  `settingsState(for:)` (coordinator :3764) hides a report whose bitrate is no longer the target's.
  Frames are withheld per device in `broadcast` :1636 (home) and `paceRemote` :1772 (away); one
  encoder feeds every device.
- **iOS:** Quality picker HostSettingsPanel.swift:579 and ControlCenterSheet.swift:315; callout
  HostSettingsPanel.swift:325 with AwayCopy.swift:94; ledger HostSettingsLedger.swift.
- **Mac UI:** SettingsPanes.swift `StreamingPane` :437; menu StatusItemController.swift:115.
- **Checks:** Tests/checks/link-judge, away-quality, away-wire, away-copy, ledger, compatibility
  (each with mutants.py).
- **Analytics:** none in the codebase; records are log lines and `Stats` counters.

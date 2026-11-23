# Adaptive quality ("Auto")

Status: decided 2026-11-23 (Huy, in a grilling session), design next. Reverses
docs/remote-bundle-plan.md open question 2 ("Automatic step-down: off") on Huy's decision.

## Decisions

Huy, 2026-11-23: these are the direction, not directives. Where two of them pull against each other
(a home start at Extreme against a conservative pace), the design resolves it on the evidence and
says how; it does not need to come back for a ruling.

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

## Design (synthesized 2026-11-23)

The design package is docs/design/adaptive-quality/: DESIGN.md (base), MODULES.md (every file, wire
field, check and harness case), Sketch.swift.txt (types and signatures), JUDGE.md (the cross-judge).

### Synthesis decision

Two independent candidates (Claude Opus 5.5, Gemini 4 Neon) converged on one shape: a pure
`AutoQuality` owned by the coordinator, a ladder of (preset, Retina/Standard) rungs, a step's `how`
derived from the two rungs (one rung down at one resolution = live; everything else = restart), and
per-device windows of their own so Auto's steps cannot blind it. The base is candidate 1 (cross-judge
26/30 against 20/30): one commit point for what runs (`commitRunning`), LinkJudge's rules shared but
never its state, `effective(away:)` replaced rather than kept beside the new reader, one iOS
`QualityMenu` for both pickers, and pacing-harness cases whose gates are derived from a simulated link.

Grafted from candidate 2:
- **One hop a second.** `StreamServer` hands the coordinator each second's `(id, Second, Verdict?)`
  in one main-actor hop, so the "Link to …" line always precedes the Auto step line and no reset races.
- **A preset pick while Auto runs is never lost.** A device that takes Auto sends
  `{bitrate, autoQuality: false}` for a preset pick (host: `false` is taken only with a bitrate), and
  the ledger treats Auto and the preset as one field, so picking the preset Auto happens to run at still
  fixes it. An older device sends `{bitrate}`, which fixes as today.
- **The callout stays for a device Auto does not govern** (an away device beside a home one): `link` is
  withheld only from connections whose pair Auto runs.
- `AwayQuality` gains `homeAuto`/`awayAuto` (takers only) so the away header reads "Auto · Standard".
- The resolution notice is idempotent per drop and posts a VoiceOver announcement.
- `HEVCEncoder` retires a slow-state replacement made before a live lower, so a swap never restores
  the old rate.

### Open questions, resolved on the evidence (Huy: decisions are direction)

1. **Home start vs pace.** The first behind judgement after Auto starts or flips caps to what the link
   carried (`LinkJudge.suggestion` on the ladder), one restart; every later step is one rung, live, per
   3-of-5. Arithmetic: behind means carried < ~0.7 × the rung and the fit is ≤ 0.7 × carried, so the cap
   is always two or more rungs (a live multi-rung drop costs ~41 frames). ~3 s and one blip instead of
   ~15 s of stutter.
2. **Encoder-side drops are invisible to the link judge** (ratelive 3024×1964: 7/s at 8 Mbps, 34/s at
   4 Mbps). The Retina ladder skips Low · Retina: Efficient · Retina → Low · Standard. Calibration from
   that measurement, recorded as such.
3. **Climb evidence:** a clean second counts only when the stream offered ≥ fps/4 frames. Labelled
   calibration; the `autostill` harness case holds it.
4. **Failed climb hold:** a climb judged behind within 10 s doubles the next climb's clean seconds to
   that rung, up to 60 s. Labelled calibration; the `autodown` case gates it.
5. Away start: Low at the away Resolution (Standard by default).
6. The Mac's menu checks "Auto" and its subtitle names the rung ("Balanced now"); passive, no notice.
   The CLI stays fixed by default (`--auto-quality` opts in) so headless tests keep their rates and the
   CLI's stdout stays byte-identical.
7. The backlog after a live step can make 1–2 short seconds at the new rung: the `autodrift` case
   gates one step per drop of the link.

### codebase-design check (2026-11-23)

- **AutoQuality is deep.** Interface: `init(place:retina:)`, `rung`, `close(_:governing:running:fps:)
  -> Step?`, `governing(_:)`, `stepLine`, `startLine`. Behind it: the ladder, the windows, the
  cross-device merge, the cap, the hold and the live-or-restart rule. Deletion test: deleting it would
  spread all of that into the coordinator. Change: `downTarget`, `how`, `isLoaded` and `needs` are
  `private`; `Tests/checks/auto-quality` drives everything through `close` (the interface is the test
  surface), not past it.
- **The coordinator side gets its own file.** StreamCoordinator.swift is 3,842 lines; Auto's shell
  (`syncAuto`, `autoSecond`, `lowerLive`, `commitRunning` and its three stored properties' uses) goes in
  `Sources/SillHost/StreamCoordinator+Auto.swift`, an extension, so Auto's coordination lives in one
  place and the monolith gains only the stored properties and the calls at `select`'s commit,
  `restartNeeded` and `settingsState`.
- **The seam is guarded.** New check `Tests/checks/auto-seam` (Python, like repo-rules) declares and
  enforces: `lowerBitrate(` is called only from StreamCoordinator+Auto.swift; `autoRunning` is assigned
  only inside `commitRunning`; `AutoQuality(` is constructed only there, in Tests/checks/auto-quality
  and in Scripts/pacing. Each failure prints the file, the line, the rule and a `fix:` line; fixtures
  prove each rule fires and its allow-list names files that exist. CLAUDE.md's pointer stays as is;
  docs/LAYOUT.md names the check.
- Seams with one adapter (`StreamServer.onSecond`) stay plain callbacks; no protocol is introduced.
- Not built: product analytics. The app has no analytics source (zero operating costs); Auto's
  outcomes are the "Auto:" log lines and the `auto.live`, `auto.restart`, `enc.lowered` counters.
- No tip: Auto is the default and asks nothing of the person; picking a preset is the existing control.

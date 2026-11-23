# Auto adaptive quality: candidate 1, "one rung, its own windows, one commit point"

Repo read at `84ac3610` (worktree `t3-82439694`). Types: [Sketch.swift](Sketch.swift). Files, wire, UI,
migration and checks: [MODULES.md](MODULES.md).

## Problem

Auto must pick the bitrate (and, below Low, the resolution) of the Mac's **one** encoder from how
several devices' links keep up. Four things in the existing system make the shape non-obvious:

- **The judge resets itself on every bitrate change.** `LinkJudge.judgedAfresh` resets on any new
  quality, verdicts come only on a *change* of state, and `settingsState` (StreamCoordinator.swift
  :3769) hides a report whose bitrate is no longer the target's. A policy built on LinkJudge's verdicts
  or on `linkReports` goes blind after each of its own steps.
- **The encoder is asymmetric.** One-preset steps down follow on a live session with no drops. Steps up
  don't follow reliably (25 → 40 stayed at 17.5 Mbps). A 5× live drop costs about 41 frames
  (docs/evidence/adaptive-quality). Today `HEVCEncoder.bitrate` is a `let`. `makeReplacement` (:462)
  remakes slow sessions from it, and that is on by default, so a live lower would be silently undone.
- **"What runs" has no single commit.** The running bitrate is computed from `config` plus
  `awayRunning`. It is committed only inside `select`: `judgeLinks`, `status.stream`. A live step
  happens outside `select`.
- **Compatibility floor.** New wire fields must be optional and go only to devices that say they take
  them. Older devices must see a preset and keep working. A preset pick from any device fixes the rate.

## Usage (caller's view)

The policy is one value with one call per second. The coordinator owns it. The server feeds it. Nobody
else touches it.

```swift
// StreamCoordinator: the per-second feed (server.onSecond, hopped to the main actor)
private func autoSecond(_ seconds: [ObjectIdentifier: LinkJudge.Second]) {
    guard var a = auto, let running = autoRunning else { return }
    let step = a.close(seconds, governing: AutoQuality.governing(routes.mapValues(\.isAway)),
                       running: running, fps: fps)
    auto = a
    guard let step else { return }
    print(AutoQuality.stepLine(step, device: deviceName(id:)))
    switch step.how {
    case .live:    lowerLive(step.to)                       // encoder.lowerBitrate, then commitRunning
    case .restart: Task { await applyPending() }            // restartNeeded sees auto.rung != autoRunning
    }
}

// select's commit, and lowerLive: the one place "what runs" moves
commitRunning(config.choice(away: awayRunning) == .auto ? auto?.rung : nil)

// settingsState: what each connection is told
let pair = t.running(away: thisAway, auto: autoRung(forAway: thisAway))
StreamSettings(..., bitrate: pair.bitrate, ..., autoQuality: autoTakers.contains(id) ? choiceIsAuto : nil)
link: autoRuns ? nil : link                                  // decisions 7 and 8

// iOS: both Quality pickers
Picker("Quality", selection: pickBinding) {
    ForEach(QualityMenu.items(shown), id: \.pick) { Text($0.title).tag($0.pick) }
} currentValueLabel: { Text(QualityMenu.label(shown)) }      // "Auto"
```

A device picks Auto with `HostSettingsChange(autoQuality: true)` and a fixed rate with
`HostSettingsChange(bitrate: 40_000_000)`, as today.

## Shape

**Data first.** `AutoQuality.Rung` is a preset plus Retina or Standard. The **ladder** is built from the
Mac's Resolution:

- Retina: `[Low·Std, Low·Ret, Eff·Ret, Bal·Ret, High·Ret, Pro·Ret, Ultra·Ret, Extreme·Ret]`
- Standard: every preset at Standard

Auto is a position on that ladder. Three pieces of state, each with one owner:

| state | owner | written by |
|---|---|---|
| `rung` (what Auto wants) | `AutoQuality` | `close` only |
| per-device windows of `LinkJudge.Second` since the running rung changed | `AutoQuality` | `close` only |
| `autoRunning` (what the pipeline runs) | coordinator | `commitRunning` only |

**Load-bearing decisions:**

1. **Shared rules, separate windows** (per separate-before-serializing-shared-state). Auto reads the
   raw seconds the sweep already builds. It reuses LinkJudge's *rules*: `isShort`, 3-of-5, 5-clean,
   `suggestion`, and the carried rate. The carried rate is pulled out as
   `LinkJudge.carriedKbps(of:)` so both use one function. Auto never reads the judge's *state*. Its
   windows clear when `running` changes, whoever changed it, and it never judges while a restart is
   pending (`running != rung`). So its own steps can't blind it or count a second twice, and `close`
   is idempotent across a pending restart.
2. **One commit point.** `commitRunning(rung?)` is called by `select`'s commit and by the live step.
   It sets `autoRunning`, calls `judgeLinks` (reports start afresh, as for any quality change),
   updates `status.stream`'s mbps, and publishes. The other readers then agree:
   - `restartNeeded`
   - `settingsState`'s link filter
   - `RunningStream`
   - `settings.bitrate`
3. **`How` is derived, not chosen.** A step is `live` only for exactly one rung down at the same
   resolution, which is the measured case. Everything else is `restart`: every climb, every resolution
   change, and any jump of two or more rungs. `AutoQuality.how(from:to:ladder:)` is that rule.
4. **The start's cap is the old callout's suggestion; every later step is one rung.** This applies
   to the first behind judgement after Auto starts or flips. It is decision 4's "capped by the link
   the first seconds show". There, `downTarget` maps `LinkJudge.suggestion` onto the ladder, the rung
   the callout would have recommended, and restarts straight to it.
   - **Why one restart:** a behind link carries less than the stream's ~0.7 × target. The fit is at
     most 0.7 × that, so ~0.49 × the rung, always two or more rungs down (Extreme → Pro, Pro →
     Balanced). A multi-preset live drop is the 41-frame loss the evidence shows.
   - **Every later judgement** is one rung, live: decisions 2 and 5 as written. The exception is
     Low · Retina → Low · Standard, which restarts.
5. **Climb evidence must be loaded.** A clean second counts toward a climb only if the stream offered
   at least fps/4 frames. Otherwise a still window over a 2 Mbps phone link would climb to Extreme and
   then stutter on the first scroll. A climb that fails within 10 s doubles what the next climb to
   that rung needs, up to 60 s. Without this, a link sitting between two presets would get a restart
   blip about every 8 s.
6. **`BitrateChoice` in HostConfig, plain fields on the wire.** `HostConfig.bitrate` and `awayBitrate`
   keep their names but change type to `.auto | .fixed(Int)`. The compiler then lists every reader,
   and each must decide what Auto means there. The wire keeps `bitrate` as an Int (what runs, always a
   preset) and adds `autoQuality: Bool?`. That respects "no enums in payloads".
7. **The encoder only lowers live.** `HEVCEncoder.lowerBitrate(to:)` sets exactly what `ratelive`
   measured: AverageBitRate, and DataRateLimits `[bps/8, 1]`. It runs on the encode queue. The rate
   becomes a lock-guarded `var`, which `makeReplacement` reads. A raise returns false.

**Interface depth.** The public surface is `init(place:retina:)`, `rung`, `close(…) -> Step?`,
`governing(_:)` and the line functions. That surface hides:

- the ladder
- the windows
- the merge across devices (down if any governing device is behind, using the lowest target; up only
  if all are clean and loaded)
- the hold
- the target choice
- the live-or-restart rule

The coordinator's shell is four functions (Sketch §6). The device side is one pure `QualityMenu` that
replaces two hand-kept picker copies.

**What it deliberately does not do:**

- no live raise
- no low-latency rate control
- no per-network memory
- no device-side policy
- no change to `paceRemote` or `broadcast`
- no callout under Auto

### Decisions 1–8: where each is honoured, and what checks it

| # | decision | where in the shape | asserted by |
|---|---|---|---|
| 1 | Auto is a choice and the default; one migration; a preset pick fixes | `BitrateChoice`; `HostConfig.app` = `.auto`; `HostSettings` migration key `autoQualityMigration`; `applying` maps a `bitrate` pick to `.fixed` | away-quality (applying, accepted), settings-window/HostSettings load check (migration once) |
| 2 | down live one step; up one restart per step; below Low Retina → Standard by restart | `AutoQuality.how`, `downTarget` (one rung after the start's cap), `ladder(retina:)`, `HEVCEncoder.lowerBitrate`, `lowerLive`; climbs go through `applyPending`. **Deviation (Q1):** the start's one cap is a restart | auto-quality cases 3, 5, 6, 7; pacing `autodrift` (live lines only after the start), `autoclimb` (restart lines only) |
| 3 | ceiling Extreme home and away | `ladder` top is `.extreme` for both places | auto-quality case 2 |
| 4 | home starts at the top, capped by the first seconds; away at Low climbing | `init(place:retina:)`; `capped` + `startCappedByLink`: the first judgement's carried target | auto-quality cases 1, 5; pacing `autodown` |
| 5 | LinkJudge's pace: 3 of 5 behind, 5 clean to climb | `close` uses `LinkJudge.shortToBehind`, `window`, `cleanToFine` directly | auto-quality cases 3, 4, 7 |
| 6 | any device home → home devices govern; all away → slowest | `AutoQuality.governing`, the merge in `close`; `paceRemote` untouched | auto-quality case 10 |
| 7 | silent bitrate changes; resolution-drop notice; no callout under Auto; log keeps "Link to" and logs each step | `stepLine`/`startLine`; `link: nil` while Auto runs; `HostSettingsState.autoCaptureScale` + `AutoCopy.resolutionNotice` | auto-quality case 11 (lines), away-copy (notice), away-wire (no `link` under Auto) |
| 8 | Auto as an optional field only to takers; old devices see the running preset; their pick fixes | `Hello.autoQuality`, `autoTakers`, `StreamSettings.autoQuality`, `settings.bitrate` = running rung | compatibility (decode old/new, mutants), away-wire (taker vs non-taker states) |

## Red-flags screen

- **Hand-synced list:** the existing checklist at HostSettings.swift:24–40 gains one field. The two
  iOS picker copies become one `QualityMenu`, and the compatibility mutants cover the wire.
- **Split ownership:** `rung` vs `autoRunning` is want vs runs, with one writer each, as
  `awayWanted`/`awayRunning` are.
- **Two ways:** `effective(away:)` is deleted, not kept beside `running(away:auto:)`.
- **Importable internals:** `AutoQuality` is internal to SillHostCore, like LinkJudge; only
  `BitrateChoice` is `package`, because Sill.app saves it.
- **Shallow module / pass-through:** the coordinator's four functions each add policy, none forwards.
  `StreamCoordinator` grows by about 60 lines; it is already a monolith, and this adds a section
  without a new responsibility mixed in.

## Synthesis decision

To be filled in by arena.

## Tradeoffs accepted

- **Two windows of the same seconds.** Auto keeps a window per device, and so does LinkJudge. We
  accept the duplicate state in exchange for never being blinded. The rules stay single-sourced; only
  the clocks differ.
- **One restart at the start's cap** (if Q1 is accepted), instead of walking down one preset per
  judgement. The cost is one keyframe blip, and it arrives ~12 s sooner on 24 Mbps Wi-Fi.
- **The steady state still walks one preset per 3-of-5.** If the start saw no motion (a still window,
  so nothing was measured) and motion then meets a slow link, the stutter is ~3 s per preset as the
  decisions say.
- **Climbs on a still window wait.** We accept a slower climb while nothing moves, in exchange for not
  stuttering on the first scroll.
- **The CLI stays fixed by default** (`--auto-quality` opts in). Headless tests keep their rates. The
  product default, Sill.app, is Auto.
- **The callout is withheld from every connection while Auto runs.** That includes an away device that
  the home quality is not adapting to (see Q5).

## Alternatives considered

- **Policy inside LinkJudge.** The judge owns the rung, and its verdict becomes the step. Its surface
  is smaller, but the judge's reset-on-quality-change is exactly what makes a policy blind. Fixing that
  means skipping the reset for Auto's own steps, which makes the reports stale ("cannot carry Ultra"
  after Auto left Ultra). It also mixes two lifetimes (reports for people, rungs for the encoder) in
  one type that every device's UI reads.
- **Device-driven Auto.** Each device judges its own link and sends kind 17 picks. It fails three
  ways:
  - One encoder serves several devices, and their picks fight.
  - Older devices never send them.
  - The host already sees the withheld frames the device can only infer.
- **Low-latency rate control (`hevc.rtvc`).** It follows every change live, both ways, and so would
  remove the restart for climbs. The evidence rejects it: it holds a tight budget by dropping to about
  37 fps at Retina (ratelive-lowlatency-3024x1964: 204 drops in 18 s), against 0–7 a second with the
  default encoder.
- **Live walk down, one preset a second, after one judgement.** It keeps decision 2's letter (every
  encoder change is one preset) and is about 4 s from Extreme to Balanced. It is **unproven**: the
  measured steps were 3 s apart, and nothing shows the encoder follows faster. It stays a fallback for
  Q1 if a ratelive run at 1 s spacing shows 0 drops.

## Open questions and risks

1. **The tension between decisions 2, 4 and 5 (needs Huy's call).**
   - The conflict: home starts at Extreme (4), and the pace is one preset per 3-of-5 judgement (5),
     down live only (2). On ordinary 24 Mbps Wi-Fi, Extreme → Ultra → Pro → High → Balanced is 3 s
     plus 4 × at least 3 s, which is **about 15 s of stutter** at every home start with motion.
   - Proposed resolution: only the first behind judgement after Auto starts or flips is the start's
     cap. Its target is what the link carried (`LinkJudge.suggestion`, already the callout's rule).
     Arithmetic: behind means carried < ~0.7 × the rung, and the fit is ≤ 0.7 × carried ≈ 0.49 × the
     rung. That is always two or more rungs (Extreme → Pro, Pro → Balanced), so it is one restart:
     about 3 s plus one blip.
   - Every later step is one rung, live, per 3-of-5: decisions 2 and 5 as written.
   - Why not jump at every judgement: by the same arithmetic, every measured judgement would be a
     restart. That would replace decision 2, not refine it.
   - What it breaks: decision 2's "no restart" for that one start step, and decision 5's one step per
     judgement for it.
   - The literal fallback is `AutoQuality.startCappedByLink = false`: decisions as written, ~15 s.
   - The walk alternative above is unproven.
   - Accept the jump?
2. **Encoder drops are invisible to LinkJudge.** At 3024×1964 the encoder itself drops 7 frames a
   second at 8 Mbps and 34 at 4 Mbps (ratelive-default-3024x1964). Auto never sees these: the
   frames are never offered to the network.
   - This undercuts the Low · Retina rung and the climb into it.
   - Should the ladder skip Low · Retina, going Efficient · Retina → Low · Standard?
   - Or should Auto read the encoder's drop counter, which would be a new input?
3. **The "loaded" threshold (fps/4 frames offered) is a calibration.** It has not been measured. Is
   frame count the right climb evidence, or bytes taken against the rung's budget?
4. **The failed-climb hold (10 s, doubling, 60 s cap) is a calibration** beyond decision 5's "5 clean
   seconds". Accept it, or keep the literal 5 s and the oscillation?
5. **An away device while the home quality runs Auto.** Decisions 7 and 8, read literally, withhold
   its callout too. But that callout says "which the Mac keeps while a device at home is connected"
   with no button, and Auto is not acting on that device. Keep it for that case?
6. **Away start.** Is it Low · Standard (the ladder's bottom and the old away default), or Low at the
   away Resolution?
7. **Visibility.** Should the Mac's menu show the running rung under Auto ("Auto, Balanced now")?
   That is passive, not a notice. Should the CLI default to Auto too?
8. **Risk: the backlog after a live step.** The old rate's queue still drains and can make 1–2 short
   seconds at the new rung. 3-of-5 absorbs it, but a link right at the boundary can step twice. The
   pacing harness's `autodrift` gate (one step for one drop of the link) catches it.

## Next implementation step

Write `Sources/SillHost/AutoQuality.swift` and `Tests/checks/auto-quality` together. The cases in
MODULES.md come first, with mutants, before any coordinator change.

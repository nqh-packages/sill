# Module map: candidate 1

This map follows the checklist at `Sources/StreamProtocol/HostSettings.swift:24–40` line by line.
The compiler won't catch a missed entry there. Line numbers are at `84ac3610`.

## Host (SillHostCore)

| file | change |
|---|---|
| **NEW** `Sources/SillHost/AutoQuality.swift` | The policy: `Rung`, the ladder, `close`, `governing`, `downTarget`, `how`, and the lines. Pure (Foundation, StreamProtocol, LinkJudge). |
| `Sources/SillHost/LinkJudge.swift` | Pulls out `static func carriedKbps(of:)`; the instance property calls it. No behaviour change. |
| `Sources/SillHost/HostConfig.swift` | `bitrate` and `awayBitrate` change from `Int` to `BitrateChoice`.<br>`validated()` clamps only `.fixed`.<br>`changes(to:)` says "Auto".<br>`effective(away:)` is deleted, and `choice(away:)` (package) answers what is set. New internal `running(away:auto:)` is the one way to ask what runs.<br>Callers moved: StreamCoordinator.swift:47, :48, :1057, :3769; DeviceSettings.swift:15; Tests/checks/away-quality/main.swift:82–83 and its mutants.py:14; the comment at StreamProtocol/HostSettings.swift:44.<br>`standard` stays fixed; `app` is `.auto` for both. |
| `Sources/SillHost/DeviceSettings.swift` | `streamSettings(away:auto:takesAuto:)`: `bitrate` is the running rung under Auto, and `autoQuality` goes only to a taker.<br>`applying` / `applyingAway`: `autoQuality: true` gives `.auto`; a `bitrate` gives `.fixed`.<br>`accepted`: takes `autoQuality: true`; refuses `false`, and refuses it together with `bitrate`, naming both. |
| `Sources/SillHost/HEVCEncoder.swift` | `bitrate` becomes a `var` under `lock`.<br>New `lowerBitrate(to:)` sets AverageBitRate and DataRateLimits `[bps/8, 1]` on `encodeQueue`.<br>`makeReplacement` reads the current rate.<br>`submit` applies it to a replacement made before a lower. |
| `Sources/SillHost/StreamServer.swift` | `onSecond` is fired at the end of `sweep` (:1358) with every client's `LinkJudge.Second`.<br>`broadcast` (:1636) and `paceRemote` (:1772) are untouched. |
| `Sources/SillHost/StreamCoordinator.swift` | Adds `auto`, `autoRunning`, `autoTakers`, `syncAuto`, `autoSecond`, `lowerLive`, `commitRunning`.<br>`bitrate`/`scale` (:48) are read through `running(away:auto:)`.<br>`restartNeeded` (:1053) compares the resolved rung.<br>`applyPending`'s guard (:994) also wakes when `auto?.rung != autoRunning`.<br>`select`'s commit (:2057) calls `commitRunning` instead of `judgeLinks` directly.<br>`settingsState` (:3764) sends `link` nil while Auto runs, plus `autoQuality` and `autoCaptureScale` to takers.<br>`onClientHello` (:749) adds takers and publishes; disconnect removes them.<br>Stats keys: `auto.live`, `auto.restart`. |
| `Sources/SillHost/AwayPolicy.swift` | `awayLine` / `homeLine` name "Auto" for an Auto pair. |
| `Sources/SillHostCLI` | `--auto-quality` sets both pairs to `.auto`. |

## Wire (StreamProtocol): optional only

| type | field | sent / read |
|---|---|---|
| `Hello` (Compatibility.swift:104) | `autoQuality: Int?` | 1 from a device that shows Auto. |
| `StreamSettings` (HostSettings.swift:64) | `autoQuality: Bool?` (in `init`, no default) | Host → taker only. Nil from older hosts. `bitrate` is always the running preset. |
| `HostSettingsChange` (:243) | `autoQuality: Bool?` (+ `isEmpty`, `applied(to:)`) | Device → host. Only `true` is taken. An older host ignores the key, and the ledger reads a refusal. |
| `HostSettingsState` (:185) | `autoCaptureScale: Double?` | Host → taker, while Auto runs that connection's pair. `link` is nil for everyone while Auto runs. |

No new kind, no new enum case, and `SillProtocol.current` stays 1.

## Sill.app

- **`Sources/SillMenuBar/HostSettings.swift`**
  - New keys `autoQuality` and `awayAutoQuality` (Bool). `bitrate`/`awayBitrate` keep the last fixed
    rate.
  - Registered default: true (`HostConfig.app`).
  - Load: `.auto` if the key is true, else `.fixed(bitrate)`. `save(changedFrom:)` writes both keys.
  - **Migration (decision 1):** an `autoQualityMigration` Int key. While it is below 1, load writes
    `autoQuality = true` and `awayAutoQuality = true`, then sets it to 1. That runs once per Mac,
    whatever was saved, and is idempotent. A later preset pick fixes the rate and sticks.
- **`DebugHooks`:** `-SillSetAfter bitrate=auto` / `awayBitrate=auto`.
- **`SettingsPanes.swift` `StreamingPane` (:437–479):** both Quality pickers tag `BitrateChoice`, with
  "Auto" first.
- **`StatusItemController.swift` (:115):**
  - "Auto" is the Quality submenu's first item, checked under `.auto`.
  - Picking a preset sets `.fixed`.
  - Q7: the subtitle "Balanced now".

## iOS

- **NEW `iOSClient/QualityMenu.swift`:** `items`, `selection`, `label`, `change`.
  - `HostSettingsPanel.qualityPicker` (:579) and `ControlCenterSheet.qualityPicker` (:315) both build
    from it. That removes the two hand-kept copies.
  - Its pbxproj gets four entries by hand.
- **`HostSettingsLedger.swift`:**
  - `fields`: `autoQuality` maps to `.bitrate`, so the one control is one field and either pick
    replaces the other.
  - `only` / `adding` carry it.
  - Rule 9: never send `autoQuality` to a host whose state had it nil.
- **`AwayCopy.swift`:** `AutoCopy.resolutionNotice`. The stream screen shows it for 3 s where
  `streamLine` shows. The callout (:94) needs no change, because the host withholds `link`.
- **`StreamClient.swift` (:2193):** `Hello(…, autoQuality: AutoQuality.wireGeneration)`. The constant
  lives in StreamProtocol, beside `LockedMac.viewGeneration`.
- **`MockCatalog.swift`:** DEBUG mock cases for Auto at Extreme and Auto lowered to Standard.
- **Tips:** none. Auto asks nothing of the user (it is the default), and picking a preset is the
  existing control.

## Scripts

- **`Scripts/sillclient.py`:** `--set autoQuality=true`. `describe` prints "Auto (Balanced · Retina)".
- **`Scripts/pacing/build.sh` `host_files`:** add `AutoQuality`.

## Checks

| check | new / extended | asserts |
|---|---|---|
| `Tests/checks/auto-quality` | **NEW** (`run.sh`, `build.sh` like link-judge's, `main.swift`, `mutants.py`) | See the 11 cases below. |
| `link-judge` | extended | `carriedKbps(of:)` gives the same numbers as before on its existing sequences. |
| `away-quality` | extended | `applying`/`applyingAway` map Auto/fixed; `accepted` takes `true` and refuses `false` or Auto with a bitrate; `validated` leaves `.auto`; `changes(to:)` text; `running(away:auto:)` never above the Mac's Resolution. |
| `away-wire` | extended | A taker's kind 16 has `autoQuality` and `autoCaptureScale`; a non-taker's has neither and its `bitrate` is the running preset; `link` is nil under Auto. |
| `compatibility` (+ mutants) | extended | An old `StreamSettings`, `HostSettingsChange` and `Hello` JSON decodes into the new types, and the new JSON into the old ones; a `Hello` without `autoQuality` makes no taker. |
| `ledger` | extended | Auto and a preset share `.bitrate`; rule 9; a pending Auto pick is answered by `autoQuality: true`. |
| `away-copy` | extended | `QualityMenu` items/selection/label (Auto first only with a non-nil field; a hand-set rate shown, not offered); `resolutionNotice` only for 2 → 1. |

**`auto-quality` cases:**

1. The home start is Extreme · Retina; the away start is Low · Standard.
2. The Retina ladder has Low · Standard under Low · Retina, the Standard ladder has no Retina, and
   the top is Extreme.
3. 3 short seconds of 5 at Ultra with nothing measured goes to Pro, live.
4. 2 short of 5 does nothing.
5. **The start's cap:**
   - At Extreme with 24 Mbps carried: Balanced by restart (≤ 0.7 × 24 at 60 fps).
   - With `startCappedByLink` false: Ultra, live.
   - A second judgement after the cap is one rung, live: Pro with 26 Mbps carried goes to High, not Balanced.
6. Low · Retina behind goes to Low · Standard by restart; nothing below the bottom.
7. 5 clean, loaded seconds climb one rung by restart; 4 do not; 5 clean still seconds do not.
8. A failed climb doubles the hold, capped at 60.
9. **It doesn't blind itself:**
   - `running != rung` judges nothing.
   - After a live step, the shorts from before don't count, but 3 new ones step again.
   - A second `close` with the same pending state returns nil.
10. **Governance:**
    - A home device plus an away device: only the home device's shorts move Auto.
    - All away: one short device moves it down, and a climb needs every device clean.
11. The line texts, word for word.
12. **Simulated links, which set the pacing gates' numbers.** `close` is driven with seconds from a
    one-line link model: taken = min(link, 0.7 × rung), a short second when the offered rate exceeds
    the link. So the gates below are derived, not written by hand. On 24 Mbit/s from Extreme:
    1. cap to Balanced
    2. climb to High (17.5 fits)
    3. climb to Pro (28 does not)
    4. live back to High
    5. Pro's hold doubles 10 → 20 → 40 → 60 s

## The agent-observable tool: live down, restart up

**1. Pacing harness cases** (`Scripts/pacing/run.sh`, no encoder, loopback, `bottleneck.py`).

`main.swift` gains `--auto home|away`. It runs `AutoQuality` on the real `StreamServer`'s
`onSecond`:

- Frame sizes follow the rung: deltas are bitrate × 0.7 / fps, and keyframes scale with the rung.
- A live step changes the sizes from the next frame.
- A restart goes through the harness's existing restart path (`--restart-at`).
- Each step prints `AutoQuality.stepLine`, and `summarize.py` gates on those lines.

| case | link | gates |
|---|---|---|
| `autodown` | 24 Mbit/s, 70 ms, 120 s | The first Auto line comes within 5 s of the first keyframe, is a restart (Q1), and lands at or below Balanced. After that: never above Pro; at least 80 % of the last 60 s at High; climbs into Pro spaced by the hold (case 12's numbers). |
| `autodrift` | 60 → 24 Mbit/s at 30 s | After the start's cap, every step down is "lowered live", one rung each, at least 3 s apart (Ultra → Pro → High). No restart downward. |
| `autoclimb` | `--auto away`, 8 → 200 Mbit/s at 20 s | Every step up is "restarting", at least 5 s apart. Extreme within 60 s of the rise. Never a live raise. |
| `autostill` | 2 Mbit/s, window still 30 s | No climb while still. |

`autodown`, `autodrift` and `autoclimb` go in the gate cases; `autostill` goes in `--full`.

**2. Encoder side (operator-run only, never while Noah streams).** `Scripts/encoder-check/ratelive`
already measured the two properties `lowerBitrate` sets.

- Q1's walk alternative needs one more schedule at 1 s spacing.
- `docs/BUILD-AND-RUN.md` names both.

**3. Person-facing.**

- The Mac's Log window gets `Auto:` lines for each start and step.
- The Stats counters `auto.live`, `auto.restart` and `enc.lowered` show in the once-a-second stats
  line.

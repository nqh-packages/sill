---
name: verify-sill
description: Launch, check, drive, prove, render the state gallery, and bug bash the Sill iOS/iPadOS app (`com.uxheavy.sill`, `iOSClient/Sill.xcodeproj`). Use before claiming any Sill UI or workspace behavior change works, when asked to verify or screenshot a Sill screen, or to bug bash a flow.
---

# Verify Sill (iOS / iPadOS)

Primary surface: **Sill iOS / iPadOS app** (`com.uxheavy.sill`, project `iOSClient/Sill.xcodeproj`, scheme `Sill`). Secondary surface (macOS host `Sill.app` / `SillHost`): verified separately via `swift build -c release`, `Tests/checks/run-all.sh`, and headless `SillHost --synthetic` + `Scripts/sillclient.py` (see `docs/BUILD-AND-RUN.md`).

Drive lanes in decision-tree order:
1. **Lane 1 — Revyl cloud devices from CI** *(needs one-time setup — no Sill app or `.revyl/config.yaml` exists yet; CLI is authenticated)*: off-machine PR smoke once configured.
2. **Lane 2 — e2e tests (`Tests/e2e/`)** *(primary runnable lane)*: TypeScript tests (`@e2e-dev/mobile`, exact locators, no model) on an iPad and an iPhone simulator, driven through Sill's deterministic DEBUG `LayoutHarness` launch arguments (`-SillLayout`, `-SillConnectCase`, `-SillIdiom`, `-SillDrawer`, `-SillSettings`, `-SillSettingsCase`, `-SillActive`, `-SillFullScreen`). Maestro was removed from this Mac (Huy, 2026-11-24): never install or use it. argent was benchmarked against e2e and lost as the verify lane (its simulator runner cannot see SwiftUI controls; `docs/evidence/e2e-vs-argent/BENCH.md`); `Tests/argent/` keeps its port.
3. **Lane 3 — Local runner (`Tests/checks/tactile-workspace/run.sh`, `Tests/checks/run-all.sh`, T3 `device_open` / `agent-device`, `Scripts/render-states.sh`)**: pure state-machine assertions (<2 s), exact timed coordinate pans/drags, live loopback streaming against `SillHost --synthetic`, and HTML state gallery generation.

Never touch the Mac's hardware video encoder while Noah streams (see `CLAUDE.md`, "Steps"). Lanes 1 and 2 and the gallery never touch it (mock harness, still screenshots), so they need no check for a stream; every headless host test in Lane 3 uses `SILL_TEST_LOOPBACK=1 SILL_TEST_SOFTWARE_ENCODER=1 SILL_TEST_NO_ROUTER=1 SILL_TEST_NO_SCREEN=1`.

## Launch

### Lane 1 — Revyl cloud (once configured)
One-time setup (user's call): create the Sill iOS app in Revyl (`revyl app create`), add `.revyl/config.yaml`, set CI secret `REVYL_API_KEY` and variables `REVYL_IOS_APP_ID` / `WORKFLOW_ID`, and add an upload+run step to `.github/workflows/ci.yml`:
```bash
xcodebuild -project iOSClient/Sill.xcodeproj -scheme Sill \
  -destination 'generic/platform=iOS Simulator' -configuration Debug \
  -derivedDataPath /tmp/sill-revyl-dd CODE_SIGN_IDENTITY="-" DEVELOPMENT_TEAM="" ARCHS=arm64 build
revyl build upload /tmp/sill-revyl-dd/Build/Products/Debug-iphonesimulator/Sill.app \
  --app "$REVYL_IOS_APP_ID" --json
revyl workflow run "$WORKFLOW_ID" --ios-build-id "<build-id>" --json
```
*Limit:* Revyl cloud cannot reach a local loopback `SillHost`.

### Lane 2 — e2e (primary)
Simulators: this lane taps, so it cannot use the agents' photo pair (`Sill agents …`, `Scripts/harness-photos.sh` never taps), and CLAUDE.md's rule against an agent's own simulator "for photos" does not cover it: this lane and its state gallery (`Scripts/render-states.sh`) run on simulators of your own, without asking. Create your own, one iPad and one iPhone (Huy, 2026-11-24), slim each right after it boots, boot only what the run needs (one target's simulator for tests; both for the state gallery), and delete both at Cleanup. Never boot or drive a simulator another session made.
```bash
IPAD_UDID="$(xcrun simctl create "verify-sill iPad" com.apple.CoreSimulator.SimDeviceType.iPad-Pro-11-inch-M5-12GB com.apple.CoreSimulator.SimRuntime.iOS-27-3)"
PHONE_UDID="$(xcrun simctl create "verify-sill iPhone" com.apple.CoreSimulator.SimDeviceType.iPhone-17-Pro com.apple.CoreSimulator.SimRuntime.iOS-27-3)"
xcrun simctl boot "$IPAD_UDID" && xcrun simctl bootstatus "$IPAD_UDID" -b && simslim on "$IPAD_UDID"

xcodebuild -project iOSClient/Sill.xcodeproj -scheme Sill \
  -destination 'generic/platform=iOS Simulator' -configuration Debug \
  -derivedDataPath /tmp/sill-tactile-dd CODE_SIGNING_ALLOWED=NO build
xcrun simctl install "$IPAD_UDID" /tmp/sill-tactile-dd/Build/Products/Debug-iphonesimulator/Sill.app   # and on each simulator you boot
(cd Tests/e2e && pnpm install)
export SILL_E2E_IPAD="verify-sill iPad" SILL_E2E_PHONE="verify-sill iPhone"
```
The e2e targets name their simulators: `ipad` (`SILL_E2E_IPAD`) and `phone` (`SILL_E2E_PHONE`), defaults in `Tests/e2e/e2e.config.ts`. Each test relaunches `com.uxheavy.sill` with its own arguments (`Tests/e2e/tests/launch.ts`) — no live Mac, no network, no screen recording prompt, no hardware encoder. A T3 Device panel session holds its simulator: `device_close` it before an e2e run (`ENGINE_FAILURE … owned by session`).

### Lane 3 — Local interactive / loopback host
- Interactive simulator inspection in T3 Code: call `device_list` → `device_open` → use the returned `agent-device` command (`open com.uxheavy.sill --relaunch --launch-args -SillLayout --launch-args 834x1194`).
- Live loopback stream (when verifying real video/input end-to-end without touching Screen Recording or the hardware encoder):
  ```bash
  swift build -c release
  SILL_TEST_LOOPBACK=1 SILL_TEST_SOFTWARE_ENCODER=1 SILL_TEST_NO_ROUTER=1 SILL_TEST_NO_SCREEN=1 \
    .build/release/SillHost --synthetic
  ```
  Read `<PORT>` from `SillHost`'s stdout (it logs the loopback port on startup; CLI logs go to stdout, whereas `~/Library/Logs/Sill/Sill.log` is `Sill.app`'s log). Verify headlessly with `python3 Scripts/sillclient.py <PORT> 8 desktop`, or launch the simulator app with `-SillConnect 127.0.0.1:<PORT>`.

## Doctor

Run before driving, and again after any failed drive:

- **Lane 1 (Revyl):**
  ```bash
  revyl auth status                # never prints the full key
  revyl device list --json         # confirm no orphaned cloud sessions
  ```
- **Lane 2 & 3 (Local simulators + pure checks):**
  ```bash
  sysctl -n vm.loadavg                                          # refuse heavy local runs if 1-min load > 8
  simslim list --booted                                         # your simulator booted and "slim"
  Tests/checks/tactile-workspace/run.sh                         # pure workspace state machine (~1 s)
  Tests/checks/repo-rules/run.sh                                # repo hygiene rules
  (cd Tests/e2e && pnpm exec e2e doctor)                        # config, agent-device, the targets' simulators, the app
  (cd Tests/e2e && pnpm exec e2e run --target ipad tests/smoke.e2e.ts)
  ```
  Exit `0` on all of them proves the state machine, the simulator, the installed app launching into `LayoutHarness`, and the floating chrome's accessible controls (`Apps`, `Text size`, `Keyboard`, `Trackpad`, `Controls`, `Minimize controls`). `e2e doctor` reports `no model configured`: expected, the tests have no agent steps. A simulator whose test runner stops answering ("Runner did not accept connection", or a hierarchy dump that hangs) is rebooted (`simctl shutdown` then `boot`) before the next drive.

## Drive

### Lane 2 — e2e (primary)
Which test covers a change: `features/README.md` maps each feature to its test, and a feature's file says what the test proves. The floating dock (the capsule, its orb, the Aa pill, the floating trackpad) is `pad-pencilkit-chrome` on the iPad and `phone-workspace` on the iPhone; the switcher `switcher-and-controls`; Control Center `control-center`; the connect screen `connect-screen`. A behaviour no test covers gets a test in `Tests/e2e/tests/` before it is claimed.

One target per run, with its simulator booted; results in `Tests/e2e/.e2e/results/<test>/` (trace, screenshots):
```bash
cd Tests/e2e
pnpm exec e2e run --target ipad --tag ipad      # smoke, pad-pencilkit-chrome, switcher-and-controls, connect-screen
pnpm exec e2e run --target phone --tag phone    # phone-workspace, control-center
pnpm exec e2e run --target ipad tests/connect-screen.e2e.ts   # one file
```
Locators match whole strings and fail on two matches: use `.first()` where a label repeats (feature files name them), `getByRole('button', { name })` for a row whose value is part of its label (`Quality, Auto`). `await screen.debug()` prints the tree.

### Lane 3 — Local interactive & pure checks
- Pure logic & state transitions: `Tests/checks/tactile-workspace/run.sh` (workspace state machine) and `Tests/checks/run-all.sh` (full CI pure-check suite).
- Exact timed coordinate drags or live inspection: use T3 Code `device_open`'s `agent-device` (`gesture pan x y dx dy durationMs`, `press x y`, `screenshot <path>`).
- Hardware-device install check: `xcrun devicectl device install app --device <UDID> /tmp/sill-tactile-device-dd/Build/Products/Debug-iphoneos/Sill.app`.

## Evidence

- **Lane 1 (Revyl):** `report_link` from `--json`, cloud recording, and screenshots.
- **Lane 2 (e2e):** exit code, the run's summary, and `Tests/e2e/.e2e/results/<test>/` (`trace.md`, `attempt-N/screenshots/*.png`, `screen-at-failure.txt`). A later run replaces a test's folder: copy what must be kept first.
- **Lane 3 (Local):** `Tests/checks/tactile-workspace/run.sh` pass count, `Tests/checks/repo-rules/run.sh` output, `agent-device` screenshots, and `.e2e/states/index.html`.
- **Proof standards:**
  - Exercise the real user path (tap labeled buttons, drag chrome, swipe deck — never internal test-only setters).
  - Capture both the action and the resulting state (screenshots and `toBeVisible` / `toBeHidden`).
  - Side-effect stores on iOS/macOS when testing live sessions:
    - iOS app preferences: `xcrun simctl spawn <UDID> defaults read com.uxheavy.sill`
    - Cached stream previews: simulator app container `Library/Caches/SillPreviews/`
    - Saved Macs / pairing identity: iOS Keychain (`SavedMacs.swift`, `DeviceIdentity.swift`)
    - macOS host log & prefs: `~/Library/Logs/Sill/Sill.log` and `defaults read me.saffer.sill.mac`
  - Mock boundary: `LayoutHarness` + `MockCatalog` isolates network/ScreenCaptureKit/encoder cleanly for UI behavior; live streaming proofs use headless `SillHost --synthetic` on `127.0.0.1` with `SILL_TEST_NO_SCREEN=1`.

## State gallery

One script renders every reachable screen and component state (empty/looking, typical, overloaded `methods`, permission denied `denied`, version/remote errors, `Aa`-disabled Desktop, `SillActive=none`, full-screen hint, iPad floating chrome bottom + vertical rail + corner orb, iPhone capsule + Control Deck + Switcher, Quality on Auto, and **Dynamic Type XXXL** accessibility text) into one browsable HTML sheet, through the e2e gallery (`Tests/e2e/tests/gallery.e2e.ts`, one row per state). It **does not build or install the app** (run Lane 2's `xcodebuild` + `simctl install` first after code changes), and it **never records video or touches the Mac's hardware encoder** (still PNGs only):

```bash
Scripts/render-states.sh --ipad "verify-sill iPad" --phone "verify-sill iPhone"
# Renders whichever of the two is booted, and each run replaces the whole gallery: boot both for a full sheet; --force past load 8
```

- Output, at the repository root: `.e2e/states/index.html` and `.e2e/states/frames/<component>-<state>[-xl].png` (gitignored; each render replaces it, and its `manifest.tsv` lists the frames).
- Dynamic Type XXXL frames are the iPad's connect screen and Control Center only (`gallery-ipad-xl`). For any other screen or the iPhone at XXXL: `xcrun simctl ui <UDID> content_size accessibility-extra-extra-extra-large`, run that screen's test or open it with its launch arguments and screenshot it, then set `content_size large` again.
- Visually inspect every frame — check overloaded and `-xl` frames first for truncation, clipping, or overlapping chrome.
- *Unreachable / skipped states:* light mode is skipped because Sill enforces `.preferredColorScheme(.dark)` globally in `ContentView.swift`; StoreKit / real tip-jar sheets are skipped on simulator; RTL is not localized yet.

## Bug bash

Charters live in [features/](features/) (one file per user-facing feature, formatted as `slug|target|agent|charter`).
- **Status of automated `e2e explore`:** e2e is installed in `Tests/e2e/`, but `explore` needs a model for its agent steps and none is configured (`e2e doctor`: "no model configured"), so automated bug-bash exploration is **unproven**. Configuring one is Huy's choice (`Tests/e2e/node_modules/e2e/docs/models.mdx`); then run charters from `features/*.md`.
- **Verification bar (regardless of runner):** A finding is a confirmed bug only when a deterministic e2e test (`Tests/e2e/tests/bugbash-<slug>.e2e.ts`) or pure state-machine test in `Tests/checks/tactile-workspace/main.swift` fails on the assertion encoding the bug.
- **Not bugs in mock harness:** black video backdrop when streaming mock windows (mock has no HEVC frames unless `-SillPointer` is set); `Not paired` on local real Mac rows when launched without `-SillLayout`.

## Cleanup

- Stop only processes and Revyl sessions **this run started** (by PID or Revyl session ID — never `pkill` by process name).
- If you changed simulator Dynamic Type (`xcrun simctl ui <UDID> content_size ...`), restore it to `large` (`Scripts/render-states.sh` does this automatically via `trap EXIT`).
- Remove temporary `/tmp/sill-*` scratch files; **never delete** `.e2e/states/` or results you are citing (that is the kept evidence).
- Shut down and delete the simulators this run created (`xcrun simctl shutdown`, `xcrun simctl delete`), after `device_close` for any you opened in the Device panel.

## Helpers

- `Scripts/render-states.sh` — builds the full HTML state gallery at `.e2e/states/index.html`.
- `Tests/checks/tactile-workspace/run.sh` — pure Swift state-machine check for `StreamWorkspaceState.swift`.
- `Tests/e2e/` — the e2e project: `e2e.config.ts` (targets `ipad`, `phone`), `tests/*.e2e.ts`, `tests/launch.ts` (launch arguments per layout), `tests/gallery.e2e.ts` (the gallery's states). `pnpm exec e2e --help` there.
- `revyl` (`/Users/nqh/.local/bin/revyl`) — Lane 1 cloud simulator CLI (once app/workflow configured).

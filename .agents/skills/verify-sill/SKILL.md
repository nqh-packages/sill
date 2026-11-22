---
name: verify-sill
description: Launch, check, drive, prove, render the state gallery, and bug bash the Sill iOS/iPadOS app (`com.uxheavy.sill`, `iOSClient/Sill.xcodeproj`). Use before claiming any Sill UI or workspace behavior change works, when asked to verify or screenshot a Sill screen, or to bug bash a flow.
---

# Verify Sill (iOS / iPadOS)

Primary surface: **Sill iOS / iPadOS app** (`com.uxheavy.sill`, project `iOSClient/Sill.xcodeproj`, scheme `Sill`). Secondary surface (macOS host `Sill.app` / `SillHost`): verified separately via `swift build -c release`, `Tests/checks/run-all.sh`, and headless `SillHost --synthetic` + `Scripts/sillclient.py` (see `docs/BUILD-AND-RUN.md`).

Drive lanes in decision-tree order:
1. **Lane 1 — Revyl cloud devices from CI** *(needs one-time setup — no Sill app or `.revyl/config.yaml` exists yet; CLI is authenticated)*: off-machine PR smoke once configured.
2. **Lane 2 — Maestro flows (`.maestro/*.yaml`)** *(primary runnable lane today)*: declarative, repeatable UI behavior tests on booted iPad/iPhone simulators using Sill's deterministic DEBUG `LayoutHarness` launch arguments (`SillLayout`, `SillConnectCase`, `SillIdiom`, `SillDrawer`, `SillSettings`, `SillActive`).
3. **Lane 3 — Local runner (`Tests/checks/tactile-workspace/run.sh`, `Tests/checks/run-all.sh`, T3 `device_open` / `agent-device`, `Scripts/render-states.sh`)**: pure state-machine assertions (<2 s), exact timed coordinate pans/drags, live loopback streaming against `SillHost --synthetic`, and HTML state gallery generation.

Never touch the Mac's hardware video encoder while Noah streams (see `CLAUDE.md`, "Steps"): every headless host test uses `SILL_TEST_LOOPBACK=1 SILL_TEST_SOFTWARE_ENCODER=1 SILL_TEST_NO_ROUTER=1 SILL_TEST_NO_SCREEN=1`.

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
*Limit:* Revyl cloud cannot reach a local loopback `SillHost`, and Revyl's Maestro runner passes `--launch-env` rather than arbitrary `-SillLayout` process arguments.

### Lane 2 — Maestro (primary runnable lane today)
Resolve the booted simulator UDIDs, then build and install the Debug simulator `.app` once per code change:
```bash
IPAD_UDID="$(xcrun simctl list devices booted | awk -F '[()]' '/iPad/ {print $2; exit}')"
PHONE_UDID="$(xcrun simctl list devices booted | awk -F '[()]' '/iPhone/ {print $2; exit}')"

xcodebuild -project iOSClient/Sill.xcodeproj -scheme Sill \
  -destination 'generic/platform=iOS Simulator' -configuration Debug \
  -derivedDataPath /tmp/sill-tactile-dd \
  CODE_SIGN_IDENTITY="-" DEVELOPMENT_TEAM="" ARCHS=arm64 build
xcrun simctl install "$IPAD_UDID" /tmp/sill-tactile-dd/Build/Products/Debug-iphonesimulator/Sill.app
xcrun simctl install "$PHONE_UDID" /tmp/sill-tactile-dd/Build/Products/Debug-iphonesimulator/Sill.app
```
Maestro launches `com.uxheavy.sill` directly with `arguments:` (`SillLayout`, `SillConnectCase`, `SillIdiom`, etc.) — no live Mac, no network, no screen recording prompt, and no hardware encoder needed.

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

Run before driving whenever anything looks off:

- **Lane 1 (Revyl):**
  ```bash
  revyl auth status                # never prints the full key
  revyl device list --json         # confirm no orphaned cloud sessions
  ```
- **Lane 2 & 3 (Local simulators + pure checks):**
  ```bash
  sysctl -n vm.loadavg                                          # refuse heavy local runs if 1-min load > 8
  xcrun simctl list devices booted | grep -E "iPad|iPhone"      # confirm target simulator UDID(s) are booted
  Tests/checks/tactile-workspace/run.sh                         # pure workspace state machine (98 checks, ~1 s)
  Tests/checks/repo-rules/run.sh                                # repo hygiene rules
  maestro --device "$IPAD_UDID" test .maestro/smoke.yaml --debug-output .e2e/proof/doctor-smoke
  ```
  Exit `0` on `tactile-workspace`, `repo-rules`, and `.maestro/smoke.yaml` proves the state machine compiles, the simulator app launches into `LayoutHarness`, and the primary PencilKit chrome renders its accessible controls (`Apps`, `Text size`, `Keyboard`, `Trackpad`, `Controls`, `Minimize controls`).
  *Shared simulator rule:* never boot or erase a simulator another session owns; check `xcrun simctl list devices booted` first and drive only the target UDID.

## Drive

### Lane 2 — Maestro flows (primary)
Run one feature flow or the full suite, keeping screenshots in `.e2e/proof/<run>/`:
```bash
# iPad PencilKit 4-edge / 4-corner chrome + floating trackpad
maestro --device "$IPAD_UDID" test .maestro/pad-pencilkit-chrome.yaml \
  --debug-output .e2e/proof/pad-pencilkit-chrome

# Unified Switcher (Desktop + Windows) & Control Center sheet
maestro --device "$IPAD_UDID" test .maestro/switcher-and-controls.yaml \
  --debug-output .e2e/proof/switcher-and-controls

# Connect screen discovery & Add a Mac sheet
maestro --device "$IPAD_UDID" test .maestro/connect-screen.yaml \
  --debug-output .e2e/proof/connect-screen

# iPhone portrait Focus dock, Control Deck & Control Center
maestro --device "$PHONE_UDID" test .maestro/phone-workspace.yaml \
  --debug-output .e2e/proof/phone-workspace
```
All flows use real accessibility labels verified from source (`Apps`, `Text size`, `Keyboard`, `Trackpad`, `Controls`, `Minimize controls`, `Stow trackpad`, `Move the trackpad`, `Close the trackpad`, `Add a Mac`, `Reconnect automatically`, `Cancel`, `Desktop`, `Mac mini`).

### Lane 3 — Local interactive & pure checks
- Pure logic & state transitions: `Tests/checks/tactile-workspace/run.sh` (workspace state machine) and `Tests/checks/run-all.sh` (full CI pure-check suite).
- Exact timed coordinate drags or live inspection: use T3 Code `device_open`'s `agent-device` (`gesture pan x y dx dy durationMs`, `press x y`, `screenshot <path>`).
- Hardware-device install check: `xcrun devicectl device install app --device <UDID> /tmp/sill-tactile-device-dd/Build/Products/Debug-iphoneos/Sill.app`.

## Evidence

- **Lane 1 (Revyl):** `report_link` from `--json`, cloud recording, and screenshots.
- **Lane 2 (Maestro):** exit code + timestamped output folder under `.e2e/proof/<name>/` (contains `commands-*.json`, logs, and every named `takeScreenshot` PNG). Never overwrite `.e2e/proof/<name>/` with a subsequent Doctor run.
- **Lane 3 (Local):** `Tests/checks/tactile-workspace/run.sh` pass count, `Tests/checks/repo-rules/run.sh` output, `agent-device` screenshots, and `.e2e/states/index.html`.
- **Proof standards:**
  - Exercise the real user path (tap labeled buttons, drag chrome, swipe deck — never internal test-only setters).
  - Capture both the action and the resulting state (before/after screenshots and `assertVisible` / `assertNotVisible`).
  - Side-effect stores on iOS/macOS when testing live sessions:
    - iOS app preferences: `xcrun simctl spawn <UDID> defaults read com.uxheavy.sill`
    - Cached stream previews: simulator app container `Library/Caches/SillPreviews/`
    - Saved Macs / pairing identity: iOS Keychain (`SavedMacs.swift`, `DeviceIdentity.swift`)
    - macOS host log & prefs: `~/Library/Logs/Sill/Sill.log` and `defaults read com.uxheavy.sill.mac`
  - Mock boundary: `LayoutHarness` + `MockCatalog` isolates network/ScreenCaptureKit/encoder cleanly for UI behavior; live streaming proofs use headless `SillHost --synthetic` on `127.0.0.1` with `SILL_TEST_NO_SCREEN=1`.

## State gallery

One script renders every reachable screen and component state (empty/looking, typical, overloaded `methods`, permission denied `denied`, version/remote errors, `Aa`-disabled Desktop, `SillActive=none`, full-screen hint, iPad PencilKit bottom + vertical rail + corner orb, iPhone Focus + Control Deck + Switcher, and **Dynamic Type XXXL** accessibility text) into one browsable HTML sheet. It **does not build or install the app** (run Lane 2's `xcodebuild` + `simctl install` first after code changes), and it **never records video or touches the Mac's hardware encoder** (still Maestro PNGs only):

```bash
Scripts/render-states.sh
# Auto-detects booted iPad & iPhone simulators, or pass explicit UDIDs / --force if load > 8:
# Scripts/render-states.sh --ipad-udid "$IPAD_UDID" --phone-udid "$PHONE_UDID"
```

- Output: `.e2e/states/index.html` and `.e2e/states/frames/<component>-<state>[-xl].png` (gitignored, not cleared by `.maestro` proof runs).
- Visually inspect every frame — check overloaded and `-xl` frames first for truncation, clipping, or overlapping chrome.
- *Unreachable / skipped states:* light mode is skipped because Sill enforces `.preferredColorScheme(.dark)` globally in `ContentView.swift`; StoreKit / real tip-jar sheets are skipped on simulator; RTL is not localized yet.

## Bug bash

Charters live in [features/](features/) (one file per user-facing feature, formatted as `slug|target|agent|charter`).
- **Status of automated `e2e explore`:** The `e2e` CLI (`e2e.config.ts`) is **not installed** in this repository yet, so automated AI bug-bash exploration is currently **unproven**. To enable it later, run `npx e2e init`, configure `@e2e-dev/mobile` against `com.uxheavy.sill`, and run charters from `features/*.md` into `.e2e/bugbash/<slug>` (already gitignored).
- **Verification bar (regardless of runner):** A finding is a confirmed bug only when a deterministic Maestro flow (`.maestro/bugbash-<slug>.yaml`) or pure state-machine test in `Tests/checks/tactile-workspace/main.swift` fails on the assertion encoding the bug.
- **Not bugs in mock harness:** black video backdrop when streaming mock windows (mock has no HEVC frames unless `-SillPointer` is set); `Not paired` on local real Mac rows when launched without `-SillLayout`.

## Cleanup

- Stop only processes and Revyl sessions **this run started** (by PID or Revyl session ID — never `pkill` by process name).
- If you changed simulator Dynamic Type (`xcrun simctl ui <UDID> content_size ...`), restore it to `large` (`Scripts/render-states.sh` does this automatically via `trap EXIT`).
- Remove temporary `/tmp/sill-*` scratch flows; **never delete** `.e2e/proof/` or `.e2e/states/` (that is the kept evidence).

## Helpers

- `Scripts/render-states.sh` — builds the full HTML state gallery at `.e2e/states/index.html`.
- `Tests/checks/tactile-workspace/run.sh` — pure Swift state-machine check for `StreamWorkspaceState.swift`.
- `maestro` (`/opt/homebrew/bin/maestro`) — runs `.maestro/*.yaml` behavioral flows.
- `revyl` (`/Users/nqh/.local/bin/revyl`) — Lane 1 cloud simulator CLI (once app/workflow configured).

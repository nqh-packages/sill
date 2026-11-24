# Benchmark: `e2e` vs `argent` on Sill's iOS Verify Suite

**Verdict:** **`argent` 0.34.0 is ~2.6× faster on iPad wall time** (median `44.39 s` vs `115.71 s`, or ~1.9× faster excluding the switcher hang and teardown timeout), **and ~2.7× faster on iPhone** (median `19.10 s` vs `51.66 s`), with cleaner failure screenshots on hung apps and zero multi-agent session collisions. **However, `verify-sill` should keep `e2e` (`@e2e-dev/mobile`) as its primary Lane 2 runner**, because `argent 0.34.0`'s iOS simulator e2e runner projects only the UIKit `UIView` hierarchy (`native-full-hierarchy`) rather than the accessibility tree (`ax-service` / `native-describe-screen`) — making pure SwiftUI controls invisible to declarative YAML selectors and forcing hardcoded screen coordinates for every tap and drag.

---

## 1. Test Environment & Methodology

- **Checkout:** Sill branch `test/e2e-vs-argent-bench` from commit `7b97adfb` (product code untouched).
- **App under test:** Pre-built Debug simulator bundle `/tmp/sill-corners-dd/Build/Products/Debug-iphonesimulator/Sill.app` (`com.uxheavy.sill`, version `0.6.3` build `7`), installed identically on both simulators.
- **Simulators (created fresh, slimmed with `simslim on <udid>` after first boot, only one booted at a time, shut down and deleted at completion):**
  - `arena-c2 iPad` — iPad Pro 11-inch (M5) (`com.apple.CoreSimulator.SimDeviceType.iPad-Pro-11-inch-M5-12GB`), runtime `com.apple.CoreSimulator.SimRuntime.iOS-27-3` (`173/173 slim`).
  - `arena-c2 iPhone` — iPhone 17 Pro (`com.apple.CoreSimulator.SimDeviceType.iPhone-17-Pro`), runtime `com.apple.CoreSimulator.SimRuntime.iOS-27-3` (`173/173 slim`).
- **Tools:**
  - `e2e` `0.24.0` + `@e2e-dev/mobile` `0.12.8` (`agent-device` `0.21.39`), Node.js `26.13.1`, installed in `Tests/e2e/`.
  - `argent` `0.34.0`, global install, driving the shared `tool-server` (`http://127.0.0.1:62950`) with explicit `--device <UDID>` on every invocation.
- **Suite:** All 6 deterministic verify tests from `Tests/e2e/tests/` using identical `-SillLayout` launch arguments (`-SillLayout 834x1194` on iPad; `-SillLayout 402x874 -SillIdiom phone` on iPhone; plus `-SillConnectCase methods` and `-SillSettings 1 -SillSettingsCase auto`). Between repeats, `xcrun simctl terminate <UDID> com.uxheavy.sill` cleared any leftover spinning Sill process from the known Unified Switcher CPU bug so one repeat could not steal CPU from the next.
- **Shared-host load gating:** This 10-core Mac (`hw.ncpu = 10`) ran concurrent workloads (another arena candidate, a VM, Playwright/Swift builds). Every timed run checked `sysctl -n vm.loadavg` before starting and waited when 1-minute load exceeded `12.0` (full wait log in `docs/evidence/e2e-vs-argent/logs/load-waits.log`).

---

## 2. The `argent` Port (`Tests/argent/`)

Because `argent` 0.34.0 has no `--tag` flag and its `requires:` block only filters `platform` (`ios`) and `runtimeKind` (`mobile` | `tv`) — not iPad vs iPhone — the 6 tests are organized by target simulator so each directory runs cleanly as a batch:

- `Tests/argent/ipad/smoke.yaml` ← `Tests/e2e/tests/smoke.e2e.ts`
- `Tests/argent/ipad/pad-pencilkit-chrome.yaml` ← `Tests/e2e/tests/pad-pencilkit-chrome.e2e.ts`
- `Tests/argent/ipad/switcher-and-controls.yaml` ← `Tests/e2e/tests/switcher-and-controls.e2e.ts`
- `Tests/argent/ipad/connect-screen.yaml` ← `Tests/e2e/tests/connect-screen.e2e.ts`
- `Tests/argent/phone/phone-workspace.yaml` ← `Tests/e2e/tests/phone-workspace.e2e.ts`
- `Tests/argent/phone/control-center.yaml` ← `Tests/e2e/tests/control-center.e2e.ts`

### Crucial gap: SwiftUI views are invisible to `argent` 0.34.0's iOS simulator YAML selectors

When we first wrote idiomatic declarative YAML (`await: { visible: { text: { matches: '^Apps$' } } }`, `tap: { text: ... }`), every test failed immediately with `no element matched selector`. Inspecting both the live simulator trees and `argent`'s own `tool-server.cjs` (`projectIosNode` / `adaptFullHierarchy`, lines 177942–178050) proved why:

| Tree / Tool | Source on iOS Simulator | What it sees on Sill (pure SwiftUI) |
| --- | --- | --- |
| `argent e2e` declarative directives (`await`, `assert`, `tap`, `swipe.from`, `scroll-to`) | `native-full-hierarchy` (UIKit `UIView` hierarchy via injected ViewInspector) | Only UIKit-backed wrappers: `Sill.MacMenuTriggerButton` (`"Code menus"`), `UILabel "Sill"`, `UIPasteControl "Paste"`, `UISegment`s, and `UILabel "Auto"` (without `"Quality"`). **All pure SwiftUI buttons/text inside `SwiftUI._UIInheritedView` are absent.** |
| `argent run describe` / `tool: await-ui-element` | `ax-service` (accessibility tree) | **Every SwiftUI element** with role, label, value, identifier, and normalized `[0,1]` frame (`AXButton "Apps"`, `AXButton "Quality, Auto"`, `AXButton "Add a Mac"`, `AXStaticText "Move the trackpad"`, etc.). |
| `argent run native-describe-screen` | Injected accessibility walk | Same complete SwiftUI accessibility tree as `describe` — not wired into the iOS simulator YAML runner (though physical iOS devices *do* use the `describe` tree via `projectIosDeviceNode`). |
| `e2e` (`@e2e-dev/mobile`) | `agent-device` accessibility snapshot (`snapshot-bridge` / XCTest) | **Every SwiftUI element**, directly queryable by `getByText`, `getByRole`, `getByTestId`, `.first()`, `boundingBox()`, and `scrollUntilVisible`. |

### Exact substitutions used in `Tests/argent/`

Following `argent-create-e2e/references/reliability-and-recovery.md` ("tree-free form"):

1. **Visibility & hidden assertions (`toBeVisible` / `toBeHidden`)** → `tool: await-ui-element` with `condition: visible` / `hidden`, `selector: { role, text, identifier? }`, and `timeoutMs: 5000` (or `10000` for `-SillSettings 1`). Verified live that `tool: await-ui-element` fails the YAML step, captures a failure screenshot, and exits non-zero when `success: false`.
2. **Taps (`locator.tap()`)** → normalized `[0,1]` coordinate `tap: { x, y }` derived from `argent run describe`, prefixed by an `echo:` naming the target.
3. **Sheet/modal settle before tapping** → explicit `await: { idle: true }` after `Add a Mac` (`Cancel`), `Controls` (`Full Screen`), `Menus` (`File`), and `-SillSettings 1` (`Streaming`). Without it, `tap: { x, y }` fired mid-sheet-presentation animation (verified on `connect-screen` dry-run where tapping `Cancel` missed the animating button). `e2e` handles this automatically via its default `transition: 500` ms guard.
4. **Dock drag (`boundingBox()` + point `screen.swipe`)** → hardcoded normalized `swipe: { from: { x: 0.716, y: 0.962 }, to: { x: 0.983, y: 0.496 }, duration: 500 }`, because `from: { text: Minimize controls }` cannot resolve SwiftUI views.
5. **Scroll to element (`screen.scrollUntilVisible`)** → explicit momentum-free coordinate swipes (`swipe: { from: { x: 0.500, y: 0.650 }, to: { x: 0.500, y: 0.150 }, duration: 400, momentum: false }` followed by `y: 0.650 -> 0.250`) to expand the half-sheet and scroll past the `Text size` slider (swiping from `y=0.85` landed on the `AXAdjustable "Text size"` slider and adjusted it from `0.5×` to `0.75×` instead of scrolling!).
6. **Passing-test screenshots (`app.screenshot('...')`)** → omitted in `Tests/argent/`. `argent`'s `snapshot:` directive is a baseline-diff assertion (fails without committed baselines), and raw `tool: screenshot` does not export named PNGs into `--output <dir>` and clears the iOS launch pin. Only failure screenshots (`step-<n>-screen.png`) are written to `--output`.

---

## 3. Benchmark Results

### Exact commands

```bash
# e2e (run from Tests/e2e/ with SILL_E2E_IPAD="arena-c2 iPad" SILL_E2E_PHONE="arena-c2 iPhone")
pnpm exec e2e run --target ipad --tag ipad --output .e2e/bench-ipad-r<N>
pnpm exec e2e run --target phone --tag phone --output .e2e/bench-phone-r<N>

# argent (run from repo root with explicit simulator UDID)
argent e2e run Tests/argent/ipad --device D8F0AADC-F39D-43DE-918F-FFAF7647328B --output /tmp/argent-ipad-r<N> --json
argent e2e run Tests/argent/phone --device 005A082C-C2F8-4CE5-97A9-531473353CA6 --output /tmp/argent-phone-r<N> --json
```

### `e2e` (`0.24.0` / `@e2e-dev/mobile` `0.12.8`)

| Target | Test | Median | Range (3 runs) | R1 | R2 | R3 | Flakes |
| --- | --- | ---: | ---: | --- | --- | --- | ---: |
| iPad | `connect-screen` | **8.98 s** | 8.56–9.20 s | PASS (9.20 s) | PASS (8.98 s) | PASS (8.56 s) | 0 |
| iPad | `pad-pencilkit-chrome` | **15.32 s** | 14.37–15.36 s | PASS (15.32 s) | PASS (15.36 s) | PASS (14.37 s) | 0 |
| iPad | `smoke` | **5.39 s** | 4.97–5.40 s | PASS (5.39 s) | PASS (5.40 s) | PASS (4.97 s) | 0 |
| iPad | `switcher-and-controls` *(known bug)* | **40.41 s** | 39.94–41.07 s | FAIL (41.07 s) | FAIL (40.41 s) | FAIL (39.94 s) | 0 |
| **iPad** | **Suite wall total (incl. engine prep + cleanup)** | **115.71 s** | **112.95–124.42 s** | **3/4 pass, exit 3** (124.42 s) | **3/4 pass, exit 3** (115.71 s) | **3/4 pass, exit 3** (112.95 s) | **0** |
| **iPhone** | **Suite wall total (2 tests, incl. engine prep)** | **51.66 s** | **50.95–53.12 s** | **1/2 pass, exit 1** (53.12 s) | **1/2 pass, exit 1** (50.95 s) | **1/2 pass, exit 1** (51.66 s) | **0** |

The iPhone failure is `control-center` in every repeat: a flaw in the test, not the app (see "Synthesis" below). Per-test iPhone times are in `logs/phone-r*-e2e.report.json`.

**`e2e` iPad run start loads (`sysctl -n vm.loadavg`):**
- R1: `{ 10.46 19.50 29.15 }` (`waited=0s`; engine prep `21.70 s`, runner `101.83 s`, `CLEANUP_TIMEOUT` `+30.85 s`)
- R2: `{ 8.41 15.88 26.39 }` (`waited=0s`; engine prep `14.13 s`, runner `100.97 s`, `CLEANUP_TIMEOUT` `+30.82 s`)
- R3: `{ 11.86 13.99 24.21 }` (`waited=0s`; engine prep `13.52 s`, runner `98.64 s`, `CLEANUP_TIMEOUT` `+30.81 s`)

**`e2e` iPhone run start loads:** R1 `{ 11.38 74.11 131.28 }`, R2 `{ 11.93 44.30 106.25 }`, R3 `{ 10.49 30.68 85.86 }` (`logs/timings.txt`).

### `argent` (`0.34.0`)

| Target | Test | Median | Range (3 runs) | R1 | R2 | R3 | Flakes |
| --- | --- | ---: | ---: | --- | --- | --- | ---: |
| iPad | `connect-screen` | **8.23 s** | 6.96–11.60 s | PASS (11.60 s) | PASS (6.96 s) | PASS (8.23 s) | 0 |
| iPad | `pad-pencilkit-chrome` | **11.36 s** | 10.46–12.39 s | PASS (11.36 s) | PASS (12.39 s) | PASS (10.46 s) | 0 |
| iPad | `smoke` | **3.75 s** | 3.45–3.79 s | PASS (3.79 s) | PASS (3.75 s) | PASS (3.45 s) | 0 |
| iPad | `switcher-and-controls` *(known bug)* | **20.79 s** | 20.06–25.46 s | FAIL (25.46 s) | FAIL (20.79 s) | FAIL (20.06 s) | 0 |
| **iPad** | **Suite wall total** | **44.39 s** | **42.44–53.24 s** | **3/4 pass, exit 1** (53.24 s) | **3/4 pass, exit 1** (44.39 s) | **3/4 pass, exit 1** (42.44 s) | **0** |
| **iPhone** | **Suite wall total (2 tests)** | **19.10 s** | **18.88–24.92 s** | **2/2 pass, exit 0** (24.92 s) | **2/2 pass, exit 0** (18.88 s) | **2/2 pass, exit 0** (19.10 s) | **0** |

Per-test iPhone times are in `logs/phone-r*-argent.report.json`.

**`argent` iPad run start loads (`sysctl -n vm.loadavg`):**
- R1: `{ 11.87 41.15 70.50 }` (after waiting ~10 min while other simulators finished first-boot migration)
- R2: `{ 11.58 21.06 42.55 }` (`waited=0s` after load dipped below 12)
- R3: `{ 11.24 20.95 30.15 }` (`waited=105s` after rebooting `arena-c2 iPad` post-`e2e` wedge; see §4)

**`argent` iPhone run start loads:** R1 `{ 15.62 88.52 140.19 }` (above the 12 gate), R2 `{ 11.74 56.19 117.65 }`, R3 `{ 11.37 32.24 87.71 }` (`logs/timings.txt`).

### Where the time goes (limiter breakdown on iPad)

The `71.3 s` median wall-time gap on iPad (`115.71 s` vs `44.39 s`) decomposes almost exactly (`70.9 s` = 99.4% accounted for):

1. **Post-hang `CLEANUP_TIMEOUT` (`+30.82 s`):** Every `e2e` iPad run hit `ERROR infrastructure error CLEANUP_TIMEOUT (cleanup): disposing the engine timed out` because `switcher-and-controls` left Sill spinning at 100% CPU, adding `30.8 s` and flipping the exit code from `1` to `3`. `argent` exited immediately with code `1` (`0 s` cleanup overhead).
2. **Switcher failure timeout (`+19.62 s`):** `e2e` waited its default `30 s` `--action-timeout` on `getByText("Desktop").first()` (`40.41 s` total); `argent` waited `~15 s` ViewInspector settle on the coordinate tap plus `5 s` `await-ui-element` timeout (`20.79 s` total).
3. **Per-run engine preparation (`+14.13 s`):** Every `e2e` invocation starts `agent-device`, launches `AgentDeviceRunnerUITests` via `xcodebuild test-without-building` (`5.3–13.4 s`), and performs an un-arged warm-up launch of `com.uxheavy.sill` (`4.6–4.9 s`). `argent` reuses a persistent `tool-server` and per-UDID `simulator-server` / `ax-service` (`<0.5 s` CLI startup).
4. **Passing tests (`+6.35 s` across 3 tests: `29.69 s` vs `23.34 s`):** `e2e` runs `~3.2 s` per `device.openApp`, captures 7 explicit `app.screenshot()` PNGs, and applies `transition: 500 ms` animation guards; `argent` launches in `~2.0 s` and captures no passing-step screenshots.

### Cross-tool & concurrency incidents observed (and logged)

Two real operational failures occurred during benchmarking (preserved in `docs/evidence/e2e-vs-argent/logs/` and excluded from the clean 3-run medians above):

1. **`e2e` multi-agent session collision (`ipad-r0-e2e-collision.stdout.txt`):** When Candidate 1 ran `e2e run --target ipad` on its own simulator (`arena-c1 iPad`) at the same time we ran `e2e run --target ipad` on `arena-c2 iPad`, `Tests/e2e/e2e.config.ts` had no per-device `session:` option, so both defaulted to `"e2e-ipad-0"` in the shared `~/.agent-device` daemon. Result: `ENGINE_FAILURE: open com.uxheavy.sill failed: Session "e2e-ipad-0" is already bound to apple device "arena-c1 iPad" (...), but this request selected --device=arena-c2 iPad` — failing 3 tests before `switcher-and-controls` timed out (`exit 3`, `141.3 s`). `argent` ran concurrently on the shared `tool-server` with zero collisions because `--device <UDID>` scopes every session by UDID.
2. **Post-`e2e` `ax-service` wedge on the same simulator (`ipad-r0-argent-post-e2e-ax-wedge.report.json`):** Immediately after `ipad-r1-e2e` hit the switcher hang and `CLEANUP_TIMEOUT`, running `argent` on `arena-c2 iPad` failed all 4 tests with `await-ui-element condition not judged (unreadable): The accessibility read returned no elements`. Rebooting `arena-c2 iPad` via `argent run boot-device --udid <UDID> --force true` (keeping `173/173 slim`) restored `ax-service` immediately, and all subsequent `argent` runs passed 3/4 cleanly. Consecutive `argent`-only runs never wedged `ax-service`.

---

## 4. Ergonomics & Diagnostics Comparison

### Repeated labels (`Cancel`, `Move the trackpad`, `Full Screen`)
- **`e2e`:** Strict by default — matching two nodes throws `LOCATOR_AMBIGUOUS` with the matching nodes and suggests narrowing or `.first()`. Every Sill duplicate is handled explicitly in one token: `getByText('Cancel').first()`, `getByText('Move the trackpad').first()`, `getByText('Full Screen').first()`, `getByText('Menus').first()`.
- **`argent`:** Behavior splits across two mechanisms. In `await-ui-element`, `condition: visible` succeeds if *any* match is visible and `condition: hidden` requires *all* matches to be hidden, so `{ text: Move the trackpad }` (matching both `AXStaticText` and `AXImage`) works for assertions without `.first()`. However, `await-ui-element`'s `text` field is a **case-insensitive substring** (so `{ text: Controls }` also matches `"Minimize controls"`, requiring `identifier: slider.horizontal.3`), and for *tapping* one of two `"Cancel"` buttons (`(0.216, 0.254)` toolbar vs `(0.487, 0.576)` inline), `argent` on SwiftUI cannot select either declaratively and falls back to raw coordinates.

### The `Quality, Auto` button
- **`e2e`:** `await expect(screen.getByRole('button', { name: 'Quality, Auto' })).toBeVisible()` — exact role + full combined accessibility label in one readable line, after `await screen.scrollUntilVisible(screen.getByText('Quality').first())`.
- **`argent`:** In `native-full-hierarchy` (what declarative YAML reads), SwiftUI's menu `Picker("Quality", ...)` exposes only `SwiftUI.UIKitIconPreferringButton label='Auto'` and `UILabel label='Auto'` — the `"Quality"` label is completely missing, so declarative YAML cannot even prove the `"Auto"` label belongs to the Quality row! Dropping to `tool: await-ui-element` with `{ role: AXButton, text: "Quality, Auto" }` *does* verify the exact combined button via `ax-service`, but only after two manually calibrated coordinate swipes that carefully avoid the `AXAdjustable "Text size"` slider at `y=0.80..0.91`.

### Per-test launch arguments
- **`e2e`:** `launch(device, [...ipad, '-SillConnectCase', 'methods'])` via `device.openApp('com.uxheavy.sill', { relaunch: true, launchArguments })`. Sharing base arrays (`ipad`, `phone`) in `tests/launch.ts` prevents typos and keeps all 6 tests DRY. **Caveat:** `e2e`'s target-preparation warm-up opens `com.uxheavy.sill` *without* `-SillLayout` before test 1 runs (`mobile.mdx`: "The warm-up before the run passes neither"), briefly showing the real Bonjour discovery list (nothing is tapped before test 1 relaunches with `-SillLayout`).
- **`argent`:** First-class YAML support via `launch: { ios: { app: com.uxheavy.sill, args: ["-SillLayout", "834x1194", "-SillConnectCase", "methods"] } }` — passes args on the very first launch (no un-arged warm-up!), takes `~2.0 s` vs `e2e`'s `~3.2 s`, and requires repeating the base args in every YAML file (or extracting a `run:` fragment, which does not take parameters).

### The dock drag (`pad-pencilkit-chrome`)
- **`e2e`:** Queries the live element frame dynamically — `const dock = await screen.getByText('Minimize controls').boundingBox(); await screen.swipe({ from: { x: dock.x + dock.width / 2, y: dock.y + dock.height / 2 }, to: { x: 820, y: 600 }, duration: 500 })`. Works even if the dock shifts horizontally when buttons change.
- **`argent`:** On UIKit/React Native apps, `argent` actually has nicer syntax (`swipe: { from: { text: Minimize controls }, to: { x: 0.983, y: 0.496 }, duration: 500 }`). On SwiftUI Sill, `from: { text: Minimize controls }` fails because the button is not in `native-full-hierarchy`, forcing hardcoded start *and* end coordinates (`from: { x: 0.716, y: 0.962 }`), plus hardcoding every subsequent tap on the morphed trailing vertical rail (`x: 0.957`).

### Setup cost & footprint
- **`e2e`:** Per-repo `Tests/e2e/package.json` + 920-line `pnpm-lock.yaml`; `pnpm install` took `2.6 s` (`69 MB` `node_modules`) plus `85 MB` cached `~/.agent-device` runner build; `e2e doctor` verifies toolchain, simulator, and installed bundle in one command; pays `13.5–21.7 s` engine prep on every CLI invocation; rejects `--output` outside `Tests/e2e/` and rejects `--reporter list,json`.
- **`argent`:** Zero per-repo dependencies (global `0.34.0` install, `79 MB` in pnpm store); persistent shared `tool-server` + per-UDID `simulator-server`/`ax-service` means `<0.5 s` startup per run; accepts any `--output` path and `--json`; requires explicit `--device <UDID>` when multiple simulators are booted and has no `doctor` equivalent for project config.

### Failure diagnostics (shared case: Unified Switcher 100% CPU bug)
- **`e2e` leaves behind:**
  - `trace.md` with exact source file and line (`tests/switcher-and-controls.e2e.ts:12`), per-step durations, and a **46-node accessibility tree diff** showing that `Done`, `Windows`, `Search windows & Mac apps`, and `Desktop` all appeared before the hang.
  - `report.json` (`schemaVersion: report-1`) with full step timings and `CLEANUP_TIMEOUT` error record.
  - **Missing on hang:** No `screen-at-failure.txt` and no automatic failure screenshot (only the explicit `01-switcher-open.png` taken before the hang).
  - **Side-effect:** `CLEANUP_TIMEOUT` adds `30.8 s` and changes exit code from `1` (test failure) to `3` (infrastructure error), which can mislead CI triage into retrying a deterministic product bug.
- **`argent` leaves behind:**
  - Structured `--json` report with every step's `durationMs`, `args`, `result`, and explicit cause classification: `"cause": "unreadable"` (`"last tree fetch failed: tree fetch did not complete within the 5000ms wait budget"`) — immediately separating a wedged app from a bad selector.
  - `step-7-screen.png` in `--output <dir>/switcher-and-controls/`, captured from the simulator framebuffer **even while Sill is frozen at 100% CPU**, visually proving the Unified Switcher sheet is open with the cursor blinking in `Search windows & Mac apps`.
  - **Weakness:** Step 8 (`tap: { x: 0.5, y: 0.6 }`) timed out internally for `15.4 s` during settle yet still reported `"status": "pass"` with no warning, attributing the failure to the *following* `await-ui-element` step (`Controls`) rather than the hung tap itself.

---

## 5. Recommendation for `verify-sill`

**Recommendation: Keep `e2e` (`@e2e-dev/mobile`) as `verify-sill`'s primary Lane 2 test runner.**

### Rationale
1. **Selector fidelity on SwiftUI is non-negotiable.** `verify-sill` exists to catch regressions across Sill's SwiftUI layouts, edge morphing, sheets, and Dynamic Type XXXL. `e2e` drives Sill entirely through semantic accessibility locators (`getByText`, `getByRole`, `.first()`, `boundingBox()`, `scrollUntilVisible`) with zero hardcoded tap coordinates. On `argent 0.34.0`, every SwiftUI control is invisible to the iOS simulator YAML runner tree, forcing `tool: await-ui-element` + brittle normalized coordinates for every single tap and swipe. A faster suite that breaks whenever a button moves 20 pt or text scales up is worse for `verify-sill` than a slower suite with real semantic locators.
2. **State gallery integration.** `Scripts/render-states.sh` drives `Tests/e2e/tests/gallery.e2e.ts`, which renders 20 parameterized states across iPad, iPhone, and Dynamic Type XXXL using a single TypeScript data table, `app.screenshot(s.frame)`, file copies, and `manifest.tsv` output. `argent` YAML cannot replace this cleanly without an external orchestration script.
3. **Target & tag ergonomics.** `e2e` supports `--target ipad --tag ipad` / `--target phone --tag phone` in one config; `argent` requires manual directory splitting and explicit UDID plumbing.
4. **The main `e2e` pain points are directly fixable.**
   - **Multi-agent session collision:** Set a per-device `session` in `Tests/e2e/e2e.config.ts` (e.g., slugifying `SILL_E2E_IPAD` / `SILL_E2E_PHONE`) so parallel agents on separate simulators never collide on `"e2e-ipad-0"`.
   - **71 s iPad slowdown & `exit 3`:** Over `50 s` of the iPad wall-time gap (`30.8 s` `CLEANUP_TIMEOUT` + `~20 s` extra timeout on `switcher-and-controls`) disappears once Sill's Unified Switcher 100% CPU product bug is fixed.

### Alternatives considered and rejected
- **Switch `verify-sill` Lane 2 to `argent` YAML (`Tests/argent/`):** Rejected. Despite ~2.6× faster iPad wall time (`44.39 s` vs `115.71 s`) and superior hung-app screenshot capture, `argent 0.34.0` lacks accessibility-tree selector resolution in iOS simulator e2e YAML (`adaptFullHierarchy` reads only `UIView`s). *Revisit condition:* if a future `argent` release adds an accessibility-tree (`ax-service` / `native-describe-screen`) runner tree mode for iOS simulators (matching what `argent` already does on physical iPhones via `projectIosDeviceNode`), `argent` becomes a strong contender on speed and hung-app diagnostics.
- **Run both (`argent` for fast smoke, `e2e` for full verify + gallery):** Rejected. Duplicates test maintenance, adds a second daemon stack, and mixing `e2e` (XCTest) and `argent` (`ax-service`) on the same simulator wedged `ax-service` after a hung app until the simulator was rebooted. Keep `argent` strictly as an optional interactive inspection tool (`argent run describe`, `native-view-at-point`) rather than a second verify suite.
- **Maestro:** Rejected / forbidden (uninstalled globally on this Mac).

---

## 6. Committed Evidence Artifacts

All raw benchmark logs and failure artifacts are committed under `docs/evidence/e2e-vs-argent/logs/`:
- `timings.txt`, `load-waits.log`
- `ipad-r{1,2,3}-e2e.{stdout.txt,report.json}` & `ipad-r1-e2e-failure/.../trace.md`
- `ipad-r{1,2,3}-argent.{report.json,stderr.txt}` & `ipad-r1-argent-failure/switcher-and-controls/step-7-screen.png`
- `ipad-r0-e2e-collision.{stdout.txt,report.json}` & `ipad-r0-argent-post-e2e-ax-wedge.report.json`
- `phone-r{1,2,3}-e2e.{stdout.txt,report.json}` & `phone-r{1,2,3}-argent.{report.json,stderr.txt}`

---

## Synthesis (arena, 2026-11-24)

This report is candidate 2's (Gemini 4 Neon), the base picked by the cross-judge (Gemini 4 Neon on another account: 19/25 against 17/25) and by the orchestrator's own reading. A `decide score` pass over the two report texts alone leaned the other way (21.8 against 20.4), but it read neither port nor logs. Candidate 1 (Claude Sonnet 5.5, branch `test/bench-e2e-vs-argent`, `ae43a88c`) lost on one checked defect: its argent switcher test taps the Apps position without waiting for the dock, so its switcher never opened, and its argent switcher timing (9.0 s) and diagnostics describe a missed tap, not the bug. Both candidates reached the same recommendation independently: keep e2e.

Candidate 2 stopped on a usage quota before filling its iPhone rows. The orchestrator filled them from its own logs (`logs/timings.txt`, `logs/phone-r*`), deleted its simulators (`arena-c2 iPad`, `arena-c2 iPhone`, left booted), and grafted:

- **From candidate 1: cold start.** e2e's "mobile engine prepared" includes the simulator boot and the iOS runner (25–44 s: boot 6–8 s, runner 15–25 s, app open 3–6 s); argent's `boot-device` takes 8–13 s (iPad) and 13–19 s (iPhone) and builds nothing. This report's argent totals are on a warm simulator and a running tool-server.
- **From candidate 1: unverified tail.** In `Tests/argent/ipad/switcher-and-controls.yaml`, every step after the switcher opens (the Desktop tap at `0.500, 0.600` and on) has never run, because the CPU spin stops every run there; its coordinates are unproven.
- **The `control-center` e2e failure, found after both runs.** Both candidates saw it fail 3 of 3 and neither found why. Its trace shows `scrollUntilVisible` reaching the `Quality, Auto` row and the sheet then expanding to large and the list moving on past it (`momentum: 'none'` did not stop it). The test now taps the sheet's grabber to expand it first and asserts the row without scrolling: 3 of 3 passes (`Tests/e2e/tests/control-center.e2e.ts`). So e2e's iPhone suite passes 2 of 2, as argent's did, whose `text` match is a substring.
- **From candidate 2's own finding: the session collision is fixed.** `Tests/e2e/e2e.config.ts` now names each target's agent-device session after its simulator (`mobile({ session })`), so two agents on two simulators no longer share `e2e-ipad-0`.

Rejected: candidate 1's `bench.sh` and `aggregate.py` (written for its own log names and branch; this report's numbers come from candidate 2's logs), and running both tools in verify-sill (candidate 2, section 5).

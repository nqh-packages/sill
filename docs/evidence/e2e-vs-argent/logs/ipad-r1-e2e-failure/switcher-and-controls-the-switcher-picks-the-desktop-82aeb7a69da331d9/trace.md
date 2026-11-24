# ✗ the switcher picks the Desktop, then Control Center opens

`tests/switcher-and-controls.e2e.ts` · target `ipad` · failed · 41.1s

Ran on: platform `ios` · device `arena-c2 iPad`

**ACTION_FAILED**

```text
operation timed out: getByText("Desktop").first()
```

Look at: `tests/switcher-and-controls.e2e.ts:12`  

## Steps

1. ✓ `device.openApp` `com.uxheavy.sill` (3.2s) — `tests/launch.ts:7`
2. ✓ `locator.tap` `getByText("Apps")` (1.1s) — `tests/switcher-and-controls.e2e.ts:7`
   - tap button "Apps" (1.1s)
   - screen: 15 nodes at `com.uxheavy.sill`
3. ✓ `expect.toBeVisible` `getByText("Done")` (398ms) — `tests/switcher-and-controls.e2e.ts:8`
   - screen: 46 changes since step 2 at `com.uxheavy.sill / Mac mini`, 35 nodes
     - `added other "dismiss popup" testid="PopoverDismissRegion"`
     - `added button "Sheet Grabber" value="Half screen"`
     - `added navigation testid="Mac mini"`
     - `added text "Mac mini"`
     - `added button "Done"`
     - `added textbox "Search windows & Mac apps"`
     - `added image "Search" testid="magnifyingglass"`
     - `added scroll-view`
     - `added button "Show the full Mac desktop"`
     - `added image "Mac" testid="display"`
     - `added text "Desktop"`
     - `added text "Windows"`
     - 34 more
4. ✓ `expect.toBeVisible` `getByText("Windows")` (154ms) — `tests/switcher-and-controls.e2e.ts:9`
   - screen: unchanged since step 3 at `com.uxheavy.sill / Mac mini`
5. ✓ `app.screenshot` `01-switcher-open` (1.2s) — `tests/switcher-and-controls.e2e.ts:10`
   - [screenshot](attempt-1/screenshots/001-01-switcher-open.png) `.e2e/bench-ipad-r1/results/switcher-and-controls-the-switcher-picks-the-desktop-82aeb7a69da331d9/attempt-1/screenshots/001-01-switcher-open.png`
6. ✗ `locator.tap` `getByText("Desktop").first()` (30.0s) — **ACTION_FAILED** — `tests/switcher-and-controls.e2e.ts:12`

## Evidence

- [screenshot](attempt-1/screenshots/001-01-switcher-open.png) `.e2e/bench-ipad-r1/results/switcher-and-controls-the-switcher-picks-the-desktop-82aeb7a69da331d9/attempt-1/screenshots/001-01-switcher-open.png`

<sub>e2e 0.24.0 · run `01a20b71-abd5-7de9-9964-465980938cff` · the whole run is in `report.json`</sub>

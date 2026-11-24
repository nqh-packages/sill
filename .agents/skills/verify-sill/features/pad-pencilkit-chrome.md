# iPad PencilKit Floating Chrome

Unified floating tool palette over the full-bleed Mac stream canvas on iPad, iPhone landscape, and Duo book mode (`PadWorkspaceChrome.swift`, `StreamWorkspaceState.swift`).

## Sub-features

- Starts docked horizontally at the **bottom edge** so Mac window titlebars and browser toolbars stay unobstructed.
- Unified tactile capsule containing a subtle drag grip, 3 front-most Mac window icons (with active selection rim), divider, and uniform circular keys (`Apps`, Mac `Menus` when available, `Aa` Text size, `Keyboard`, `Trackpad`, `Controls`, `Minimize controls`).
- Free drag from anywhere on the chrome (8 pt before it counts): the bar collapses to the 48 pt orb under the finger, a ghost previews the drop, and release snaps with velocity projection to one of 4 edges or, within 20 % of a side and 22 % of the top or bottom, a corner (`capsuleSnapTarget`).
- Automatic axis morphing (`HStack` on top/bottom, vertical `VStack` rail on leading/trailing). Compact rail when the height left above the software keyboard is < 460 pt; compact horizontal bar below 500 pt wide (active app, `Keyboard`, `Trackpad`, `Controls`, `Minimize controls`; no `Text size`).
- 4-corner minimization into a 48×48 circular orb displaying the active Mac app icon (plus cyan LED when Keyboard or Trackpad is active); tapping expands back onto its adjacent `returnEdge`, dragging relocates or docks it.
- Edge-aware `Aa` text-scale detent pill opening inward toward the canvas (dimmed when Desktop or nothing streams).
- Floating draggable Trackpad toggled by the `Trackpad` key.
- The dock and the floating trackpad keep 10 pt above the software keyboard (`StreamWorkspaceState.chromeBottomClearance`, `StreamScreen.floatingPadAvoidance`).
- Window icons are labelled by their window title (or app name), not `Apps`.

## How to get to it (user POV)

Connect to a Mac on iPad (or rotate iPhone to landscape). In the offline mock harness, launch with `SillLayout=834x1194` (portrait) or `SillLayout=1112x834` (landscape). No account required.

## Driving it

- **Lane 2 (e2e — primary):** `Tests/e2e/tests/pad-pencilkit-chrome.e2e.ts` (`--target ipad`) pins bottom launch, `Aa` detent selection, a drag from the dock to the trailing edge with the inward `Aa`, minimize to the corner orb, tap-orb-to-expand, and the floating trackpad open/close. `Tests/e2e/tests/smoke.e2e.ts` is the doctor's launch check.
- **Locators:** `Apps`, `Text size`, `Keyboard`, `Trackpad`, `Controls`, `Minimize controls`, `Off`, `1 times`, `Move the trackpad` and `Close the trackpad` (each matches two nodes: `.first()`). The `Text size` locators need a width of 500 pt or more.
- **Lane 3 (Local):** `Tests/checks/tactile-workspace/run.sh` section 5 pins the 4-edge & 4-corner snap math, adjacent `returnEdge` preservation, and NaN/center guards; section 6 the floating trackpad; section 10 the keyboard clearance. T3 `agent-device gesture pan` verifies timed drags into specific corners.

## Proof

On screen: bottom capsule clears top area; after drag to right edge, `Apps` and `Text size` remain visible along trailing edge and `Aa` opens to the left; after minimize, `Apps`/`Text size` are not visible and the single 48×48 `Controls` orb is visible in the corner; tapping `Controls` restores `Apps` and `Text size`. Pure state check: `Tests/checks/tactile-workspace/run.sh` exits `0`.

## Charters

```
pad-chrome-docking|ios|skeptic|On iPad stream (SillLayout=834x1194), drag the floating capsule to all four edges and all four corners; verify axis morphing, corner orb expansion to adjacent edge, and that Aa always opens inward without clipping
pad-chrome-gestures|ios|fuzzer|Rapidly tap buttons right after short drags, open Aa then drag the capsule, and toggle the floating trackpad while minimized; report any accidental button fires, stuck popovers, or blocked canvas touches
```

## States

- Typical bottom dock (`SillLayout=834x1194`) → `pad-chrome-bottom`
- Vertical trailing rail + inward `Aa` popover (dragged) → `pad-chrome-trailing-aa`
- Minimized 48×48 corner orb (minimized) → `pad-chrome-orb`
- Desktop streaming / `Aa` disabled (`SillActive=desktop`) → `pad-chrome-desktop-aa-disabled`
- Empty / nothing streaming (`SillActive=none`) → `pad-chrome-empty-none`
- Full-screen hidden chrome with hint (`SillFullScreen=1`, `SillFullScreenHint=hold`) → `pad-fullscreen-hint`

## Gotchas

- The mock harness has a black stream backdrop (no live HEVC frames); this is normal and not a blank-screen bug.
- Tapping `Minimize controls` collapses to the nearest corner for the current edge (`bottomTrailing` from bottom/trailing, `topTrailing` from top, `bottomLeading` from leading); its accessibility label becomes `Controls`.
- The `Aa` scale pill (`PadWorkspaceChrome`) auto-closes when a drag begins, on minimize, or when `client.textScaleSelectable` becomes false (Desktop / none).
- `Controls` is a key in the expanded capsule and the orb's label when minimized: assert it only after `Minimize controls`.

# iPad PencilKit Floating Chrome

Unified floating tool palette over the full-bleed Mac stream canvas on iPad, iPhone landscape, and Duo book mode (`PadWorkspaceChrome.swift`, `StreamWorkspaceState.swift`).

## Sub-features

- Starts docked horizontally at the **bottom edge** so Mac window titlebars and browser toolbars stay unobstructed.
- Unified tactile capsule containing a subtle drag grip, 3 front-most Mac window icons (with active selection rim), divider, and uniform circular keys (`Apps`, Mac `Menus` when available, `Aa` Text size, `Keyboard`, `Trackpad`, `Controls`, `Minimize controls`).
- Free drag from anywhere on the chrome with velocity-projected snapping across all 4 edges (`.top`, `.bottom`, `.leading`, `.trailing`) and live magnetic dock silhouette preview.
- Automatic axis morphing (`HStack` on top/bottom, vertical `VStack` rail on leading/trailing; compact vertical sizing when height < 460 pt).
- 4-corner minimization into a 48×48 circular orb displaying the active Mac app icon (plus cyan LED when Keyboard or Trackpad is active); tapping expands back onto its adjacent `returnEdge`, dragging relocates or docks it.
- Edge-aware `Aa` text-scale detent pill opening inward toward the canvas (dimmed when Desktop or nothing streams).
- Floating draggable Trackpad toggled by the `Trackpad` key.

## How to get to it (user POV)

Connect to a Mac on iPad (or rotate iPhone to landscape). In the offline mock harness, launch with `SillLayout=834x1194` (portrait) or `SillLayout=1112x834` (landscape). No account required.

## Driving it

- **Lane 2 (Maestro — primary):** `.maestro/pad-pencilkit-chrome.yaml` pins bottom launch, `Aa` detent selection, drag-to-trailing-edge vertical morph + inward `Aa`, minimize to corner orb, tap-orb-to-expand, and floating trackpad open/close.
- **Locators:** `Apps`, `Text size`, `Keyboard`, `Trackpad`, `Controls`, `Minimize controls`, `Off`, `1 times`, `Move the trackpad`, `Close the trackpad`.
- **Lane 3 (Local):** `Tests/checks/tactile-workspace/run.sh` (section 6) pins all 4-edge & 4-corner snap math, adjacent `returnEdge` preservation, and NaN/center guards; T3 `agent-device gesture pan` verifies timed drags into specific corners.

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
- In `StreamScreen`, the `Aa` scale pill auto-closes when dragging begins or when `client.textScaleSelectable` becomes false (Desktop / none).

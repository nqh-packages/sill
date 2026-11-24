# iPhone Compact PencilKit Chrome & Control Deck

Unified size-adaptive PencilKit floating palette paired with the bottom-anchored tactile Control Deck on narrow screens (`width < 600 pt`, e.g. iPhone portrait; `PadWorkspaceChrome.swift`, `TactileTrackpadDeck.swift`, `TactileKeycaps.swift`).

## Sub-features

- Uses the same universal PencilKit floating chrome as iPad (4-edge docking + 4-corner 48×48 minimized orb) over a **100% full-bleed stream canvas** — no permanently reserved bottom bar.
- Compact horizontal density (`width < 500 pt`): grip notch + active app icon button (`Apps`, opens Unified Switcher) + divider + `Keyboard`, `Trackpad`, `Controls`, `Minimize controls` (`~235 pt` wide). Dragging to a vertical side rail morphs into the full vertical tool rail.
- Width-adaptive Trackpad (`width < 600 pt`): tapping `Trackpad` opens the bottom-anchored Control Deck (`Drag to move the pointer. Tap to click, two fingers to scroll.`) with hardware-style command keycaps (`TactileCommandBar`), 1-tap `Switch to keyboard` / `Switch to trackpad`, and `Stow trackpad`.
- Viewport stability: mid-drag deck movement never thrashes Mac viewport resizes; settled deck open/close refits the visible canvas above the deck or software keyboard.
- The capsule keeps 10 pt above the software keyboard (`StreamWorkspaceState.chromeBottomClearance`).
- The picture stays clear of the screen's rounded corners, shown and in full screen, its own edges mirrored into the strips this leaves (`ScreenCorners`, `StreamScreen.cornerStrips`; DEBUG `-SillCornerRadius R`, `-SillCornerFill 0`; the console's "corners: …" line).

## How to get to it (user POV)

Connect to a Mac on iPhone in portrait orientation. In the offline mock harness, launch on an iPhone simulator with `SillLayout=402x874` and `SillIdiom=phone`.

## Driving it

- **Lane 2 (e2e — primary):** `Tests/e2e/tests/phone-workspace.e2e.ts` (`--target phone`) verifies the compact bottom PencilKit pill (`Apps`, `Keyboard`, `Trackpad`, `Controls`, `Minimize controls`), minimizes to and expands from the corner orb, opens and stows the Control Deck (`Stow trackpad`), and opens `Controls` → Mac `Menus` (`File`) → `Done`.
- **Locators:** `Apps`, `Keyboard`, `Trackpad`, `Controls`, `Minimize controls`, `Drag to move the pointer. Tap to click, two fingers to scroll.`, `Stow trackpad`, `Switch to keyboard`, `Full Screen` and `Menus` (tile and row: `.first()`), `File`, `Done`.
- **Lane 3 (Local):** `Tests/checks/tactile-workspace/run.sh` pins deck drag/snap thresholds, Keyboard ↔ Trackpad swap, viewport locking, and 4-edge / 4-corner snap physics.

## Proof

On screen: compact bottom capsule fits inside 402 pt width without overflow; `Minimize controls` collapses to the 48×48 corner orb (`Apps` hidden, `Controls` orb visible); tapping `Controls` expands it back; tapping `Trackpad` opens the bottom Control Deck with trackpad well and hides the capsule; `Stow trackpad` returns the floating capsule cleanly.

## Charters

```
phone-pencilkit-and-deck|ios|skeptic|On iPhone portrait (SillLayout=402x874, SillIdiom=phone), drag the compact capsule to all four edges and corners, open and stow the Control Deck, and open Control Center; check no overflow or home-indicator overlap
phone-deck-keyboard|ios|fuzzer|Alternate rapidly between Control Deck, software Keyboard, corner orb, and Switcher/Controls modals on iPhone portrait; verify clean restoration and that no modifiers remain stuck
```

## States

- Compact PencilKit bottom pill (`SillLayout=402x874`, `SillIdiom=phone`) → `phone-pencilkit-bottom`
- Minimized 48×48 corner orb on phone → `phone-pencilkit-orb`
- Bottom-anchored Control Deck open (tap `Trackpad`) → `phone-control-deck`
- Compact Unified Switcher (`SillDrawer=1`) → `phone-switcher`

## Gotchas

- `Aa` and `Menus` are intentionally omitted from the compact horizontal pill (`width < 500 pt`) to prevent overflow; both remain 1 tap away inside `Controls` (or directly on the capsule when docked vertically on a side rail).
- The corner clearance does not show in the mock (its picture is black, and `-SillPointer`'s frame is landscape, letterboxed away from the corners): see it on a live picture (`-SillConnect 127.0.0.1:<PORT>` to a `--synthetic` host) or a device, and in the console's "corners: …" line.
- Software keyboard visibility on a simulator depends on whether UIKit considers a hardware keyboard connected; in mock mode `-SillKeyboard 1` lights the Keyboard button without raising the system IME over the fake frame.

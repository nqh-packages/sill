# Unified Switcher

Modal sheet for picking the Mac Desktop, switching open Mac windows, or launching installed Mac apps (`UnifiedSwitcherSheet.swift`).

## Sub-features

- Desktop hero card showing display bezel, display names, `Streaming` (only while the Desktop streams: `SillActive=desktop`), and display stop indicator.
- Open windows grid with `TactileDisplayBezel` thumbnails, corner app icons, window titles, and active selection rim.
- `Apps on <Mac>` section to launch installed apps on the Mac.
- Live search filtering across windows and installed apps (trimmed of spaces), with the system's search empty state (`ContentUnavailableView.search`).
- `Done` closes it; a window card's context menu offers Close, Minimize and Full Screen.

## How to get to it (user POV)

Tap `Apps` in the floating capsule (the search field takes focus), or the active-app key of the compact capsule below 500 pt wide (no focus). Seedable in the mock harness with `-SillDrawer 1` (opens 1.5 s after launch, no focus). `-SillDrawerSearch` only reaches the old `AppDrawer`, which nothing shows any more.

## Driving it

- **Lane 2 (e2e — primary):** `Tests/e2e/tests/switcher-and-controls.e2e.ts` (`--target ipad`) opens `Apps`, verifies `Done` and `Windows`, taps `Desktop`, and confirms the sheet dismisses into Control Center's root. **Fails today** on a product bug (Gotchas).
- **Locators:** `Apps`, `Done`, `Windows`, `Desktop` (the card and the Finder window titled "Desktop": `.first()`), `Finder`, `Code`, `Notes`, `Streaming` (with `SillActive=desktop`). The `Mac mini` navigation title is drawn but not reported to the accessibility tree.
- **Lane 3 (Local):** `Tests/checks/tactile-workspace/run.sh` section 8 verifies `.switcher` acquires the `.drawer` keyboard taker, section 3 `restoreKeyboardAfterModal`.

## Proof

On screen: sheet presents with the Mac's name as its title, the Desktop card, and window cards (`Finder`, `Code`, `Notes`); selecting `Desktop` dismisses the switcher sheet and returns to the stream screen with active chrome.

## Charters

```
switcher-pick-and-search|ios|skeptic|Open Unified Switcher from Apps, search for an app name, clear search, then switch between Desktop and a window; verify selection updates and sheet dismisses cleanly
switcher-empty-search|ios|fuzzer|Open Unified Switcher and enter nonsense strings, whitespace-only queries, and very long text into search; check empty-state copy and layout stability
```

## States

- Typical iPad switcher (`SillLayout=834x1194`, `SillDrawer=1`) → `switcher-typical`
- Typical compact iPhone switcher (`SillLayout=402x874`, `SillIdiom=phone`, `SillDrawer=1`) → `phone-switcher`

## Gotchas

- `TactileDisplayBezel` clips thumbnails via an `.overlay` + `.clipShape` so portrait or mismatched aspect ratio mock thumbnails must never bleed past the card border — check this visually in `switcher-typical`.
- In mock mode, `client.macName` is `"Mac mini"` unless overridden by `-SillMockMacName`.
- **Known product bug (2026-11-24, iOS 27.3 simulator, iPad):** opening the switcher from `Apps` pins Sill at 100 % CPU inside `UISheetPresentationController`'s keyboard layout (the search field's focus), so every accessibility query and tap after it times out. Reproduced at a795274c and 58613b5d. Until it is fixed the switcher test fails at its first tap.

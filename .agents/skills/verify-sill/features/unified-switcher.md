# Unified Switcher

Modal sheet for picking the Mac Desktop, switching open Mac windows, or launching installed Mac apps (`UnifiedSwitcherSheet.swift`).

## Sub-features

- Desktop hero card showing display bezel, display names, active `Streaming` status, and display stop indicator.
- Open windows grid with `TactileDisplayBezel` thumbnails, corner app icons, window titles, and active selection rim.
- Installed Mac apps section to launch apps on the Mac.
- Live search filtering across windows and installed apps, with an explicit empty-match state (`No windows or apps match “…”`).

## How to get to it (user POV)

Tap `Apps` in the iPad floating capsule, or tap the active window chip in the iPhone Focus dock. Directly seedable in mock harness with `SillDrawer=1` (and optional `SillDrawerSearch=<query>`).

## Driving it

- **Lane 2 (Maestro — primary):** `.maestro/switcher-and-controls.yaml` opens `Apps`, verifies `Mac mini`, `Desktop`, and `Finder`, taps `Desktop`, and confirms the sheet dismisses back to the stream chrome.
- **Locators:** `Apps`, `Mac mini` (navigation title), `Desktop`, `Finder`, `Code`, `Notes`, `Streaming`.
- **Lane 3 (Local):** `Tests/checks/tactile-workspace/run.sh` (section 9) verifies `.switcher` acquires the `.drawer` keyboard taker and preserves `restoreKeyboardAfterModal`.

## Proof

On screen: sheet presents with Mac name title (`Mac mini`), Desktop card, and window cards (`Finder`, `Code`, `Notes`); selecting `Desktop` dismisses the switcher sheet and returns to the stream screen with active chrome.

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

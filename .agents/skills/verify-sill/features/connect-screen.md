# Connect Screen & Add a Mac

Root discovery and pairing screen shown before connecting to a Mac (`TactileConnectView.swift`, `AddMacCard.swift`).

## Sub-features

- Discovered and saved Macs displayed as machined `TactileDisplayBezel` cards with connection method badges (`Wired`, `Wi-Fi`, `Direct`, `Remote`, `Not paired`).
- Empty/searching state (`looking`), hint with `Search Nearby` (`hint`), permission-denied explanation (`denied`), version-floor refusal (`update`), and remote failure states (`remotefail`, its words set by `-SillRemoteFailure`).
- `Add a Mac` button (`+`) opening the manual pairing / QR / code entry sheet (`Add a Mac` / `Cancel`).
- `Reconnect automatically` switch and footer links + version label.

## How to get to it (user POV)

Launch Sill with no active Mac connection (or after disconnecting). Seedable in the mock harness via `-SillConnectCase` (`MockCatalog.ConnectCase`: `looking`, `hint`, `methods`, `denied`, `update`, `remotefail`, `addmac`, `addcode`, `nearby`, `notice`, `remote`, `pairing`, `camera`, the `home*` cases and more). The mock never auto-reconnects, so the "Reconnecting to …" pill is not seen there.

## Driving it

- **Lane 2 (e2e — primary):** `Tests/e2e/tests/connect-screen.e2e.ts` (`--target ipad`) launches `-SillConnectCase methods`, verifies `Add a Mac` and `Reconnect automatically`, opens `Add a Mac`, verifies `Cancel`, and dismisses back.
- **Locators:** `Add a Mac`, `Reconnect automatically` (switch and text: `.first()`), `Cancel` (two in the sheet: `.first()`), `Search Nearby` (`hint` and `looking` only).
- **Lane 3 (Local):** `Tests/checks/connection-list/run.sh`, `Tests/checks/home-device/run.sh`, and `Tests/checks/goodbye/run.sh` test discovery/pairing/refusal rules headlessly.

## Proof

On screen: navigation title `Sill`, Mac bezel cards without thumbnail bleed, `Reconnect automatically` row, and `Add a Mac` modal opens and cancels cleanly. Side effects (live app): `Reconnect automatically` persists in `UserDefaults`; paired Macs persist in Keychain (`SavedMacs.swift`).

## Charters

```
connect-discovery-and-add|ios|skeptic|Launch Connect screen with SillConnectCase=methods, verify every card badge and layout, toggle Reconnect automatically, open Add a Mac and cancel back
connect-edge-cases|ios|fuzzer|Inspect Connect screen across looking, denied, update, remotefail, and methods at Dynamic Type XXXL; report any truncated error explanations or overflowing bezel cards
```

## States

- Empty / searching (`SillConnectCase=looking`) → `connect-looking`
- Overloaded methods + long Mac names (`SillConnectCase=methods`) → `connect-methods`
- Permission denied (`SillConnectCase=denied`) → `connect-denied`
- Error: older app refused (`SillConnectCase=update`) → `connect-error-update`
- Error: remote dial failed (`SillConnectCase=remotefail`) → `connect-error-remotefail`
- Accessibility Dynamic Type XXXL (`SillConnectCase=methods`, XXXL) → `connect-methods-xl`

## Gotchas

- Launching without `-SillLayout` uses real Bonjour discovery and lists the real Macs nearby (e.g. `MarkoloPro, Wired`). **Never tap one**: it would connect to a person's Mac and its encoder. Always pass `-SillLayout` and `-SillConnectCase`.
- QR code camera scanning inside `Add a Mac` is unavailable on iOS Simulator; use code entry or `-SillConnectCase addcode` instead.

# Connect Screen & Add a Mac

Root discovery and pairing screen shown before connecting to a Mac (`TactileConnectView.swift`, `AddMacCard.swift`).

## Sub-features

- Discovered and saved Macs displayed as machined `TactileDisplayBezel` cards with connection method badges (`Wired`, `Wi-Fi`, `Direct`, `Remote`, `Not paired`).
- Empty/searching state (`looking`), hint with `Search Nearby` (`hint`), permission-denied explanation (`denied`), version-floor refusal (`update`), and remote failure states (`remotefail`).
- `Add a Mac` button (`+`) opening the manual pairing / QR / code entry sheet (`Add a Mac` / `Cancel`).
- `Reconnect automatically` switch and footer links + version label.

## How to get to it (user POV)

Launch Sill with no active Mac connection (or after disconnecting). Directly seedable in mock harness via `SillConnectCase=looking|hint|methods|denied|update|remotefail|addmac`.

## Driving it

- **Lane 2 (Maestro — primary):** `.maestro/connect-screen.yaml` launches `SillConnectCase=methods`, verifies `Sill`, `Add a Mac`, and `Reconnect automatically`, opens `Add a Mac`, verifies `Cancel`, and dismisses back.
- **Locators:** `Sill`, `Add a Mac`, `Reconnect automatically`, `Cancel`, `Search Nearby`.
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

- Launching without `-SillLayout` uses real Bonjour discovery on the local network and will show real nearby Macs (e.g. `MarkoloPro`) as `Not paired`; always pass `SillConnectCase` for deterministic UI proofs.
- QR code camera scanning inside `Add a Mac` is unavailable on iOS Simulator; use code entry or `-SillConnectCase addcode` instead.

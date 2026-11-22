# Control Center

Unified modal sheet for Mac connection status, streaming quality/audio/virtual-display toggles, device preferences, Mac menus route, and disconnect (`ControlCenterSheet.swift`).

## Sub-features

- Mac header card with live link badge, round-trip time (`Link and stream`), Mute/Unmute audio toggle, and `Paste to <Mac>`.
- `Streaming` section: Resolution (`Retina` / `Standard`), Frame Rate (`60 fps` / `120 fps`), Quality presets, Prioritize Speed, Virtual Display, and Send Audio (beta).
- `This iPad` / `This iPhone` section: Clipboard sharing, Reverse Scrolling, Three-Finger Gestures, Full Screen, and Picture in Picture (when supported).
- `Away from home` status, Take the Tour, version footer, and `Disconnect from <Mac>` action.
- Secondary route `macMenus` for browsing Mac app menus on compact devices.

## How to get to it (user POV)

Tap `Controls` on the iPad floating capsule or iPhone Focus dock. Directly seedable in mock harness with `SillSettings=1` (and optional `SillSettingsEnd=1` or `SillSettingsScroll=sound|gestures|reverse`).

## Driving it

- **Lane 2 (Maestro — primary):** `.maestro/switcher-and-controls.yaml` (iPad) and `.maestro/phone-workspace.yaml` (iPhone) tap `Controls`, assert `Mac mini`, `Streaming`, `This iPad`/`This iPhone`, scroll to and assert `Disconnect from Mac mini`.
- **Locators:** `Controls`, `Mac mini`, `Streaming`, `This iPad`, `This iPhone`, `Reverse Scrolling`, `Three-Finger Gestures`, `Send Audio, beta`, `Disconnect from Mac mini`.
- **Lane 3 (Local):** `Tests/checks/tactile-workspace/run.sh` (section 9) pins `.controlCenter(.root)` (`[.settings]`) and `.controlCenter(.macMenus)` (`[.settings, .menus]`) keyboard takers.

## Proof

On screen: sheet renders header, `Streaming` controls, device-specific section (`This iPad` or `This iPhone`), and `Disconnect from Mac mini` at the bottom without truncation at both default and Dynamic Type XXXL sizes. Side effects (live session): device toggles persist in `UserDefaults` (`com.uxheavy.sill`); host settings changes emit `HostSettingsChange` over the wire.

## Charters

```
controls-sections|ios|skeptic|Open Controls on iPad and iPhone, scroll top to bottom, toggle Reverse Scrolling and Three-Finger Gestures, and inspect every section footer for clipping or stale labels
controls-accessibility|ios|fuzzer|Open Controls at largest accessibility text size (Dynamic Type XXXL); scroll through Streaming, This iPad, and Disconnect to catch overlapping controls or clipped badges
```

## States

- Typical iPad Control Center (`SillLayout=834x1194`, `SillSettings=1`) → `controls-typical`
- Accessibility Dynamic Type XXXL (`SillLayout=834x1194`, `SillSettings=1`, `content_size=accessibility-extra-extra-extra-large`) → `controls-typical-xl`

## Gotchas

- `This iPad` vs `This iPhone` section header adapts to the device idiom (`-SillIdiom phone|pad`).
- In mock mode, tapping `Disconnect from Mac mini` does not tear down a real network socket; test real disconnect against a loopback `SillHost --synthetic` with `-SillSettingsScript`.

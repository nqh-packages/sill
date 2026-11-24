# Control Center

Unified modal sheet for Mac connection status, streaming quality/audio/virtual-display toggles, device preferences, Mac menus route, and disconnect (`ControlCenterSheet.swift`).

## Sub-features

- The Mac's name as the sheet's title, then a deck of tiles: `Full Screen`, `Sound`/`Muted` (labelled "Mute/Unmute sound from <Mac>"), `Paste`, `Menus` (dimmed unless the Mac has menus) and Picture in Picture; the `Text size` dial; and the link pill (`Link and stream`).
- `Streaming` section: Quality (a menu: `Auto` first when the Mac offers it, then the presets; the row reads "Quality, Auto" while Auto holds; `QualityMenu.swift`), Resolution (`Retina` / `Standard`), Frame Rate (`60 fps` / `120 fps`), Prioritize Encoding Speed, Virtual Display, and Send Audio (beta).
- `This iPad` / `This iPhone` section: Clipboard sharing, Reverse Scrolling, Three-Finger Gestures, Full Screen (only while it is offered), and Picture in Picture (when supported).
- `Away from home` status, Take the Tour, version footer, and `Disconnect from <Mac>` action.
- Secondary route `macMenus` for browsing Mac app menus on compact devices.

## How to get to it (user POV)

Tap `Controls` on the floating capsule. Seedable in the mock harness with `-SillSettings 1` (opens 1.5 s after launch), with `-SillSettingsEnd 1` or `-SillSettingsScroll sound|mute|gestures|reverse|hold|clipboard|pip`, and the mock Mac's state with `-SillSettingsCase` (`auto`: Quality on Auto; `autolowered`: Auto lowered to Standard, the stream screen's notice).

## Driving it

- **Lane 2 (e2e — primary):** `Tests/e2e/tests/control-center.e2e.ts` (`--target phone`) opens it with `-SillSettingsCase auto` and asserts the `Quality, Auto` row; `Tests/e2e/tests/phone-workspace.e2e.ts` opens `Controls` → `Menus` → `File` → `Done`; `Tests/e2e/tests/switcher-and-controls.e2e.ts` (iPad) reaches `Streaming`, `This iPad` and `Disconnect from Mac mini` after the switcher (blocked by the switcher's bug).
- **Locators:** `Controls`, `Streaming`, `This iPad`, `This iPhone`, `Quality, Auto` (a button), `Full Screen` and `Menus` (tile and row: `.first()`), `Reverse Scrolling`, `Three-Finger Gestures`, `Send Audio, beta`, `Disconnect from Mac mini`. The `Mac mini` title is not in the accessibility tree.
- **Lane 3 (Local):** `Tests/checks/tactile-workspace/run.sh` section 8 pins `.controlCenter(.root)` (`[.settings]`) and `.controlCenter(.macMenus)` (`[.settings, .menus]`) keyboard takers.

## Proof

On screen: sheet renders header, `Streaming` controls, device-specific section (`This iPad` or `This iPhone`), and `Disconnect from Mac mini` at the bottom without truncation at both default and Dynamic Type XXXL sizes. Side effects (live session): device toggles persist in `UserDefaults` (`com.uxheavy.sill`); host settings changes emit `HostSettingsChange` over the wire.

## Charters

```
controls-sections|ios|skeptic|Open Controls on iPad and iPhone, scroll top to bottom, toggle Reverse Scrolling and Three-Finger Gestures, and inspect every section footer for clipping or stale labels
controls-accessibility|ios|fuzzer|Open Controls at largest accessibility text size (Dynamic Type XXXL); scroll through Streaming, This iPad, and Disconnect to catch overlapping controls or clipped badges
```

## States

- Typical iPad Control Center (`SillLayout=834x1194`, `SillSettings=1`) → `controls-typical`
- Quality on Auto, iPhone (`SillSettings=1`, `SillSettingsCase=auto`) → `phone-controls-auto`
- Accessibility Dynamic Type XXXL (`SillLayout=834x1194`, `SillSettings=1`, `content_size=accessibility-extra-extra-extra-large`) → `controls-typical-xl`

## Gotchas

- `This iPad` vs `This iPhone` section header adapts to the device idiom (`-SillIdiom phone|pad`).
- In mock mode, tapping `Disconnect from Mac mini` does not tear down a real network socket; test real disconnect against a loopback `SillHost --synthetic` with `-SillSettingsScript`.

# Sill Feature Map

User-facing feature map for the Sill iOS/iPadOS app (`com.uxheavy.sill`). Each file names its sub-features, user entry points, driving lane and test file, observable proof, bug-bash charters, gallery states, and gotchas.

| Feature | Entry point / Launch args | Test / Flow | Status |
| --- | --- | --- | --- |
| [iPad PencilKit Floating Chrome](pad-pencilkit-chrome.md) | Stream screen (iPad / landscape / Duo book) · `SillLayout=834x1194` | `.maestro/pad-pencilkit-chrome.yaml`, `Tests/checks/tactile-workspace/run.sh` | tested |
| [iPhone Compact PencilKit Chrome & Control Deck](phone-workspace.md) | Stream screen (iPhone portrait) · `SillLayout=402x874`, `SillIdiom=phone` | `.maestro/phone-workspace.yaml`, `Tests/checks/tactile-workspace/run.sh` | tested |
| [Unified Switcher](unified-switcher.md) | Tap `Apps` (iPad) or active window chip (iPhone) · `SillDrawer=1` | `.maestro/switcher-and-controls.yaml` | tested |
| [Control Center](control-center.md) | Tap `Controls` on dock or capsule · `SillSettings=1` | `.maestro/switcher-and-controls.yaml`, `.maestro/phone-workspace.yaml` | tested |
| [Connect Screen & Add a Mac](connect-screen.md) | Disconnected root screen · `SillConnectCase=methods` | `.maestro/connect-screen.yaml` | tested |

Unmapped secondary surfaces (add files when a change touches them): Mac menus pull-down (`-SillMacMenu`), Picture in Picture (`-Sill.pictureInPicture`), Clipboard chip (`-SillClipboardNote`), Guided Tour (`TourOverlay`), and macOS host `Sill.app` (`docs/BUILD-AND-RUN.md`).

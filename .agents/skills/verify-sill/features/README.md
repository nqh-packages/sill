# Sill Feature Map

User-facing feature map for the Sill iOS/iPadOS app (`com.uxheavy.sill`). Each file names its sub-features, user entry points, driving lane and test file, observable proof, bug-bash charters, gallery states, and gotchas.

| Feature | Entry point / Launch args | Test / Flow | Status |
| --- | --- | --- | --- |
| [iPad PencilKit Floating Chrome](pad-pencilkit-chrome.md) | Stream screen (iPad / landscape / Duo book) · `SillLayout=834x1194` | `Tests/e2e/tests/pad-pencilkit-chrome.e2e.ts`, `Tests/checks/tactile-workspace/run.sh` | tested |
| [iPhone Compact PencilKit Chrome & Control Deck](phone-workspace.md) | Stream screen (iPhone portrait) · `SillLayout=402x874`, `SillIdiom=phone` | `Tests/e2e/tests/phone-workspace.e2e.ts`, `Tests/checks/tactile-workspace/run.sh` | tested |
| [Unified Switcher](unified-switcher.md) | Tap `Apps` (or the compact capsule's active-app key) · `SillDrawer=1` | `Tests/e2e/tests/switcher-and-controls.e2e.ts` | failing: CPU spin on open (product bug) |
| [Control Center](control-center.md) | Tap `Controls` on the capsule · `SillSettings=1` | `Tests/e2e/tests/control-center.e2e.ts`, `Tests/e2e/tests/phone-workspace.e2e.ts` | tested |
| [Connect Screen & Add a Mac](connect-screen.md) | Disconnected root screen · `SillConnectCase=methods` | `Tests/e2e/tests/connect-screen.e2e.ts` | tested |

Unmapped secondary surfaces (add files when a change touches them): Mac menus pull-down (`-SillMacMenu`), Picture in Picture (`-Sill.pictureInPicture`), Clipboard chip (`-SillClipboardNote`), Guided Tour (`TourOverlay`), and macOS host `Sill.app` (`docs/BUILD-AND-RUN.md`).

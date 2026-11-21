# `tactile-workspace`

**Checks:** `StreamWorkspaceState` (iOSClient/StreamWorkspaceState.swift) on its own: form switching across `phonePortrait`, `phoneLandscape`, `padFullCanvas`, `duoBook` and `duoLaptop`; phone Control Deck drag clamping and snap/flick thresholds; keyboard `ReturnTarget` restoration across Focus, Control Deck, system keyboard events, and modals (with both `restoreKeyboard: true` and `false`); swipe-on-chip window cycling and wraparound; viewport stability while the Control Deck or keyboard is active versus initial, resize, text-scale and chrome-toggle commits; floating capsule tuck/untuck and edge switching; floating trackpad visibility and anchor clamping; full-screen chrome hide/show; hardware keyboard accessory suppression; `WorkspaceKeyboardTaker` derivation across every modal and Control Center route; and scene deactivation key/modifier cleanup.

**Compiles:** `iOSClient/StreamWorkspaceState.swift`

#!/bin/bash
# StreamWorkspaceState (iOSClient/StreamWorkspaceState.swift) on its own: pure state machine checks
# for phone Focus/Control Deck, keyboard ReturnTarget restoration, swipe-on-chip cycling, viewport
# stability, floating capsule/trackpad, full-screen chrome toggling, and keyboard taker derivation.
#   Tests/checks/tactile-workspace/run.sh          compile and run the check
here="$(cd "$(dirname "$0")" && pwd)"
source "$here/../common.sh"
swiftc -O iOSClient/StreamWorkspaceState.swift "$here/main.swift" -o "$out/check"
"$out/check"

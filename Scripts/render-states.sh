#!/usr/bin/env bash
set -euo pipefail

# State gallery renderer for Sill (iOS / iPadOS).
# Uses Maestro + Sill's deterministic DEBUG LayoutHarness (-SillLayout / -SillConnectCase / etc.)
# to capture every major screen and component across reachable states (including Dynamic Type XL),
# then builds a browsable HTML contact sheet at .e2e/states/index.html.
#
# Usage:
#   Scripts/render-states.sh [--ipad-udid UDID] [--phone-udid UDID] [--out DIR] [--force]
#
# Env:
#   SILL_VERIFY_IPAD_UDID   Booted iPad simulator UDID (auto-detected if omitted)
#   SILL_VERIFY_PHONE_UDID  Booted iPhone simulator UDID (auto-detected if omitted)

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT_DIR="${ROOT}/.e2e/states"
IPAD_UDID="${SILL_VERIFY_IPAD_UDID:-}"
PHONE_UDID="${SILL_VERIFY_PHONE_UDID:-}"
FORCE=0

while [[ $# -gt 0 ]]; do
    case "$1" in
        --ipad-udid) IPAD_UDID="$2"; shift 2 ;;
        --phone-udid) PHONE_UDID="$2"; shift 2 ;;
        --out) OUT_DIR="$2"; shift 2 ;;
        --force) FORCE=1; shift ;;
        -h|--help)
            sed -n '3,16p' "$0"
            exit 0
            ;;
        *) echo "Unknown arg: $1" >&2; exit 2 ;;
    esac
done

if ! command -v maestro >/dev/null 2>&1; then
    echo "ERROR: maestro is not installed (brew install maestro)." >&2
    exit 1
fi

# Doctor gate: refuse if machine 1-min load is very high unless --force.
if [[ "$FORCE" -eq 0 ]]; then
    LOAD1="$(sysctl -n vm.loadavg | awk '{print $2}')"
    if awk -v l="$LOAD1" 'BEGIN { exit !(l > 8.0) }'; then
        echo "ERROR: 1-min load is ${LOAD1} (> 8.0). Re-run when quieter or pass --force." >&2
        exit 1
    fi
fi

# Auto-detect booted simulators if not supplied.
if [[ -z "$IPAD_UDID" ]]; then
    IPAD_UDID="$(xcrun simctl list devices booted | awk -F '[()]' '/iPad/ {print $2; exit}')"
fi
if [[ -z "$PHONE_UDID" ]]; then
    PHONE_UDID="$(xcrun simctl list devices booted | awk -F '[()]' '/iPhone/ {print $2; exit}')"
fi

if [[ -z "$IPAD_UDID" && -z "$PHONE_UDID" ]]; then
    echo "ERROR: No booted iOS/iPadOS simulator found. Boot one first or pass --ipad-udid / --phone-udid." >&2
    exit 1
fi

FRAMES_DIR="${OUT_DIR}/frames"
TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/sill-gallery.XXXXXX")"
mkdir -p "$FRAMES_DIR"

cleanup() {
    # Always restore default Dynamic Type size on simulators we touched.
    if [[ -n "$IPAD_UDID" ]]; then
        xcrun simctl ui "$IPAD_UDID" content_size large >/dev/null 2>&1 || true
    fi
    if [[ -n "$PHONE_UDID" ]]; then
        xcrun simctl ui "$PHONE_UDID" content_size large >/dev/null 2>&1 || true
    fi
    rm -rf "$TMP_DIR"
}
trap cleanup EXIT

run_flow() {
    local udid="$1"
    local name="$2"
    local yaml_path="${TMP_DIR}/${name}.yaml"
    local debug_dir="${TMP_DIR}/out-${name}"
    cat > "$yaml_path"
    echo "==> Rendering ${name} on ${udid}"
    maestro --device "$udid" test "$yaml_path" --debug-output "$debug_dir" >/dev/null
    local png
    png="$(find "$debug_dir" -name "${name}.png" -type f | head -n 1 || true)"
    if [[ -z "$png" || ! -f "$png" ]]; then
        # Maestro may also save screenshots relative to cwd if path is bare
        if [[ -f "${ROOT}/${name}.png" ]]; then
            mv "${ROOT}/${name}.png" "${FRAMES_DIR}/${name}.png"
        elif [[ -f "${PWD}/${name}.png" ]]; then
            mv "${PWD}/${name}.png" "${FRAMES_DIR}/${name}.png"
        else
            echo "ERROR: Expected screenshot ${name}.png not produced" >&2
            exit 1
        fi
    else
        cp "$png" "${FRAMES_DIR}/${name}.png"
    fi
}

# Build manifest as TSV: group\tframe\tcaption
MANIFEST="${TMP_DIR}/manifest.tsv"
: > "$MANIFEST"

add_entry() {
    printf "%s\t%s\t%s\n" "$1" "$2" "$3" >> "$MANIFEST"
}

if [[ -n "$IPAD_UDID" ]]; then
    xcrun simctl ui "$IPAD_UDID" content_size large >/dev/null 2>&1 || true

    # 1. Connect screen states
    run_flow "$IPAD_UDID" "connect-looking" <<'EOF'
appId: com.uxheavy.sill
---
- launchApp:
    clearState: false
    arguments:
      SillLayout: "834x1194"
      SillConnectCase: "looking"
- assertVisible: "Sill"
- takeScreenshot: "connect-looking"
EOF
    add_entry "Connect Screen" "connect-looking" "Empty / searching for Macs (SillConnectCase=looking)"

    run_flow "$IPAD_UDID" "connect-methods" <<'EOF'
appId: com.uxheavy.sill
---
- launchApp:
    clearState: false
    arguments:
      SillLayout: "834x1194"
      SillConnectCase: "methods"
- assertVisible: "Sill"
- takeScreenshot: "connect-methods"
EOF
    add_entry "Connect Screen" "connect-methods" "Overloaded discovery: Wired, Wi-Fi, Direct, long Mac names"

    run_flow "$IPAD_UDID" "connect-denied" <<'EOF'
appId: com.uxheavy.sill
---
- launchApp:
    clearState: false
    arguments:
      SillLayout: "834x1194"
      SillConnectCase: "denied"
- assertVisible: "Sill"
- takeScreenshot: "connect-denied"
EOF
    add_entry "Connect Screen" "connect-denied" "Permission denied (Local Network access denied)"

    run_flow "$IPAD_UDID" "connect-error-update" <<'EOF'
appId: com.uxheavy.sill
---
- launchApp:
    clearState: false
    arguments:
      SillLayout: "834x1194"
      SillConnectCase: "update"
- assertVisible: "Sill"
- takeScreenshot: "connect-error-update"
EOF
    add_entry "Connect Screen" "connect-error-update" "Error: Mac refused older app version"

    run_flow "$IPAD_UDID" "connect-error-remotefail" <<'EOF'
appId: com.uxheavy.sill
---
- launchApp:
    clearState: false
    arguments:
      SillLayout: "834x1194"
      SillConnectCase: "remotefail"
- assertVisible: "Sill"
- takeScreenshot: "connect-error-remotefail"
EOF
    add_entry "Connect Screen" "connect-error-remotefail" "Error: Remote connection failed"

    # 2. iPad PencilKit Floating Chrome states
    run_flow "$IPAD_UDID" "pad-chrome-bottom" <<'EOF'
appId: com.uxheavy.sill
---
- launchApp:
    clearState: false
    arguments:
      SillLayout: "834x1194"
- assertVisible: "Apps"
- takeScreenshot: "pad-chrome-bottom"
EOF
    add_entry "iPad PencilKit Chrome" "pad-chrome-bottom" "Typical: unified capsule docked at bottom"

    run_flow "$IPAD_UDID" "pad-chrome-trailing-aa" <<'EOF'
appId: com.uxheavy.sill
---
- launchApp:
    clearState: false
    arguments:
      SillLayout: "834x1194"
- assertVisible: "Apps"
- swipe:
    start: "50%,96%"
    end: "95%,50%"
    duration: 500
- tapOn: "Text size"
- assertVisible: "Off"
- takeScreenshot: "pad-chrome-trailing-aa"
EOF
    add_entry "iPad PencilKit Chrome" "pad-chrome-trailing-aa" "Vertical right rail with inward Aa detent popover"

    run_flow "$IPAD_UDID" "pad-chrome-orb" <<'EOF'
appId: com.uxheavy.sill
---
- launchApp:
    clearState: false
    arguments:
      SillLayout: "834x1194"
- assertVisible: "Minimize controls"
- tapOn: "Minimize controls"
- assertNotVisible: "Apps"
- assertVisible: "Controls"
- takeScreenshot: "pad-chrome-orb"
EOF
    add_entry "iPad PencilKit Chrome" "pad-chrome-orb" "Minimized 48x48 corner orb showing active app icon"

    run_flow "$IPAD_UDID" "pad-chrome-desktop-aa-disabled" <<'EOF'
appId: com.uxheavy.sill
---
- launchApp:
    clearState: false
    arguments:
      SillLayout: "834x1194"
      SillActive: "desktop"
- assertVisible: "Text size"
- takeScreenshot: "pad-chrome-desktop-aa-disabled"
EOF
    add_entry "iPad PencilKit Chrome" "pad-chrome-desktop-aa-disabled" "Desktop streaming: Aa disabled/dimmed"

    run_flow "$IPAD_UDID" "pad-chrome-empty-none" <<'EOF'
appId: com.uxheavy.sill
---
- launchApp:
    clearState: false
    arguments:
      SillLayout: "834x1194"
      SillActive: "none"
- assertVisible: "Apps"
- takeScreenshot: "pad-chrome-empty-none"
EOF
    add_entry "iPad PencilKit Chrome" "pad-chrome-empty-none" "Empty: nothing streaming (SillActive=none)"

    run_flow "$IPAD_UDID" "pad-fullscreen-hint" <<'EOF'
appId: com.uxheavy.sill
---
- launchApp:
    clearState: false
    arguments:
      SillLayout: "834x1194"
      SillFullScreen: "1"
      SillFullScreenHint: "hold"
- assertVisible: ".*Mac mini.*"
- waitForAnimationToEnd
- takeScreenshot: "pad-fullscreen-hint"
EOF
    add_entry "iPad PencilKit Chrome" "pad-fullscreen-hint" "Full screen hidden chrome with swipe-in hint"

    # 3. Unified Switcher & Control Center (typical + Dynamic Type XL)
    run_flow "$IPAD_UDID" "switcher-typical" <<'EOF'
appId: com.uxheavy.sill
---
- launchApp:
    clearState: false
    arguments:
      SillLayout: "834x1194"
      SillDrawer: "1"
- assertVisible: "Mac mini"
- takeScreenshot: "switcher-typical"
EOF
    add_entry "Unified Switcher" "switcher-typical" "Typical: Desktop card + open windows + installed apps"

    run_flow "$IPAD_UDID" "controls-typical" <<'EOF'
appId: com.uxheavy.sill
---
- launchApp:
    clearState: false
    arguments:
      SillLayout: "834x1194"
      SillSettings: "1"
- assertVisible: "Streaming"
- takeScreenshot: "controls-typical"
EOF
    add_entry "Control Center" "controls-typical" "Typical: Mac header, Streaming controls, This iPad"

    # Dynamic Type XL edge case on iPad
    xcrun simctl ui "$IPAD_UDID" content_size accessibility-extra-extra-extra-large >/dev/null 2>&1 || true

    run_flow "$IPAD_UDID" "connect-methods-xl" <<'EOF'
appId: com.uxheavy.sill
---
- launchApp:
    clearState: false
    arguments:
      SillLayout: "834x1194"
      SillConnectCase: "methods"
- assertVisible: "Sill"
- takeScreenshot: "connect-methods-xl"
EOF
    add_entry "Accessibility (Dynamic Type XXXL)" "connect-methods-xl" "Connect screen overloaded at accessibility-extra-extra-extra-large"

    run_flow "$IPAD_UDID" "controls-typical-xl" <<'EOF'
appId: com.uxheavy.sill
---
- launchApp:
    clearState: false
    arguments:
      SillLayout: "834x1194"
      SillSettings: "1"
- assertVisible: "Streaming"
- takeScreenshot: "controls-typical-xl"
EOF
    add_entry "Accessibility (Dynamic Type XXXL)" "controls-typical-xl" "Control Center at accessibility-extra-extra-extra-large"

    xcrun simctl ui "$IPAD_UDID" content_size large >/dev/null 2>&1 || true
fi

if [[ -n "$PHONE_UDID" ]]; then
    xcrun simctl ui "$PHONE_UDID" content_size large >/dev/null 2>&1 || true

    run_flow "$PHONE_UDID" "phone-pencilkit-bottom" <<'EOF'
appId: com.uxheavy.sill
---
- launchApp:
    clearState: false
    arguments:
      SillLayout: "402x874"
      SillIdiom: "phone"
- assertVisible: "Minimize controls"
- takeScreenshot: "phone-pencilkit-bottom"
EOF
    add_entry "iPhone Workspace" "phone-pencilkit-bottom" "Typical: unified compact PencilKit floating capsule at bottom"

    run_flow "$PHONE_UDID" "phone-pencilkit-orb" <<'EOF'
appId: com.uxheavy.sill
---
- launchApp:
    clearState: false
    arguments:
      SillLayout: "402x874"
      SillIdiom: "phone"
- tapOn: "Minimize controls"
- assertNotVisible: "Apps"
- assertVisible: "Controls"
- takeScreenshot: "phone-pencilkit-orb"
EOF
    add_entry "iPhone Workspace" "phone-pencilkit-orb" "Minimized 48x48 corner orb on full-bleed phone canvas"

    run_flow "$PHONE_UDID" "phone-control-deck" <<'EOF'
appId: com.uxheavy.sill
---
- launchApp:
    clearState: false
    arguments:
      SillLayout: "402x874"
      SillIdiom: "phone"
- tapOn: "Trackpad"
- assertVisible: "Drag to move the pointer. Tap to click, two fingers to scroll."
- takeScreenshot: "phone-control-deck"
EOF
    add_entry "iPhone Workspace" "phone-control-deck" "Control Deck: tactile trackpad + Esc/modifier command bar"

    run_flow "$PHONE_UDID" "phone-switcher" <<'EOF'
appId: com.uxheavy.sill
---
- launchApp:
    clearState: false
    arguments:
      SillLayout: "402x874"
      SillIdiom: "phone"
      SillDrawer: "1"
- assertVisible: "Mac mini"
- takeScreenshot: "phone-switcher"
EOF
    add_entry "iPhone Workspace" "phone-switcher" "Unified Switcher sheet on compact phone width"
fi

# Generate one browsable HTML contact sheet grouped by component.
python3 - "$MANIFEST" "$OUT_DIR" <<'PY'
import html, os, sys
from collections import OrderedDict

manifest_path, out_dir = sys.argv[1], sys.argv[2]
groups = OrderedDict()
count = 0
with open(manifest_path, encoding="utf-8") as f:
    for line in f:
        line = line.rstrip("\n")
        if not line:
            continue
        group, frame, caption = line.split("\t", 2)
        groups.setdefault(group, []).append((frame, caption))
        count += 1

sections = []
for group, items in groups.items():
    cards = []
    for frame, caption in items:
        img = f"frames/{html.escape(frame)}.png"
        cards.append(
            f'<figure class="card">'
            f'<a href="{img}" target="_blank"><img src="{img}" alt="{html.escape(frame)}" loading="lazy"></a>'
            f'<figcaption><strong>{html.escape(frame)}</strong><span>{html.escape(caption)}</span></figcaption>'
            f'</figure>'
        )
    sections.append(
        f'<section><h2>{html.escape(group)}</h2><div class="grid">{"".join(cards)}</div></section>'
    )

doc = f"""<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<title>Sill State Gallery ({count} frames)</title>
<style>
  :root {{ color-scheme: dark; }}
  body {{ margin: 0; padding: 28px; background: #0d0d0e; color: #f2f2f7; font-family: -apple-system, BlinkMacSystemFont, sans-serif; }}
  header {{ display: flex; justify-content: space-between; align-items: baseline; margin-bottom: 24px; border-bottom: 1px solid #2c2c2e; padding-bottom: 12px; }}
  h1 {{ margin: 0; font-size: 22px; }}
  .meta {{ color: #8e8e93; font-size: 13px; }}
  section {{ margin-bottom: 34px; }}
  h2 {{ font-size: 15px; text-transform: uppercase; letter-spacing: 0.06em; color: #aeaeb2; margin: 0 0 14px; }}
  .grid {{ display: grid; grid-template-columns: repeat(auto-fill, minmax(260px, 1fr)); gap: 16px; }}
  .card {{ margin: 0; background: #141415; border: 1px solid rgba(255,255,255,0.12); border-radius: 14px; overflow: hidden; display: flex; flex-direction: column; }}
  .card img {{ width: 100%; height: auto; display: block; background: #000; }}
  figcaption {{ padding: 10px 12px; display: flex; flex-direction: column; gap: 4px; font-size: 12px; }}
  figcaption strong {{ color: #f2f2f7; font-family: ui-monospace, SFMono-Regular, monospace; }}
  figcaption span {{ color: #8e8e93; }}
</style>
</head>
<body>
<header>
  <h1>Sill State Gallery</h1>
  <span class="meta">{count} frames across {len(groups)} groups</span>
</header>
{"".join(sections)}
</body>
</html>
"""

index_path = os.path.join(out_dir, "index.html")
with open(index_path, "w", encoding="utf-8") as f:
    f.write(doc)
print(f"State gallery written: {index_path} ({count} frames)")
PY

#!/usr/bin/env bash
set -euo pipefail

# State gallery renderer for Sill (iOS / iPadOS).
# Runs the e2e gallery (Tests/e2e/tests/gallery.e2e.ts) against Sill's deterministic DEBUG LayoutHarness
# (-SillLayout / -SillConnectCase / etc.) on the iPad and iPhone simulators e2e targets, Dynamic Type XXXL
# included, then builds a browsable HTML contact sheet at .e2e/states/index.html.
# It installs nothing: build and install the Debug simulator app first (verify-sill, "Launch").
#
# Usage:
#   Scripts/render-states.sh [--ipad NAME] [--phone NAME] [--out DIR] [--force]
#
# Env:
#   SILL_E2E_IPAD   iPad simulator name for the e2e "ipad" target (default: e2e.config.ts's)
#   SILL_E2E_PHONE  iPhone simulator name for the e2e "phone" target (default: e2e.config.ts's)

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
E2E="${ROOT}/Tests/e2e"
OUT_DIR="${ROOT}/.e2e/states"
FORCE=0

while [[ $# -gt 0 ]]; do
    case "$1" in
        --ipad) export SILL_E2E_IPAD="$2"; shift 2 ;;
        --phone) export SILL_E2E_PHONE="$2"; shift 2 ;;
        --out) OUT_DIR="$2"; shift 2 ;;
        --force) FORCE=1; shift ;;
        -h|--help)
            sed -n '3,15p' "$0"
            exit 0
            ;;
        *) echo "Unknown arg: $1" >&2; exit 2 ;;
    esac
done

if [[ ! -x "${E2E}/node_modules/.bin/e2e" ]]; then
    echo "ERROR: e2e is not installed: (cd Tests/e2e && pnpm install)." >&2
    exit 1
fi

if [[ "$FORCE" -eq 0 ]]; then
    LOAD1="$(sysctl -n vm.loadavg | awk '{print $2}')"
    if awk -v l="$LOAD1" 'BEGIN { exit !(l > 8.0) }'; then
        echo "ERROR: 1-min load is ${LOAD1} (> 8.0). Re-run when quieter or pass --force." >&2
        exit 1
    fi
fi

udid_named() {
    xcrun simctl list devices booted -j | python3 -c 'import json,sys
name=sys.argv[1]
for devs in json.load(sys.stdin)["devices"].values():
    for d in devs:
        if d["name"]==name: print(d["udid"]); raise SystemExit' "$1"
}

rm -rf "$OUT_DIR"
mkdir -p "$OUT_DIR/frames"
export SILL_GALLERY_OUT="$OUT_DIR"
MANIFEST="${OUT_DIR}/manifest.tsv"
: > "$MANIFEST"
XL_UDID=""
cleanup() {
    if [[ -n "$XL_UDID" ]]; then xcrun simctl ui "$XL_UDID" content_size large >/dev/null 2>&1 || true; fi
}
trap cleanup EXIT

FAILED=0
gallery() {
    (cd "$E2E" && pnpm exec e2e run --target "$1" --tag "$2" tests/gallery.e2e.ts) || FAILED=1
}

IPAD_NAME="${SILL_E2E_IPAD:-iPad Pro 11-inch (M5)}"
PHONE_NAME="${SILL_E2E_PHONE:-iPhone 17 Pro}"
IPAD_UDID="$(udid_named "$IPAD_NAME" || true)"
PHONE_UDID="$(udid_named "$PHONE_NAME" || true)"
if [[ -z "$IPAD_UDID" && -z "$PHONE_UDID" ]]; then
    echo "ERROR: neither \"$IPAD_NAME\" nor \"$PHONE_NAME\" is booted. Boot one, or name yours with --ipad / --phone." >&2
    exit 1
fi

if [[ -n "$IPAD_UDID" ]]; then
    xcrun simctl ui "$IPAD_UDID" content_size large >/dev/null 2>&1 || true
    gallery ipad gallery-ipad
    XL_UDID="$IPAD_UDID"
    xcrun simctl ui "$IPAD_UDID" content_size accessibility-extra-extra-extra-large >/dev/null 2>&1 || true
    gallery ipad gallery-ipad-xl
    xcrun simctl ui "$IPAD_UDID" content_size large >/dev/null 2>&1 || true
    XL_UDID=""
fi
if [[ -n "$PHONE_UDID" ]]; then
    xcrun simctl ui "$PHONE_UDID" content_size large >/dev/null 2>&1 || true
    gallery phone gallery-phone
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
if [[ "$FAILED" -ne 0 ]]; then
    echo "Some states failed to render: see Tests/e2e/.e2e/results/." >&2
    exit 1
fi

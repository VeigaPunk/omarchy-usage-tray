#!/usr/bin/env bash
# M01: fixture → cache → Waybar JSON. No network.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BIN="$ROOT/bin/ai-usage"
FIXTURE="$ROOT/fixtures/codex.pro.json"

if [[ ! -x "$BIN" ]]; then
  echo "FAIL: missing executable $BIN" >&2
  exit 1
fi
if [[ ! -f "$FIXTURE" ]]; then
  echo "FAIL: missing $FIXTURE" >&2
  exit 1
fi

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
export AI_USAGE_CACHE="$TMP/status.json"
export AI_USAGE_SELECTED="$TMP/selected"

"$BIN" probe codex --fixture "$FIXTURE"

mode="$(stat -c '%a' "$AI_USAGE_CACHE")"
if [[ "$mode" != "600" ]]; then
  echo "FAIL: cache mode $mode want 600" >&2
  exit 1
fi

json="$("$BIN" waybar)"
echo "$json"

echo "$json" | jq -e '.text and .tooltip and .class and .alt' >/dev/null

text="$(echo "$json" | jq -r .text)"
tooltip="$(echo "$json" | jq -r .tooltip)"
class="$(echo "$json" | jq -r .class)"

# Pinned fixture meters: white-on-gray pango bars, no block-grid glyphs.
if [[ "$text" == *$'\n'* ]]; then
  echo "FAIL: expected one-line text, got: $text" >&2
  exit 1
fi
if [[ "$text" != *bgcolor* ]]; then
  echo "FAIL: expected pango bgcolor meters, got: $text" >&2
  exit 1
fi
if [[ "$text" == *▓* || "$text" == *░* ]]; then
  echo "FAIL: block-grid glyphs still in text: $text" >&2
  exit 1
fi
if [[ -z "$tooltip" ]]; then
  echo "FAIL: empty tooltip" >&2
  exit 1
fi
if [[ "$class" != *ok* ]]; then
  echo "FAIL: class '$class' does not include ok" >&2
  exit 1
fi

# Missing used_pct must never become a guessed fill.
python3 - "$AI_USAGE_CACHE" "$BIN" <<'PY'
import json, os, subprocess, sys, tempfile
from pathlib import Path
cache_path = Path(sys.argv[1])
bin_path = sys.argv[2]
data = json.loads(cache_path.read_text())
prov = data["providers"]["codex"]
# Drop special used_pct entirely.
for w in prov["windows"]:
    if w.get("kind") == "special":
        w.pop("used_pct", None)
cache_path.write_text(json.dumps(data))
env = os.environ.copy()
out = subprocess.check_output([bin_path, "waybar"], env=env, text=True)
payload = json.loads(out)
if "—" not in payload["text"] and "–" not in payload["text"]:
    raise SystemExit(f"FAIL: missing window must render em-dash, got {payload['text']!r}")
# A guessed 0-fill would be five empty blocks without a dash.
if "░" in payload["text"] and "—" not in payload["text"]:
    raise SystemExit("FAIL: invented empty-bar percent for missing window")
print("MISSING_WINDOW_OK")

# Unauth / missing used_pct → em-dash, never empty-block 0% fill.
data = json.loads(cache_path.read_text())
data["selected"] = "kimi"
data["providers"]["kimi"] = {
    "id": "kimi",
    "name": "Kimi",
    "logo": "K",
    "status": "unauth",
    "reason": "need_login",
    "windows": [
        {"kind": "weekly", "label": "Weekly"},
        {"kind": "special", "label": "Special"},
    ],
}
cache_path.write_text(json.dumps(data))
sel = Path(os.environ["AI_USAGE_SELECTED"])
sel.write_text("kimi\n")
out = subprocess.check_output([bin_path, "waybar"], env=env, text=True)
payload = json.loads(out)
text = payload["text"]
if "\n" in text:
    raise SystemExit(f"FAIL: unauth chip must be one line, got {text!r}")
if "—" not in text and "–" not in text:
    raise SystemExit(f"FAIL: unauth text must contain em-dash, got {text!r}")
if "░" in text or "▓" in text:
    raise SystemExit(f"FAIL: unauth must not render empty-block 0%, got {text!r}")
if payload.get("class") and "ok" == payload["class"]:
    raise SystemExit(f"FAIL: unauth class looks ok: {payload['class']!r}")
print("UNAUTH_DASH_OK")
PY

echo "WAYBAR_JSON_OK"

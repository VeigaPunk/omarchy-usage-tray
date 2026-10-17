#!/usr/bin/env bash
# M01: probe → cache → Waybar JSON. No network (fake omp).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BIN="$ROOT/bin/ai-usage"

if [[ ! -x "$BIN" ]]; then
  echo "FAIL: missing executable $BIN" >&2
  exit 1
fi

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
export AI_USAGE_CACHE="$TMP/status.json"
export AI_USAGE_SELECTED="$TMP/selected"
export AI_USAGE_OMP_BIN="$TMP/fake-omp"
cat >"$AI_USAGE_OMP_BIN" <<'SH'
#!/usr/bin/env bash
# One openai-codex report: primary weekly window at 62%.
cat <<'JSON'
{"reports":[{"provider":"openai-codex","fetchedAt":1790233200000,"limits":[{"id":"openai-codex:primary","window":{"id":"primary","resetsAt":1790793600000},"amount":{"usedFraction":0.62}}]}],"accountsWithoutUsage":[],"disabledCredentials":[]}
JSON
SH
chmod +x "$AI_USAGE_OMP_BIN"

"$BIN" probe codex

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
class="$(echo "$json" | jq -r '.class | join(" ")')"

# Metered probe: white-on-gray pango bars, no block-grid glyphs.
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
import xml.etree.ElementTree as ET
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

# Small positive usage must not say zero, and the less-than sign must not
# break Waybar's Pango tooltip. Near-exhaustion must not claim an exhausted
# account until the actual meter reaches 100%.
for pct, expected in ((0.4, "<1%"), (99.6, "99%"), (100, "100%")):
    for w in prov["windows"]:
        w["used_pct"] = pct
    prov["account_usage"] = [
        {"used_pct": pct, "label": "<shared & metered>"},
        {"used_pct": 0},
    ]
    cache_path.write_text(json.dumps(data))
    payload = json.loads(subprocess.check_output([bin_path, "waybar"], env=env, text=True))
    root = ET.fromstring(f"<tooltip>{payload['tooltip']}</tooltip>")
    plain = "".join(root.itertext())
    weekly = next(line for line in plain.splitlines() if line.startswith("7 days "))
    account = next(line for line in plain.splitlines() if line.startswith(" 1 "))
    assert expected in weekly.split(), (pct, weekly)
    assert expected in account.split(), (pct, account)
    assert "<shared & metered>" in account, account
print("PERCENT_BOUNDARIES_OK")

# Unauth / missing used_pct → em-dash, never empty-block 0% fill.
# The chip is scoped to authed+metered providers, so the unauth provider only
# renders once it is the sole remaining row in the cache.
data = json.loads(cache_path.read_text())
data["selected"] = "kimi"
del data["providers"]["codex"]
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
if "ok" in payload.get("class", []):
    raise SystemExit(f"FAIL: unauth class looks ok: {payload['class']!r}")
print("UNAUTH_DASH_OK")
PY

echo "WAYBAR_JSON_OK"

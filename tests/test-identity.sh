#!/usr/bin/env bash
# Token Plan identities: slots metadata only, never keys / op:// in Waybar JSON.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BIN="$ROOT/bin/ai-usage"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

mkdir -p "$TMP/tp"
cat >"$TMP/tp/slots" <<'EOF'
# comment
team|op://vault/item/credential|DashScope Token Plan Team|team
gmail|op://Personal/secret/credential|Alibaba Cloud Token Plan|vgpnk1337@gmail.com
EOF
printf 'gmail\n' >"$TMP/tp/active"
chmod 600 "$TMP/tp/slots" "$TMP/tp/active"

export AI_USAGE_CACHE="$TMP/status.json"
export AI_USAGE_SELECTED="$TMP/selected"
export AI_USAGE_TOKEN_PLAN_CONF="$TMP/tp"
printf 'token-plan\n' >"$AI_USAGE_SELECTED"

python3 - "$BIN" <<'PY'
import json, os, subprocess, sys
from pathlib import Path
bin_path = sys.argv[1]
# Minimal cache so waybar can render.
cache = {
    "version": 1,
    "updated_at": "2026-08-23T00:00:00Z",
    "selected": "token-plan",
    "providers": {
        "token-plan": {
            "id": "token-plan",
            "name": "Token Plan",
            "logo": "T",
            "status": "unauth",
            "reason": "need_console_login",
            "windows": [{"kind": "weekly", "label": "Weekly"}, {"kind": "session", "label": "5h"}],
        }
    },
}
Path(os.environ["AI_USAGE_CACHE"]).write_text(json.dumps(cache))
os.chmod(os.environ["AI_USAGE_CACHE"], 0o600)
out = subprocess.check_output([bin_path, "waybar"], text=True)
payload = json.loads(out)
blob = json.dumps(payload)
if "op://" in blob or "credential" in blob:
    raise SystemExit(f"FAIL: leaked slot secret into waybar JSON: {blob}")
if "gmail" not in payload["text"]:
    raise SystemExit(f"FAIL: expected gmail on chip, got {payload['text']!r}")
if "identity: gmail" not in payload.get("tooltip", ""):
    raise SystemExit(f"FAIL: expected identity in tooltip, got {payload.get('tooltip')!r}")
if "▓" in payload["text"] or "░" in payload["text"]:
    raise SystemExit("FAIL: grid glyphs in identity chip")
print("IDENTITY_DISPLAY_OK")
PY

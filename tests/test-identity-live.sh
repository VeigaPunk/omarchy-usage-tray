#!/usr/bin/env bash
# Opt-in live round-trip. Always leaves host slot on gmail.
set -euo pipefail

if [[ "${AI_USAGE_LIVE_SWAP:-}" != "1" ]]; then
  echo LIVE_SWAP_SKIP
  exit 0
fi

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BIN="$ROOT/bin/ai-usage"
SWAP="${HOME}/.local/bin/token-plan-swap"
CONF="${XDG_CONFIG_HOME:-$HOME/.config}/alibaba-token-plan"
BAILIAN="${HOME}/.bailian/config.json"
[[ -x "$SWAP" ]] || { echo "FAIL: token-plan-swap missing" >&2; exit 1; }

TMP="$(mktemp -d)"
chmod 700 "$TMP"
trap 'restore_gmail' EXIT

restore_gmail() {
  "$SWAP" gmail >/dev/null
  rm -rf "$TMP"
}

python3 - "$CONF" "$BAILIAN" "$TMP" <<'PY'
import hashlib, json, os, shutil, sys
from pathlib import Path

conf = Path(sys.argv[1])
bailian = Path(sys.argv[2])
bak = Path(sys.argv[3])
active = (conf / "active").read_text().strip()
api = json.loads(bailian.read_text())["token-plan"]["api_key"]
h_api = hashlib.sha256(api.strip().encode()).hexdigest()[:16]
h_active = hashlib.sha256((conf / "keys" / active).read_bytes().strip()).hexdigest()[:16]
if h_api != h_active:
    raise SystemExit(f"FAIL: pre-swap bailian does not match keys/{active}")
print("LIVE_PRECHECK_OK", active)
PY

START="$(tr -d '[:space:]' <"$CONF/active")"
export AI_USAGE_CACHE="$TMP/status.json"
export AI_USAGE_SELECTED="$TMP/selected"
printf 'token-plan\n' >"$AI_USAGE_SELECTED"
python3 - "$BIN" <<'PY'
import json, os, sys
from pathlib import Path
Path(os.environ["AI_USAGE_CACHE"]).write_text(json.dumps({
    "version": 1,
    "updated_at": "2026-08-23T00:00:00Z",
    "selected": "token-plan",
    "providers": {
        "token-plan": {
            "id": "token-plan",
            "name": "Token Plan",
            "logo": "T",
            "status": "ok",
            "windows": [{"kind": "weekly", "label": "Weekly", "used_pct": 1}],
        }
    },
}))
os.chmod(os.environ["AI_USAGE_CACHE"], 0o600)
PY

OUT="$("$BIN" identity next)"
NEW="$(tr -d '[:space:]' <"$CONF/active")"
if [[ "$NEW" == "$START" ]]; then
  echo "FAIL: live toggle did not change active (still $NEW)" >&2
  exit 1
fi
if [[ "$OUT" != "$NEW" ]]; then
  echo "FAIL: stdout $OUT vs active $NEW" >&2
  exit 1
fi

python3 - "$CONF" "$BAILIAN" "$NEW" <<'PY'
import hashlib, json, sys
from pathlib import Path
conf, bailian, active = Path(sys.argv[1]), Path(sys.argv[2]), sys.argv[3]
api = json.loads(bailian.read_text())["token-plan"]["api_key"]
h_api = hashlib.sha256(api.strip().encode()).hexdigest()[:16]
h_active = hashlib.sha256((conf / "keys" / active).read_bytes().strip()).hexdigest()[:16]
other = "gmail" if active == "team" else "team"
h_other = hashlib.sha256((conf / "keys" / other).read_bytes().strip()).hexdigest()[:16]
if h_api != h_active:
    raise SystemExit("FAIL: live bailian sha != keys/$active")
if h_api == h_other:
    raise SystemExit("FAIL: live bailian sha matches the other slot")
print("LIVE_SHA_OK")
PY

"$SWAP" gmail >/dev/null
FINAL="$(tr -d '[:space:]' <"$CONF/active")"
if [[ "$FINAL" != "gmail" ]]; then
  echo "FAIL: expected leave-gmail, active=$FINAL" >&2
  exit 1
fi
python3 - "$CONF" "$BAILIAN" <<'PY'
import hashlib, json, sys
from pathlib import Path
conf, bailian = Path(sys.argv[1]), Path(sys.argv[2])
api = json.loads(bailian.read_text())["token-plan"]["api_key"]
h_api = hashlib.sha256(api.strip().encode()).hexdigest()[:16]
h_gmail = hashlib.sha256((conf / "keys" / "gmail").read_bytes().strip()).hexdigest()[:16]
if h_api != h_gmail:
    raise SystemExit("FAIL: leave-gmail bailian sha mismatch")
print("LIVE_GMAIL_OK")
PY

echo LIVE_SWAP_OK

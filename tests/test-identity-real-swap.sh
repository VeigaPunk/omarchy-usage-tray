#!/usr/bin/env bash
# Isolated real helper: identity next must flip active + bailian, never host files.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BIN="$ROOT/bin/ai-usage"
SWAP="${AI_USAGE_TOKEN_PLAN_SWAP:-$HOME/.local/bin/token-plan-swap}"
[[ -x "$SWAP" ]] || { echo "FAIL: token-plan-swap missing at $SWAP" >&2; exit 1; }

HOST_ACTIVE="$HOME/.config/alibaba-token-plan/active"
HOST_BEFORE=""
if [[ -f "$HOST_ACTIVE" ]]; then
  HOST_BEFORE="$(tr -d '[:space:]' <"$HOST_ACTIVE")"
fi

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

export HOME="$TMP/home"
export XDG_CONFIG_HOME="$HOME/.config"
export XDG_CACHE_HOME="$HOME/.cache"
export PATH="/usr/bin:/bin"
mkdir -p "$HOME/.config/alibaba-token-plan/keys" "$HOME/.bailian" "$HOME/.cache/ai-usage" "$HOME/.config/ai-usage"

CONF="$HOME/.config/alibaba-token-plan"
cat >"$CONF/slots" <<'EOF'
team|local://team|DashScope Token Plan Team|team
gmail|local://gmail|Alibaba Cloud Token Plan|gmail
EOF
printf 'team\n' >"$CONF/active"
# Distinct synthetic keys — must not match secret-pattern (no sk- prefix).
printf 'synth-team-aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa' >"$CONF/keys/team"
printf 'synth-gmail-bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb' >"$CONF/keys/gmail"
chmod 700 "$CONF" "$CONF/keys"
chmod 600 "$CONF/slots" "$CONF/active" "$CONF/keys/team" "$CONF/keys/gmail"

export AI_USAGE_TOKEN_PLAN_SWAP="$SWAP"
export AI_USAGE_TOKEN_PLAN_CONF="$CONF"
export AI_USAGE_CACHE="$HOME/.cache/ai-usage/status.json"
export AI_USAGE_SELECTED="$HOME/.config/ai-usage/selected"
printf 'token-plan\n' >"$AI_USAGE_SELECTED"

python3 - "$BIN" <<'PY'
import json, os, subprocess, sys
from pathlib import Path

bin_path = sys.argv[1]
cache = {
    "version": 1,
    "updated_at": "2026-08-23T00:00:00Z",
    "selected": "token-plan",
    "providers": {
        "token-plan": {
            "id": "token-plan",
            "name": "Token Plan",
            "logo": "T",
            "status": "ok",
            "windows": [
                {"kind": "weekly", "label": "Weekly", "used_pct": 41},
                {"kind": "session", "label": "5h", "used_pct": 17},
            ],
        }
    },
}
Path(os.environ["AI_USAGE_CACHE"]).write_text(json.dumps(cache))
os.chmod(os.environ["AI_USAGE_CACHE"], 0o600)

first = subprocess.check_output([bin_path, "identity", "next"], text=True).strip()
if first != "gmail":
    raise SystemExit(f"FAIL: first toggle stdout {first!r} want gmail")
second = subprocess.check_output([bin_path, "identity", "next"], text=True).strip()
if second != "team":
    raise SystemExit(f"FAIL: second toggle stdout {second!r} want team")
print("TOGGLE_STDOUT_OK")
PY

python3 - <<'PY'
import hashlib, json, os, sys
from pathlib import Path

conf = Path(os.environ["AI_USAGE_TOKEN_PLAN_CONF"])
home = Path(os.environ["HOME"])
active = (conf / "active").read_text().strip()
cache = json.loads(Path(os.environ["AI_USAGE_CACHE"]).read_text())
rec = cache["providers"]["token-plan"]

def sha(b: bytes) -> str:
    return hashlib.sha256(b.strip()).hexdigest()[:16]

api = json.loads((home / ".bailian/config.json").read_text())["token-plan"]["api_key"]
h_api = sha(api.encode() if isinstance(api, str) else api)
pairs = {s: sha((conf / "keys" / s).read_bytes()) for s in ("team", "gmail")}
other = "gmail" if active == "team" else "team"
if h_api != pairs[active]:
    raise SystemExit("FAIL: bailian sha does not match keys/$active")
if h_api == pairs[other]:
    raise SystemExit("FAIL: bailian sha matches the other slot")
if pairs["team"] == pairs["gmail"]:
    raise SystemExit("FAIL: synthetic keys are not distinct")
if any("used_pct" in w for w in rec.get("windows") or [] if isinstance(w, dict)):
    raise SystemExit("FAIL: used_pct survived identity next")
if rec.get("status") != "unknown":
    raise SystemExit(f"FAIL: status {rec.get('status')!r} want unknown")
if rec.get("identity", {}).get("id") != active:
    raise SystemExit(f"FAIL: cache identity {rec.get('identity')} vs active {active}")
print("BAILIAN_SHA_OK")
print("METERS_BLANK_OK")
PY

out="$("$BIN" waybar)"
python3 - "$out" <<'PY'
import json, os, sys
payload = json.loads(sys.argv[1])
active = open(os.environ["AI_USAGE_TOKEN_PLAN_CONF"] + "/active").read().strip()
text = payload["text"]
if active not in text:
    raise SystemExit(f"FAIL: chip missing slot {active}: {text!r}")
if "—" not in text:
    raise SystemExit(f"FAIL: chip still has meters after swap: {text!r}")
print("WAYBAR_HONEST_OK")
PY

if [[ -n "$HOST_BEFORE" ]]; then
  HOST_AFTER="$(tr -d '[:space:]' <"$HOST_ACTIVE")"
  if [[ "$HOST_AFTER" != "$HOST_BEFORE" ]]; then
    echo "FAIL: host active mutated $HOST_BEFORE -> $HOST_AFTER" >&2
    exit 1
  fi
fi

echo IDENTITY_REAL_SWAP_OK

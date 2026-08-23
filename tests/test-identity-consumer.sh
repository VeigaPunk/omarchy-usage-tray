#!/usr/bin/env bash
# Isolated consumer-follow: after toggle, codex-token-plan loads keys/$active (sha only).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BIN="$ROOT/bin/ai-usage"
REAL_LOCAL="${AI_USAGE_REAL_LOCAL:-$HOME/.local/bin}"
SWAP="${AI_USAGE_TOKEN_PLAN_SWAP:-$REAL_LOCAL/token-plan-swap}"
CODEX_TP="${AI_USAGE_CODEX_TOKEN_PLAN:-$REAL_LOCAL/codex-token-plan}"
TP_KEY="${AI_USAGE_TOKEN_PLAN_KEY:-$REAL_LOCAL/token-plan-key}"
[[ -x "$SWAP" && -x "$CODEX_TP" && -x "$TP_KEY" ]] || {
  echo "FAIL: host helpers missing" >&2
  exit 1
}

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
mkdir -p "$HOME/.config/alibaba-token-plan/keys" "$HOME/.bailian" \
  "$HOME/.cache/ai-usage" "$HOME/.config/ai-usage" "$TMP/bin"

CONF="$HOME/.config/alibaba-token-plan"
cat >"$CONF/slots" <<'EOF'
team|local://team|DashScope Token Plan Team|team
gmail|local://gmail|Alibaba Cloud Token Plan|gmail
EOF
printf 'team\n' >"$CONF/active"
printf 'synth-team-aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa' >"$CONF/keys/team"
printf 'synth-gmail-bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb' >"$CONF/keys/gmail"
chmod 700 "$CONF" "$CONF/keys"
chmod 600 "$CONF/slots" "$CONF/active" "$CONF/keys/team" "$CONF/keys/gmail"

export AI_USAGE_TOKEN_PLAN_SWAP="$SWAP"
export AI_USAGE_TOKEN_PLAN_CONF="$CONF"
export AI_USAGE_CACHE="$HOME/.cache/ai-usage/status.json"
export AI_USAGE_SELECTED="$HOME/.config/ai-usage/selected"
export AI_USAGE_CONSUMER_LOG="$TMP/consumer.log"
printf 'token-plan\n' >"$AI_USAGE_SELECTED"

cat >"$TMP/bin/codex" <<'SH'
#!/usr/bin/env bash
python3 - <<'PY'
import hashlib, os
from pathlib import Path
key = os.environ.get("BAILIAN_TOKEN_PLAN_API_KEY", "")
digest = hashlib.sha256(key.strip().encode()).hexdigest()[:16]
Path(os.environ["AI_USAGE_CONSUMER_LOG"]).write_text(f"sha16={digest}\n")
PY
exit 0
SH
chmod +x "$TMP/bin/codex"

# Real token-plan-key + stub codex. Do not print key material.
export PATH="$TMP/bin:$REAL_LOCAL:/usr/bin:/bin"

python3 - "$BIN" <<'PY'
import json, os, subprocess, sys
from pathlib import Path
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
            "windows": [{"kind": "weekly", "label": "Weekly", "used_pct": 9}],
        }
    },
}
Path(os.environ["AI_USAGE_CACHE"]).write_text(json.dumps(cache))
os.chmod(os.environ["AI_USAGE_CACHE"], 0o600)
out = subprocess.check_output([sys.argv[1], "identity", "next"], text=True).strip()
if out != "gmail":
    raise SystemExit(f"FAIL: identity next -> {out!r}")
print("CONSUMER_TOGGLE_OK")
PY

# Invoke host wrapper; stub codex records env sha. Discard wrapper stdout.
"$CODEX_TP" qwen38 exec --help >/dev/null

python3 - <<'PY'
import hashlib, os, sys
from pathlib import Path

conf = Path(os.environ["AI_USAGE_TOKEN_PLAN_CONF"])
active = (conf / "active").read_text().strip()
if active != "gmail":
    raise SystemExit(f"FAIL: active {active!r} want gmail")
want = hashlib.sha256((conf / "keys" / active).read_bytes().strip()).hexdigest()[:16]
log = Path(os.environ["AI_USAGE_CONSUMER_LOG"]).read_text().strip()
if log != f"sha16={want}":
    raise SystemExit(f"FAIL: consumer log {log!r} want sha16={want}")
print("CONSUMER_SHA_OK")
PY

if [[ -n "$HOST_BEFORE" ]]; then
  HOST_AFTER="$(tr -d '[:space:]' <"$HOST_ACTIVE")"
  if [[ "$HOST_AFTER" != "$HOST_BEFORE" ]]; then
    echo "FAIL: host active mutated $HOST_BEFORE -> $HOST_AFTER" >&2
    exit 1
  fi
fi

echo IDENTITY_CONSUMER_OK

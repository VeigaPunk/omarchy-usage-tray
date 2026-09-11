#!/usr/bin/env bash
# Token Plan route swaps preserve OMP fleet usage; other providers remain no-ops.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BIN="$ROOT/bin/ai-usage"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
export HOME="$TMP/home"
export XDG_CACHE_HOME="$TMP/cache-home"
export XDG_CONFIG_HOME="$TMP/config-home"
export XDG_STATE_HOME="$TMP/state-home"
export AI_USAGE_CACHE="$TMP/status.json"
export AI_USAGE_SELECTED="$TMP/selected"
export AI_USAGE_TOKEN_PLAN_CONF="$TMP/tp"
export PATH="$TMP/bin:/usr/bin:/bin"
mkdir -p "$TMP/bin" "$TMP/tp" "$HOME"
printf 'team\n' >"$TMP/tp/active"
cat >"$TMP/tp/slots" <<'EOF'
team|local://team|Team|team
gmail|local://gmail|Gmail|gmail
EOF

cat >"$AI_USAGE_CACHE" <<'JSON'
{
  "version": 1,
  "selected": "token-plan",
  "providers": {
    "codex": {"id": "codex", "status": "ok", "windows": []},
    "token-plan": {
      "id": "token-plan",
      "name": "Token Plan",
      "logo": "T",
      "status": "ok",
      "windows": [
        {"kind": "weekly", "label": "3-account average", "used_pct": 1.209},
        {"kind": "special", "label": "Hottest account", "used_pct": 3.627}
      ],
      "account_usage": [
        {"used_pct": 0, "fetched_at": "2100-01-01T00:00:00Z"},
        {"used_pct": 3.627, "fetched_at": "2100-01-01T00:01:00Z"},
        {"used_pct": 0, "fetched_at": "2100-01-01T00:02:00Z"}
      ],
      "capacity": {
        "accounts": 3,
        "used_accounts": 0.036270291301975,
        "remaining_accounts": 2.963729708698025
      },
      "snapshot": {
        "reports": 3,
        "accounts_without_usage": 0,
        "disabled_credentials": 0
      },
      "measured_at": "2100-01-01T00:00:00Z",
      "identity": {"id": "team", "label": "team", "title": "Team"}
    }
  }
}
JSON
printf 'token-plan\n' >"$AI_USAGE_SELECTED"

cat >"$TMP/bin/token-plan-swap" <<'SH'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"$AI_USAGE_SWAP_LOG"
printf 'gmail\n' >"$AI_USAGE_TOKEN_PLAN_CONF/active"
SH
chmod +x "$TMP/bin/token-plan-swap"
export AI_USAGE_SWAP_LOG="$TMP/swap.log"
export AI_USAGE_TOKEN_PLAN_SWAP="$TMP/bin/token-plan-swap"
python3 - "$AI_USAGE_CACHE" "$TMP/fleet-before.json" <<'PY'
import json
import sys

with open(sys.argv[1], encoding="utf-8") as fh:
    rec = json.load(fh)["providers"]["token-plan"]
fleet = {
    key: rec[key]
    for key in ("windows", "account_usage", "capacity", "snapshot", "measured_at")
}
with open(sys.argv[2], "w", encoding="utf-8") as fh:
    json.dump(fleet, fh, sort_keys=True)
PY

out="$("$BIN" identity next 2>&1)"
[[ "$out" == gmail ]]
[[ "$out" != *synth-* ]]
[[ "$(cat "$AI_USAGE_SWAP_LOG")" == toggle ]]

python3 - "$AI_USAGE_CACHE" "$TMP/fleet-before.json" <<'PY'
import json
import sys

with open(sys.argv[1], encoding="utf-8") as fh:
    rec = json.load(fh)["providers"]["token-plan"]
with open(sys.argv[2], encoding="utf-8") as fh:
    before = json.load(fh)
after = {
    key: rec[key]
    for key in ("windows", "account_usage", "capacity", "snapshot", "measured_at")
}
if after != before:
    raise SystemExit("FAIL: successful route swap changed OMP fleet usage")
if rec.get("status") != "ok":
    raise SystemExit("FAIL: successful route swap changed fleet status")
identity = rec.get("identity") or {}
if identity.get("id") != "gmail":
    raise SystemExit("FAIL: active route metadata did not change to gmail")
PY

printf 'codex\n' >"$AI_USAGE_SELECTED"
cp "$AI_USAGE_CACHE" "$TMP/cache-before-non-token.json"
"$BIN" identity next >/dev/null
[[ "$(wc -l <"$AI_USAGE_SWAP_LOG")" == 1 ]]
cmp -s "$AI_USAGE_CACHE" "$TMP/cache-before-non-token.json"

# A failing helper may emit key material on both streams. identity-next must
# report only its exit status, never relay helper output.
cat >"$TMP/bin/token-plan-swap" <<'SH'
#!/usr/bin/env bash
printf '%s\n' 'synth-stdout-key-material'
printf '%s\n' 'synth-stderr-key-material' >&2
exit 23
SH
chmod +x "$TMP/bin/token-plan-swap"
printf 'token-plan\n' >"$AI_USAGE_SELECTED"
cp "$AI_USAGE_CACHE" "$TMP/cache-before-failure.json"
set +e
out="$("$BIN" identity next 2>&1)"
rc=$?
set -e
[[ "$rc" == 23 ]]
[[ "$out" == *'swap-failed: exit 23'* ]]
[[ "$out" != *synth-* ]]
cmp -s "$AI_USAGE_CACHE" "$TMP/cache-before-failure.json"

echo IDENTITY_CYCLE_OK

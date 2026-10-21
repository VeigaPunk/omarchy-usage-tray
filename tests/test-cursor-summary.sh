#!/usr/bin/env bash
# Cursor: Included / Auto / API meters from the usage summary signed with
# OMP's Cursor login, and the OMP-only Auto / API fallback when it fails.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BIN="$ROOT/bin/ai-usage"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

export HOME="$TMP/home"
export XDG_CACHE_HOME="$TMP/cache-home"
export XDG_CONFIG_HOME="$TMP/config-home"
export XDG_STATE_HOME="$TMP/state-home"
export AI_USAGE_CACHE="$TMP/status.json"
export AI_USAGE_SELECTED="$TMP/selected"
export AI_USAGE_OMP_BIN="$TMP/fake-omp"
export AI_USAGE_CURSOR_OAUTH_CONF="$TMP/no-cursor-oauth"
export AI_USAGE_CURSOR_SUMMARY_URL="file://$TMP/usage-summary.json"
export PATH="/usr/bin:/bin"
mkdir -p "$HOME"
printf 'cursor\n' >"$AI_USAGE_SELECTED"

# Header {"alg":"none"}, payload {"sub":"auth0|synth-user"}, fake signature.
printf '%s\n' 'eyJhbGciOiJub25lIn0.eyJzdWIiOiJhdXRoMHxzeW50aC11c2VyIn0.c2ln' >"$TMP/token"

cat >"$AI_USAGE_OMP_BIN" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
if [[ "$1" == token ]]; then
  [[ "$2" == cursor ]]
  [[ "${SYNTH_TOKEN_FAIL:-}" == 1 ]] && exit 3
  cat "$(dirname "$0")/token"
  exit 0
fi
[[ "$*" == "usage --provider cursor --json" ]]
cat <<'JSON'
{
  "reports": [
    {
      "provider": "cursor",
      "fetchedAt": 4102444800000,
      "metadata": {"email": "synth@example.com"},
      "limits": [
        {"id": "cursor:usd:individual-auto", "window": {"id": "monthly", "resetsAt": 4105036800000}, "amount": {"usedFraction": 0.126, "unit": "percent"}},
        {"id": "cursor:usd:individual-api", "window": {"id": "monthly", "resetsAt": 4105036800000}, "amount": {"used": 400, "limit": 400, "usedFraction": 1, "unit": "usd"}}
      ]
    }
  ],
  "accountsWithoutUsage": [],
  "disabledCredentials": []
}
JSON
SH
chmod +x "$AI_USAGE_OMP_BIN"

cat >"$TMP/usage-summary.json" <<'JSON'
{
  "billingCycleEnd": "2100-01-31T00:00:00.000Z",
  "membershipType": "ultra",
  "individualUsage": {
    "plan": {"enabled": true, "autoPercentUsed": 12.6, "apiPercentUsed": 100, "totalPercentUsed": 15.5}
  }
}
JSON

cursor_windows() {
  python3 - "$AI_USAGE_CACHE" <<'PY'
import json, sys
rec = json.load(open(sys.argv[1]))["providers"]["cursor"]
print(rec.get("plan") or "-")
for w in rec["windows"]:
    print(f'{w["label"]}={w.get("used_pct")}')
print("rows=" + ",".join(r["label"] for r in rec["account_usage"]))
PY
}

"$BIN" probe cursor >/dev/null 2>&1 || true
got="$(cursor_windows)"
want=$'Ultra\nIncluded=15.5\nAuto=12.6\nAPI=100\nHottest=100\nrows=Included,Auto,API'
[[ "$got" == "$want" ]] || fail "summary meters: got $got"
tooltip="$("$BIN" waybar | python3 -c 'import json,sys; print(json.load(sys.stdin)["tooltip"])')"
[[ "$tooltip" == *Included* && "$tooltip" == *Auto* && "$tooltip" == *API* ]] || fail "tooltip lacks meters: $tooltip"
text="$("$BIN" waybar | python3 -c 'import json,sys; print(json.load(sys.stdin)["text"])')"
[[ "$text" != *—* ]] || fail "chip text has no Included meter: $text"
grep -q 'c2ln' "$AI_USAGE_CACHE" && fail "token leaked into cache"

SYNTH_TOKEN_FAIL=1 "$BIN" probe cursor >/dev/null 2>&1 || true
got="$(cursor_windows)"
want=$'-\nAuto=12.6\nAPI=100\nHottest=100\nrows=Auto,API'
[[ "$got" == "$want" ]] || fail "OMP fallback meters: got $got"

echo CURSOR_SUMMARY_OK

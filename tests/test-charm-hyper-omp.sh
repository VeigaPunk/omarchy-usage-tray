#!/usr/bin/env bash
# Charm Hyper counter: one isolated OMP probe, a prepaid balance in the cache,
# cache-only Waybar rendering, and last-good retention across a failed probe.
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
export AI_USAGE_OMP_LOG="$TMP/omp.log"
export AI_USAGE_FALLBACK_LOG="$TMP/fallback.log"
export PATH="/usr/bin:/bin"
mkdir -p "$HOME/.local/bin"
printf 'charm-hyper\n' >"$AI_USAGE_SELECTED"
# If the override is ignored, these sentinels fail closed instead of reaching a live CLI.
cat >"$HOME/.local/bin/omp" <<'SH'
#!/usr/bin/env bash
printf '%s\n' "$0 $*" >>"$AI_USAGE_FALLBACK_LOG"
exit 97
SH
cp "$HOME/.local/bin/omp" "$HOME/.local/bin/bl"
chmod +x "$HOME/.local/bin/omp" "$HOME/.local/bin/bl"

cat >"$AI_USAGE_OMP_BIN" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$*" >>"$AI_USAGE_OMP_LOG"
if [[ "${AI_USAGE_CH_FAIL:-}" == 1 ]]; then
  printf '%s\n' 'synth-ch-failure-stderr-secret' >&2
  printf '%s\n' 'synth-ch-failure-stdout-secret'
  exit 42
fi
printf '%s\n' 'synth-ch-stderr-secret' >&2
[[ "$#" == 4 ]]
[[ "$1" == usage ]]
[[ "$2" == --provider ]]
[[ "$3" == charm-hyper ]]
[[ "$4" == --json ]]
if [[ "${AI_USAGE_CH_PARTIAL:-}" == 1 ]]; then
  cat <<'JSON'
{
  "generatedAt": 4102444800000,
  "reports": [
    {
      "provider": "charm-hyper",
      "fetchedAt": 4102444800000,
      "metadata": {"endpoint": "https://hyper.charm.land/v1/credits", "source": "synth-ch-metadata-secret"},
      "limits": [
        {"id": "charm-hyper:credits", "label": "Credit balance", "scope": {"provider": "charm-hyper", "windowId": "balance", "shared": true}, "amount": {"remaining": 238, "unit": "credits"}}
      ]
    },
    {
      "provider": "charm-hyper",
      "limits": []
    }
  ],
  "accountsWithoutUsage": [],
  "disabledCredentials": [],
  "capacity": {}
}
JSON
  exit 0
fi
if [[ "${AI_USAGE_CH_ZERO:-}" == 1 ]]; then
  cat <<'JSON'
{
  "generatedAt": 4102444800000,
  "reports": [
    {
      "provider": "charm-hyper",
      "fetchedAt": 4102444920000,
      "metadata": {"endpoint": "https://hyper.charm.land/v1/credits"},
      "limits": [
        {"id": "charm-hyper:credits", "label": "Credit balance", "scope": {"provider": "charm-hyper", "windowId": "balance", "shared": true}, "amount": {"remaining": 0, "unit": "credits"}}
      ]
    }
  ],
  "accountsWithoutUsage": [],
  "disabledCredentials": [],
  "capacity": {}
}
JSON
  exit 0
fi
cat <<'JSON'
{
  "generatedAt": 4102444800000,
  "reports": [
    {
      "provider": "charm-hyper",
      "fetchedAt": 4102444800000,
      "metadata": {"endpoint": "https://hyper.charm.land/v1/credits", "source": "synth-ch-metadata-secret"},
      "limits": [
        {"id": "charm-hyper:credits", "label": "Credit balance", "scope": {"provider": "charm-hyper", "windowId": "balance", "shared": true}, "amount": {"remaining": 238, "unit": "credits"}}
      ]
    },
    {
      "provider": "charm-hyper",
      "fetchedAt": 4102444860000,
      "metadata": {"source": "synth-ch-metadata-secret"},
      "limits": [
        {"id": "charm-hyper:credits", "label": "Credit balance", "scope": {"provider": "charm-hyper", "windowId": "balance", "shared": true}, "amount": {"remaining": 12, "unit": "credits"}}
      ]
    }
  ],
  "accountsWithoutUsage": [],
  "disabledCredentials": [],
  "capacity": {
    "charm-hyper": [
      {"window": "balance", "accounts": 2, "usedAccounts": 0, "remainingAccounts": 2, "metadata": {"private": "synth-ch-capacity-secret"}}
    ]
  }
}
JSON
SH
chmod +x "$AI_USAGE_OMP_BIN"

probe_output="$("$BIN" probe charm-hyper 2>&1)"
[[ "$probe_output" == *'charm-hyper ok credits=250'* ]] || fail "probe did not report the summed Charm Hyper balance"
[[ "$probe_output" != *synth-* ]] || fail "probe relayed secret-bearing OMP output"
[[ "$(wc -l <"$AI_USAGE_OMP_LOG")" == 1 ]] || fail "OMP was not invoked exactly once"
[[ ! -e "$AI_USAGE_FALLBACK_LOG" ]] || fail "probe ignored AI_USAGE_OMP_BIN or fell back to bl"
[[ "$(cat "$AI_USAGE_OMP_LOG")" == 'usage --provider charm-hyper --json' ]] || fail "unexpected OMP command"

python3 - "$AI_USAGE_CACHE" <<'PY'
import json
import sys

with open(sys.argv[1], encoding="utf-8") as fh:
    cache = json.load(fh)
rec = cache["providers"]["charm-hyper"]
assert rec["status"] == "ok", rec
assert rec["name"] == "Charm Hyper" and rec["logo"] == "H", rec
assert rec["windows"] == [
    {"kind": "credits", "label": "Credit balance", "extra": {"remaining_credits": 250}}
], rec["windows"]
assert rec["credits"] == {"remaining": 250}, rec["credits"]
assert rec["measured_at"] == "2100-01-01T00:00:00Z", rec
assert rec["account_usage"] == [
    {"fetched_at": "2100-01-01T00:00:00Z", "remaining_credits": 238},
    {"fetched_at": "2100-01-01T00:01:00Z", "remaining_credits": 12},
], rec["account_usage"]
assert rec["snapshot"] == {
    "reports": 2,
    "accounts_without_usage": 0,
    "disabled_credentials": 0,
}, rec["snapshot"]
assert "reason" not in rec, rec
encoded = json.dumps(cache, sort_keys=True)
for forbidden in (
    "synth-ch-metadata-secret",
    "synth-ch-capacity-secret",
    "synth-ch-stderr-secret",
    "synth-ch-failure",
    "hyper.charm.land",
):
    assert forbidden not in encoded, forbidden
PY

# Rendering must consume only the cache. Any second OMP invocation is a failure.
waybar_json="$("$BIN" waybar 2>&1)"
[[ "$(wc -l <"$AI_USAGE_OMP_LOG")" == 1 ]] || fail "Waybar rendering invoked OMP"

python3 - "$waybar_json" <<'PY'
import json
import sys

payload = json.loads(sys.argv[1])
assert payload["alt"] == "charm-hyper", payload
assert payload["text"] == "H 250cr", payload["text"]
assert "bgcolor=" not in payload["text"], payload["text"]
assert payload["class"] == "ok", payload
tooltip = payload["tooltip"]
for expected in (
    "Charm Hyper",
    "credits: 250 left",
    "measured: 2100-01-01T00:00:00Z",
    "snapshot 1: 238 credits · fetched: 2100-01-01T00:00:00Z",
    "snapshot 2: 12 credits · fetched: 2100-01-01T00:01:00Z",
    "snapshot coverage: 2 reports · 0 without usage · 0 disabled",
):
    assert expected in tooltip, (expected, tooltip)
for forbidden in ("synth-ch", "hyper.charm.land"):
    assert forbidden not in sys.argv[1], forbidden
PY

export AI_USAGE_CH_FAIL=1
failure_output="$("$BIN" probe charm-hyper 2>&1)"
[[ "$failure_output" == *'charm-hyper unknown exit_42'* ]] || fail "failed OMP probe hid its bounded error"
[[ "$failure_output" != *synth-* ]] || fail "failed OMP probe relayed child output"
[[ "$(wc -l <"$AI_USAGE_OMP_LOG")" == 2 ]] || fail "failed probe invoked OMP more than once"

retained_waybar="$("$BIN" waybar 2>&1)"
[[ "$(wc -l <"$AI_USAGE_OMP_LOG")" == 2 ]] || fail "Waybar invoked OMP after a retained error"
python3 - "$AI_USAGE_CACHE" "$retained_waybar" <<'PY'
import json
import sys

with open(sys.argv[1], encoding="utf-8") as fh:
    rec = json.load(fh)["providers"]["charm-hyper"]
assert rec["status"] == "ok", rec
assert rec["last_error"] == "exit_42", rec
assert rec["credits"] == {"remaining": 250}, rec["credits"]
waybar = json.loads(sys.argv[2])
assert waybar["text"] == "H 250cr", waybar["text"]
assert "last error: exit_42" in waybar["tooltip"], waybar
assert "credits: 250 left (last good)" in waybar["tooltip"], waybar
assert "synth-ch" not in json.dumps(waybar), waybar
PY

unset AI_USAGE_CH_FAIL
export AI_USAGE_CH_PARTIAL=1
partial_output="$("$BIN" probe charm-hyper 2>&1)"
[[ "$partial_output" == *'charm-hyper unknown partial_balance'* ]] || fail "a half-answered fleet was not held back"
[[ "$(wc -l <"$AI_USAGE_OMP_LOG")" == 3 ]] || fail "partial probe invoked OMP more than once"
partial_waybar="$("$BIN" waybar 2>&1)"
[[ "$(wc -l <"$AI_USAGE_OMP_LOG")" == 3 ]] || fail "cache consumers invoked OMP for partial data"
python3 - "$AI_USAGE_CACHE" "$partial_waybar" <<'PY'
import json
import sys

with open(sys.argv[1], encoding="utf-8") as fh:
    rec = json.load(fh)["providers"]["charm-hyper"]
assert rec["status"] == "ok", rec
assert rec["last_error"] == "partial_balance", rec
assert rec["credits"] == {"remaining": 250}, rec["credits"]
waybar = json.loads(sys.argv[2])
assert "partial_balance" in waybar["tooltip"], waybar
assert "credits: 250 left (last good)" in waybar["tooltip"], waybar
PY

unset AI_USAGE_CH_PARTIAL
export AI_USAGE_CH_ZERO=1
zero_output="$("$BIN" probe charm-hyper 2>&1)"
[[ "$zero_output" == *'charm-hyper ok credits=0'* ]] || fail "an exhausted balance was not reported"
zero_waybar="$("$BIN" waybar 2>&1)"
python3 - "$AI_USAGE_CACHE" "$zero_waybar" <<'PY'
import json
import sys

with open(sys.argv[1], encoding="utf-8") as fh:
    rec = json.load(fh)["providers"]["charm-hyper"]
assert rec["status"] == "ok" and rec["credits"] == {"remaining": 0}, rec
waybar = json.loads(sys.argv[2])
assert waybar["text"] == "H 0cr", waybar["text"]
assert "critical" in waybar["class"].split(), waybar
assert "credits: 0 left" in waybar["tooltip"], waybar
PY

unset AI_USAGE_CH_ZERO
export AI_USAGE_CHARM_HYPER_LOW_CREDITS=300
floor_output="$("$BIN" probe charm-hyper 2>&1)"
[[ "$floor_output" == *'charm-hyper ok credits=250'* ]] || fail "floor probe lost the balance"
floor_waybar="$("$BIN" waybar 2>&1)"
python3 - "$floor_waybar" <<'PY'
import json
import sys

waybar = json.loads(sys.argv[1])
assert waybar["class"] == "ok warn", waybar
assert "warn below 300 credits" in waybar["tooltip"], waybar
PY
unset AI_USAGE_CHARM_HYPER_LOW_CREDITS

"$BIN" validate || fail "cache with a Charm Hyper row failed validation"

echo CHARM_HYPER_OMP_OK
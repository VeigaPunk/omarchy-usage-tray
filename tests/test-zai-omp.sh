#!/usr/bin/env bash
# Z.ai behavior: one isolated OMP probe, per-account credit windows, cache-only Waybar.
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
printf 'zai\n' >"$AI_USAGE_SELECTED"
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
if [[ "${AI_USAGE_ZAI_FAIL:-}" == 1 ]]; then
  printf '%s\n' 'synth-zai-failure-stderr-secret' >&2
  printf '%s\n' 'synth-zai-failure-stdout-secret'
  exit 42
fi
printf '%s\n' 'synth-zai-stderr-secret' >&2
[[ "$#" == 4 ]]
[[ "$1" == usage ]]
[[ "$2" == --provider ]]
[[ "$3" == zai ]]
[[ "$4" == --json ]]
if [[ "${AI_USAGE_ZAI_PARTIAL:-}" == 1 ]]; then
  cat <<'JSON'
{
  "reports": [
    {
      "provider": "zai",
      "fetchedAt": 4102444800000,
      "limits": [
        {"id": "zai:credits:5h", "window": {"id": "5h", "resetsAt": 4102448400000}, "amount": {"usedFraction": 0.5, "unit": "credits"}, "status": "ok"},
        {"id": "zai:credits:1w", "window": {"id": "1w", "resetsAt": 4103049600000}, "amount": {"usedFraction": 0.1, "unit": "credits"}, "status": "ok"}
      ]
    },
    {
      "provider": "zai",
      "fetchedAt": 4102444860000,
      "limits": []
    }
  ],
  "accountsWithoutUsage": [],
  "disabledCredentials": [],
  "capacity": {
    "zai": [
      {"window": "5h", "accounts": 2, "usedAccounts": 1.4, "remainingAccounts": 0.6},
      {"window": "7d", "accounts": 2, "usedAccounts": 0.3, "remainingAccounts": 1.7}
    ]
  }
}
JSON
  exit 0
fi
cat <<'JSON'
{
  "generatedAt": 4102444920000,
  "reports": [
    {
      "provider": "zai",
      "fetchedAt": 4102444800000,
      "metadata": {
        "source": "synth-zai-metadata-secret",
        "planType": "pro",
        "email": "synth-zai-email-secret@example.com",
        "endpoint": "https://api.z.ai/api/monitor/usage/quota/limit"
      },
      "limits": [
        {"id": "zai:credits:5h", "label": "ZAI 5 Hours Credit Quota", "window": {"id": "5h", "resetsAt": 4102448400000}, "amount": {"used": 6000, "limit": 12000, "remaining": 6000, "usedFraction": 0.5, "unit": "credits"}, "status": "ok"},
        {"id": "zai:credits:1w", "label": "ZAI Weekly Credit Quota", "window": {"id": "1w", "resetsAt": 4103049600000}, "amount": {"used": 6000, "limit": 60000, "remaining": 54000, "usedFraction": 0.1, "unit": "credits"}, "status": "ok"}
      ]
    },
    {
      "provider": "zai",
      "fetchedAt": 4102444860000,
      "metadata": {"source": "synth-zai-metadata-secret", "planType": "pro"},
      "limits": [
        {"id": "zai:credits:5h", "label": "ZAI 5 Hours Credit Quota", "window": {"id": "5h", "resetsAt": 4102452000000}, "amount": {"used": 10800, "limit": 12000, "remaining": 1200, "usedFraction": 0.9, "unit": "credits"}, "status": "ok"},
        {"id": "zai:credits:1w", "label": "ZAI Weekly Credit Quota", "window": {"id": "1w", "resetsAt": 4103049600000}, "amount": {"used": 12000, "limit": 60000, "remaining": 48000, "usedFraction": 0.2, "unit": "credits"}, "status": "ok"}
      ]
    }
  ],
  "accountsWithoutUsage": [],
  "disabledCredentials": [],
  "capacity": {
    "zai": [
      {"window": "5h", "accounts": 2, "usedAccounts": 1.4, "remainingAccounts": 0.6},
      {"window": "7d", "accounts": 2, "usedAccounts": 0.3, "remainingAccounts": 1.7}
    ]
  }
}
JSON
SH
chmod +x "$AI_USAGE_OMP_BIN"

probe_output="$("$BIN" probe zai 2>&1)"
[[ "$probe_output" == *'zai ok'* ]] || fail "probe did not report Z.ai ready"
[[ "$probe_output" != *synth-* ]] || fail "probe relayed secret-bearing OMP output"
[[ "$(wc -l <"$AI_USAGE_OMP_LOG")" == 1 ]] || fail "OMP was not invoked exactly once"
[[ ! -e "$AI_USAGE_FALLBACK_LOG" ]] || fail "probe ignored AI_USAGE_OMP_BIN or fell back to bl"
[[ "$(cat "$AI_USAGE_OMP_LOG")" == 'usage --provider zai --json' ]] || fail "unexpected OMP command"

python3 - "$AI_USAGE_CACHE" <<'PY'
import json
import sys

with open(sys.argv[1], encoding="utf-8") as fh:
    cache = json.load(fh)
rec = cache["providers"]["zai"]
assert rec["status"] == "ok", rec
assert rec["name"] == "Z.ai" and rec["logo"] == "Z", rec
assert rec["windows"] == [
    {"kind": "weekly", "label": "2-account weekly", "used_pct": 15, "resets_at": "2100-01-08T00:00:00Z"},
    {"kind": "session", "label": "2-account 5 Hour", "used_pct": 70, "resets_at": "2100-01-01T01:00:00Z"},
    {"kind": "special", "label": "Hottest account", "used_pct": 90, "resets_at": "2100-01-01T02:00:00Z"},
], rec["windows"]
assert rec["measured_at"] == "2100-01-01T00:00:00Z", rec
usage = rec["account_usage"]
assert [row.get("used_pct") for row in usage] == [50, 90], usage
assert [row.get("label") for row in usage] == ["5 Hour limit", "5 Hour limit"], usage
assert [row.get("windows", {}).get("weekly", {}).get("used_pct") for row in usage] == [10, 20], usage
assert [row.get("windows", {}).get("session", {}).get("used_pct") for row in usage] == [50, 90], usage
assert usage[0]["windows"]["session"]["label"] == "5h", usage[0]
assert [row.get("fetched_at") for row in usage] == [
    "2100-01-01T00:00:00Z",
    "2100-01-01T00:01:00Z",
], usage
assert rec["snapshot"] == {
    "reports": 2,
    "accounts_without_usage": 0,
    "disabled_credentials": 0,
}, rec["snapshot"]
assert "reason" not in rec, rec
encoded = json.dumps(cache, sort_keys=True)
for forbidden in (
    "synth-zai-metadata-secret",
    "synth-zai-email-secret",
    "synth-zai-stderr-secret",
    "synth-zai-failure",
    "api.z.ai/api/monitor",
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
assert payload["alt"] == "zai", payload
assert payload["text"].startswith("Z "), payload["text"]
# weekly 15% fills one cell (fill+track), hottest 90% fills five (fill+track).
assert payload["text"].count("bgcolor=") == 4, payload["text"]
classes = payload["class"].split()
assert "ok" in classes and "warn" in classes, classes
tooltip = payload["tooltip"]
for expected in (
    "Z.ai",
    "2-account weekly: 15%",
    "2-account 5 Hour: 70%",
    "Hottest account: 90%",
    "snapshot 1: 50% · 5 Hour limit · 5h 50% · 7d 10% · fetched: 2100-01-01T00:00:00Z",
    "snapshot 2: 90% · 5 Hour limit · 5h 90% · 7d 20% · fetched: 2100-01-01T00:01:00Z",
    "reset 2100-01-01T02:00:00Z",
    "snapshot coverage: 2 reports · 0 without usage · 0 disabled",
):
    assert expected in tooltip, (expected, tooltip)
for forbidden in ("synth-zai", "api.z.ai"):
    assert forbidden not in sys.argv[1], forbidden
PY

export AI_USAGE_ZAI_FAIL=1
failure_output="$("$BIN" probe zai 2>&1)"
[[ "$failure_output" == *'zai unknown exit_42'* ]] || fail "failed OMP probe hid its bounded error"
[[ "$failure_output" != *synth-* ]] || fail "failed OMP probe relayed child output"
[[ "$(wc -l <"$AI_USAGE_OMP_LOG")" == 2 ]] || fail "failed probe invoked OMP more than once"

retained_waybar="$("$BIN" waybar 2>&1)"
[[ "$(wc -l <"$AI_USAGE_OMP_LOG")" == 2 ]] || fail "Waybar invoked OMP after a retained error"
python3 - "$AI_USAGE_CACHE" "$retained_waybar" <<'PY'
import json
import sys

with open(sys.argv[1], encoding="utf-8") as fh:
    rec = json.load(fh)["providers"]["zai"]
assert rec["status"] == "ok", rec
assert rec["last_error"] == "exit_42", rec
assert rec["windows"][0]["used_pct"] == 15, rec["windows"]
waybar = json.loads(sys.argv[2])
assert "last error: exit_42" in waybar["tooltip"], waybar
assert "synth-zai" not in json.dumps(waybar), waybar
PY

unset AI_USAGE_ZAI_FAIL
export AI_USAGE_ZAI_PARTIAL=1
partial_output="$("$BIN" probe zai 2>&1)"
[[ "$partial_output" == *'zai ok partial_usage'* ]] || fail "partial OMP probe lost its usable averages"
[[ "$(wc -l <"$AI_USAGE_OMP_LOG")" == 3 ]] || fail "partial probe invoked OMP more than once"
partial_waybar="$("$BIN" waybar 2>&1)"
[[ "$(wc -l <"$AI_USAGE_OMP_LOG")" == 3 ]] || fail "cache consumers invoked OMP for partial data"
python3 - "$AI_USAGE_CACHE" "$partial_waybar" <<'PY'
import json
import sys

with open(sys.argv[1], encoding="utf-8") as fh:
    rec = json.load(fh)["providers"]["zai"]
assert rec["status"] == "ok", rec
assert rec["reason"] == "partial_usage", rec
assert "measured_at" not in rec, rec
assert rec["windows"] == [
    {"kind": "weekly", "label": "1-account weekly", "used_pct": 10, "resets_at": "2100-01-08T00:00:00Z"},
    {"kind": "session", "label": "1-account 5 Hour", "used_pct": 50, "resets_at": "2100-01-01T01:00:00Z"},
    {"kind": "special", "label": "Hottest account"},
], rec["windows"]
assert [row.get("used_pct") for row in rec["account_usage"]] == [50, None], rec["account_usage"]
assert rec["account_usage"][1] == {"fetched_at": "2100-01-01T00:01:00Z"}, rec["account_usage"][1]
waybar = json.loads(sys.argv[2])
assert "partial_usage" in waybar["tooltip"], waybar
assert "Hottest account: —" in waybar["tooltip"], waybar
assert "snapshot 2: — · fetched: 2100-01-01T00:01:00Z" in waybar["tooltip"], waybar
PY

"$BIN" validate || fail "cache with Z.ai rows failed validation"

echo ZAI_OMP_OK

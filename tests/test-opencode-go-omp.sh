#!/usr/bin/env bash
# OpenCode Go behavior: one isolated OMP probe, per-account windows, cache-only Waybar.
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
printf 'opencode-go\n' >"$AI_USAGE_SELECTED"
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
if [[ "${AI_USAGE_OCG_FAIL:-}" == 1 ]]; then
  printf '%s\n' 'synth-ocg-failure-stderr-secret' >&2
  printf '%s\n' 'synth-ocg-failure-stdout-secret'
  exit 42
fi
printf '%s\n' 'synth-ocg-stderr-secret' >&2
[[ "$#" == 4 ]]
[[ "$1" == usage ]]
[[ "$2" == --provider ]]
[[ "$3" == opencode-go ]]
[[ "$4" == --json ]]
if [[ "${AI_USAGE_OCG_PARTIAL:-}" == 1 ]]; then
  cat <<'JSON'
{
  "reports": [
    {
      "provider": "opencode-go",
      "fetchedAt": 4102444800000,
      "metadata": {"source": "synth-ocg-metadata-secret", "planType": "OpenCode Go"},
      "limits": [
        {"id": "rolling-5h", "window": {"id": "5h", "resetsAt": 4102444920000}, "amount": {"usedFraction": 0.01}, "status": "ok"},
        {"id": "weekly", "window": {"id": "7d", "resetsAt": 4102444800000}, "amount": {"usedFraction": 0}, "status": "ok"},
        {"id": "monthly", "window": {"id": "monthly", "resetsAt": 4102444860000}, "amount": {"usedFraction": 0.99}, "status": "warning"}
      ]
    },
    {
      "provider": "opencode-go",
      "fetchedAt": 4102444860000,
      "limits": []
    },
    {
      "provider": "opencode-go",
      "fetchedAt": 4102444920000,
      "limits": [
        {"id": "rolling-5h", "window": {"id": "5h", "resetsAt": 4102445040000}, "amount": {"usedFraction": 0.1}, "status": "ok"},
        {"id": "weekly", "window": {"id": "7d", "resetsAt": 4102444920000}, "amount": {"usedFraction": 0.04}, "status": "ok"},
        {"id": "monthly", "window": {"id": "monthly", "resetsAt": 4102444980000}, "amount": {"usedFraction": 0.25}, "status": "ok"}
      ]
    }
  ],
  "accountsWithoutUsage": [],
  "disabledCredentials": [],
  "capacity": {
    "opencode-go": [
      {"window": "5h", "accounts": 3, "usedAccounts": 0.11, "remainingAccounts": 2.89},
      {"window": "7d", "accounts": 3, "usedAccounts": 0.04, "remainingAccounts": 2.96},
      {"window": "Monthly", "accounts": 3, "usedAccounts": 1.24, "remainingAccounts": 1.76}
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
      "provider": "opencode-go",
      "fetchedAt": 4102444800000,
      "metadata": {
        "source": "synth-ocg-metadata-secret",
        "planType": "OpenCode Go",
        "endpoint": "https://opencode.ai/zen/go/v1/usage"
      },
      "limits": [
        {"id": "rolling-5h", "label": "5 Hour limit", "window": {"id": "5h", "resetsAt": 4102444920000}, "amount": {"usedFraction": 0.01, "unit": "percent"}, "status": "ok"},
        {"id": "weekly", "label": "Weekly limit", "window": {"id": "7d", "resetsAt": 4102444800000}, "amount": {"usedFraction": 0, "unit": "percent"}, "status": "ok"},
        {"id": "monthly", "label": "Monthly limit", "window": {"id": "monthly", "resetsAt": 4102444860000}, "amount": {"usedFraction": 0.99, "unit": "percent"}, "status": "warning"}
      ]
    },
    {
      "provider": "opencode-go",
      "fetchedAt": 4102444860000,
      "metadata": {"source": "synth-ocg-metadata-secret", "planType": "OpenCode Go"},
      "limits": [
        {"id": "rolling-5h", "label": "5 Hour limit", "window": {"id": "5h", "resetsAt": 4102444980000}, "amount": {"usedFraction": 0}, "status": "ok"},
        {"id": "weekly", "label": "Weekly limit", "window": {"id": "7d", "resetsAt": 4102444860000}, "amount": {"usedFraction": 0.02}, "status": "ok"},
        {"id": "monthly", "label": "Monthly limit", "window": {"id": "monthly", "resetsAt": 4102444920000}, "amount": {"usedFraction": 0}, "status": "ok"}
      ]
    },
    {
      "provider": "opencode-go",
      "fetchedAt": 4102444920000,
      "metadata": {"source": "synth-ocg-metadata-secret", "planType": "OpenCode Go"},
      "limits": [
        {"id": "rolling-5h", "label": "5 Hour limit", "window": {"id": "5h", "resetsAt": 4102445040000}, "amount": {"usedFraction": 0.1}, "status": "ok"},
        {"id": "weekly", "label": "Weekly limit", "window": {"id": "7d", "resetsAt": 4102444920000}, "amount": {"usedFraction": 0.04}, "status": "ok"},
        {"id": "monthly", "label": "Monthly limit", "window": {"id": "monthly", "resetsAt": 4102444980000}, "amount": {"usedFraction": 0.25}, "status": "ok"}
      ]
    }
  ],
  "accountsWithoutUsage": [],
  "disabledCredentials": [],
  "capacity": {
    "opencode-go": [
      {"window": "5h", "accounts": 3, "usedAccounts": 0.11, "remainingAccounts": 2.89},
      {"window": "7d", "accounts": 3, "usedAccounts": 0.06, "remainingAccounts": 2.94},
      {"window": "Monthly", "accounts": 3, "usedAccounts": 1.24, "remainingAccounts": 1.76, "metadata": {"private": "synth-ocg-capacity-secret"}}
    ]
  }
}
JSON
SH
chmod +x "$AI_USAGE_OMP_BIN"

probe_output="$("$BIN" probe opencode-go 2>&1)"
[[ "$probe_output" == *'opencode-go ok'* ]] || fail "probe did not report OpenCode Go ready"
[[ "$probe_output" != *synth-* ]] || fail "probe relayed secret-bearing OMP output"
[[ "$(wc -l <"$AI_USAGE_OMP_LOG")" == 1 ]] || fail "OMP was not invoked exactly once"
[[ ! -e "$AI_USAGE_FALLBACK_LOG" ]] || fail "probe ignored AI_USAGE_OMP_BIN or fell back to bl"
[[ "$(cat "$AI_USAGE_OMP_LOG")" == 'usage --provider opencode-go --json' ]] || fail "unexpected OMP command"

python3 - "$AI_USAGE_CACHE" <<'PY'
import json
import sys

with open(sys.argv[1], encoding="utf-8") as fh:
    cache = json.load(fh)
rec = cache["providers"]["opencode-go"]
assert rec["status"] == "ok", rec
assert rec["name"] == "OpenCode Go" and rec["logo"] == "O", rec
assert rec["windows"] == [
    {"kind": "weekly", "label": "3-account weekly", "used_pct": 2, "resets_at": "2100-01-01T00:00:00Z"},
    {"kind": "session", "label": "3-account 5 Hour", "used_pct": 3.6667, "resets_at": "2100-01-01T00:02:00Z"},
    {"kind": "monthly", "label": "3-account monthly", "used_pct": 41.3333, "resets_at": "2100-01-01T00:01:00Z"},
    {"kind": "special", "label": "Hottest account", "used_pct": 99, "resets_at": "2100-01-01T00:01:00Z"},
], rec["windows"]
assert rec["measured_at"] == "2100-01-01T00:00:00Z", rec
usage = rec["account_usage"]
assert [row.get("used_pct") for row in usage] == [99, 2, 25], usage
assert [row.get("label") for row in usage] == ["Monthly limit", "Weekly limit", "Monthly limit"], usage
assert [row.get("windows", {}).get("weekly", {}).get("used_pct") for row in usage] == [0, 2, 4], usage
assert [row.get("windows", {}).get("session", {}).get("used_pct") for row in usage] == [1, 0, 10], usage
assert usage[0]["windows"]["monthly"]["label"] == "monthly", usage[0]
assert [row.get("fetched_at") for row in usage] == [
    "2100-01-01T00:00:00Z",
    "2100-01-01T00:01:00Z",
    "2100-01-01T00:02:00Z",
], usage
assert rec["snapshot"] == {
    "reports": 3,
    "accounts_without_usage": 0,
    "disabled_credentials": 0,
}, rec["snapshot"]
assert "reason" not in rec, rec
encoded = json.dumps(cache, sort_keys=True)
for forbidden in (
    "synth-ocg-metadata-secret",
    "synth-ocg-capacity-secret",
    "synth-ocg-stderr-secret",
    "synth-ocg-failure",
    "opencode.ai/zen/go",
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
assert payload["alt"] == "opencode-go", payload
assert payload["text"].startswith("O "), payload["text"]
assert payload["text"].count("bgcolor=") == 3, payload["text"]
classes = payload["class"].split()
assert "ok" in classes and "critical" in classes, classes
tooltip = payload["tooltip"]
for expected in (
    "OpenCode Go",
    "3-account weekly: 2%",
    "3-account 5 Hour: 3.6667%",
    "3-account monthly: 41.3333%",
    "Hottest account: 99%",
    "snapshot 1: 99% · Monthly limit · 5h 1% · 7d 0% · monthly 99% · fetched: 2100-01-01T00:00:00Z",
    "snapshot 2: 2% · Weekly limit · 5h 0% · 7d 2% · monthly 0%",
    "snapshot 3: 25% · Monthly limit · 5h 10% · 7d 4% · monthly 25%",
    "reset 26761d:",
    "snapshot coverage: 3 reports · 0 without usage · 0 disabled",
):
    assert expected in tooltip, (expected, tooltip)
for forbidden in ("synth-ocg", "opencode.ai/zen/go"):
    assert forbidden not in sys.argv[1], forbidden
PY

export AI_USAGE_OCG_FAIL=1
failure_output="$("$BIN" probe opencode-go 2>&1)"
[[ "$failure_output" == *'opencode-go unknown exit_42'* ]] || fail "failed OMP probe hid its bounded error"
[[ "$failure_output" != *synth-* ]] || fail "failed OMP probe relayed child output"
[[ "$(wc -l <"$AI_USAGE_OMP_LOG")" == 2 ]] || fail "failed probe invoked OMP more than once"

retained_waybar="$("$BIN" waybar 2>&1)"
[[ "$(wc -l <"$AI_USAGE_OMP_LOG")" == 2 ]] || fail "Waybar invoked OMP after a retained error"
python3 - "$AI_USAGE_CACHE" "$retained_waybar" <<'PY'
import json
import sys

with open(sys.argv[1], encoding="utf-8") as fh:
    rec = json.load(fh)["providers"]["opencode-go"]
assert rec["status"] == "ok", rec
assert rec["last_error"] == "exit_42", rec
assert rec["windows"][0]["used_pct"] == 2, rec["windows"]
waybar = json.loads(sys.argv[2])
assert "last error: exit_42" in waybar["tooltip"], waybar
assert "synth-ocg" not in json.dumps(waybar), waybar
PY

unset AI_USAGE_OCG_FAIL
export AI_USAGE_OCG_PARTIAL=1
partial_output="$("$BIN" probe opencode-go 2>&1)"
[[ "$partial_output" == *'opencode-go ok partial_usage'* ]] || fail "partial OMP probe lost its usable averages"
[[ "$(wc -l <"$AI_USAGE_OMP_LOG")" == 3 ]] || fail "partial probe invoked OMP more than once"
partial_waybar="$("$BIN" waybar 2>&1)"
[[ "$(wc -l <"$AI_USAGE_OMP_LOG")" == 3 ]] || fail "cache consumers invoked OMP for partial data"
python3 - "$AI_USAGE_CACHE" "$partial_waybar" <<'PY'
import json
import sys

with open(sys.argv[1], encoding="utf-8") as fh:
    rec = json.load(fh)["providers"]["opencode-go"]
assert rec["status"] == "ok", rec
assert rec["reason"] == "partial_usage", rec
assert "measured_at" not in rec, rec
assert rec["windows"] == [
    {"kind": "weekly", "label": "2-account weekly", "used_pct": 2, "resets_at": "2100-01-01T00:00:00Z"},
    {"kind": "session", "label": "2-account 5 Hour", "used_pct": 5.5, "resets_at": "2100-01-01T00:02:00Z"},
    {"kind": "monthly", "label": "2-account monthly", "used_pct": 62, "resets_at": "2100-01-01T00:01:00Z"},
    {"kind": "special", "label": "Hottest account"},
], rec["windows"]
assert [row.get("used_pct") for row in rec["account_usage"]] == [99, None, 25], rec["account_usage"]
assert rec["account_usage"][1] == {"fetched_at": "2100-01-01T00:01:00Z"}, rec["account_usage"][1]
waybar = json.loads(sys.argv[2])
assert "partial_usage" in waybar["tooltip"], waybar
assert "Hottest account: —" in waybar["tooltip"], waybar
assert "snapshot 2: — · fetched: 2100-01-01T00:01:00Z" in waybar["tooltip"], waybar
PY

"$BIN" validate || fail "cache with OpenCode Go rows failed validation"

echo OPENCODE_GO_OMP_OK

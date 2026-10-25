#!/usr/bin/env bash
# Command Code: one isolated OMP probe over several credentials, shared org
# balance pools, cache-only Waybar rendering, and last-good retention.
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
printf 'commandcode\n' >"$AI_USAGE_SELECTED"
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
if [[ "${AI_USAGE_CC_FAIL:-}" == 1 ]]; then
  printf '%s\n' 'synth-cc-failure-stderr-secret' >&2
  printf '%s\n' 'synth-cc-failure-stdout-secret'
  exit 42
fi
printf '%s\n' 'synth-cc-stderr-secret' >&2
[[ "$#" == 4 ]]
[[ "$1" == usage ]]
[[ "$2" == --provider ]]
[[ "$3" == commandcode ]]
[[ "$4" == --json ]]
if [[ "${AI_USAGE_CC_PARTIAL:-}" == 1 ]]; then
  cat <<'JSON'
{
  "generatedAt": 4102444920000,
  "reports": [
    {
      "provider": "commandcode",
      "fetchedAt": 4102444800000,
      "metadata": {"accountId": "synth-cc-account-1", "email": "synth-cc-email-1@example.com"},
      "limits": [
        {"id": "commandcode:5h", "label": "5-hour limit", "scope": {"provider": "commandcode", "accountId": "synth-cc-account-1", "windowId": "5h", "shared": true}, "window": {"id": "5h", "resetsAt": 4102448400000}, "amount": {"usedFraction": 0.1, "unit": "credits"}, "status": "ok"},
        {"id": "commandcode:7d", "label": "Weekly limit", "scope": {"provider": "commandcode", "accountId": "synth-cc-account-1", "windowId": "7d", "shared": true}, "window": {"id": "7d", "resetsAt": 4103049600000}, "amount": {"usedFraction": 0.2, "unit": "credits"}, "status": "ok"},
        {"id": "commandcode:balance", "label": "Credit balance", "scope": {"provider": "commandcode", "accountId": "synth-cc-account-1", "windowId": "balance", "shared": true}, "amount": {"remaining": 50, "unit": "credits"}}
      ]
    },
    {
      "provider": "commandcode",
      "fetchedAt": 4102444860000,
      "metadata": {"accountId": "synth-cc-account-2"},
      "limits": [
        {"id": "commandcode:5h", "window": {"id": "5h", "resetsAt": 4102452000000}, "amount": {"usedFraction": 0.2, "unit": "credits"}, "status": "ok"},
        {"id": "commandcode:7d", "window": {"id": "7d", "resetsAt": 4103049600000}, "amount": {"usedFraction": 0.4, "unit": "credits"}, "status": "ok"}
      ]
    }
  ],
  "accountsWithoutUsage": [],
  "disabledCredentials": [],
  "capacity": {
    "commandcode": [
      {"window": "5h", "accounts": 2, "usedAccounts": 0, "remainingAccounts": 2},
      {"window": "7d", "accounts": 2, "usedAccounts": 0, "remainingAccounts": 2}
    ]
  }
}
JSON
  exit 0
fi
if [[ "${AI_USAGE_CC_OVERDRAWN:-}" == 1 ]]; then
  # Live shape: two credentials past their weekly cap answer usedFraction > 1.
  cat <<'JSON'
{
  "generatedAt": 4102444920000,
  "reports": [
    {"provider": "commandcode", "fetchedAt": 4102444800000, "limits": [
      {"id": "commandcode:5h", "amount": {"used": 0, "limit": 14, "usedFraction": 0, "unit": "credits"}, "status": "ok"},
      {"id": "commandcode:7d", "window": {"id": "7d", "resetsAt": 4103049600000}, "amount": {"used": 35.17, "limit": 35, "usedFraction": 1.0049, "unit": "credits"}, "status": "exhausted"},
      {"id": "commandcode:balance", "scope": {"accountId": "synth-cc-a"}, "amount": {"remaining": 34.83, "unit": "credits"}}
    ]},
    {"provider": "commandcode", "fetchedAt": 4102444800000, "limits": [
      {"id": "commandcode:5h", "amount": {"used": 0, "limit": 14, "usedFraction": 0, "unit": "credits"}, "status": "ok"},
      {"id": "commandcode:7d", "window": {"id": "7d", "resetsAt": 4103049600000}, "amount": {"used": 35.1, "limit": 35, "usedFraction": 1.0029, "unit": "credits"}, "status": "exhausted"},
      {"id": "commandcode:balance", "scope": {"accountId": "synth-cc-b"}, "amount": {"remaining": 34.9, "unit": "credits"}}
    ]},
    {"provider": "commandcode", "fetchedAt": 4102444800000, "limits": [
      {"id": "commandcode:5h", "amount": {"used": 0, "limit": 14, "usedFraction": 0, "unit": "credits"}, "status": "ok"},
      {"id": "commandcode:7d", "amount": {"used": 0, "limit": 35, "usedFraction": 0, "unit": "credits"}, "status": "ok"},
      {"id": "commandcode:balance", "scope": {"accountId": "synth-cc-c"}, "amount": {"remaining": 70, "unit": "credits"}}
    ]}
  ],
  "accountsWithoutUsage": [],
  "disabledCredentials": [],
  "capacity": {"commandcode": [{"window": "7d", "accounts": 3}]}
}
JSON
  exit 0
fi
if [[ "${AI_USAGE_CC_EXHAUSTED:-}" == 1 ]]; then
  cat <<'JSON'
{
  "generatedAt": 4102444920000,
  "reports": [
    {
      "provider": "commandcode",
      "fetchedAt": 4102444800000,
      "metadata": {"accountId": "synth-cc-account-1"},
      "limits": [
        {"id": "commandcode:5h", "window": {"id": "5h", "resetsAt": 4102448400000}, "amount": {"usedFraction": 0, "unit": "credits"}, "status": "ok"},
        {"id": "commandcode:7d", "window": {"id": "7d", "resetsAt": 4103049600000}, "amount": {"usedFraction": 0.01, "unit": "credits"}, "status": "ok"},
        {"id": "commandcode:balance", "scope": {"accountId": "synth-cc-account-1", "orgId": "synth-cc-org-1"}, "amount": {"remaining": 0, "unit": "credits"}}
      ]
    },
    {
      "provider": "commandcode",
      "fetchedAt": 4102444860000,
      "metadata": {"accountId": "synth-cc-account-2"},
      "limits": [
        {"id": "commandcode:5h", "window": {"id": "5h", "resetsAt": 4102452000000}, "amount": {"usedFraction": 0, "unit": "credits"}, "status": "ok"},
        {"id": "commandcode:7d", "window": {"id": "7d", "resetsAt": 4103049600000}, "amount": {"usedFraction": 0.02, "unit": "credits"}, "status": "ok"},
        {"id": "commandcode:balance", "scope": {"accountId": "synth-cc-account-2", "orgId": "synth-cc-org-2"}, "amount": {"remaining": -5, "unit": "credits"}}
      ]
    }
  ],
  "accountsWithoutUsage": [],
  "disabledCredentials": [],
  "capacity": {
    "commandcode": [
      {"window": "5h", "accounts": 2, "usedAccounts": 0, "remainingAccounts": 2},
      {"window": "7d", "accounts": 2, "usedAccounts": 0, "remainingAccounts": 2}
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
      "provider": "commandcode",
      "fetchedAt": 4102444800000,
      "metadata": {
        "accountId": "synth-cc-account-1",
        "email": "synth-cc-email-1@example.com",
        "endpoint": "https://api.commandcode.ai/usage"
      },
      "limits": [
        {"id": "commandcode:5h", "label": "5-hour limit", "scope": {"provider": "commandcode", "accountId": "synth-cc-account-1", "windowId": "5h", "shared": true}, "window": {"id": "5h", "label": "5-hour", "durationMs": 18000000, "resetsAt": 4102448400000}, "amount": {"used": 0.7, "limit": 14, "usedFraction": 0.05, "unit": "credits"}, "status": "ok"},
        {"id": "commandcode:7d", "label": "Weekly limit", "scope": {"provider": "commandcode", "accountId": "synth-cc-account-1", "windowId": "7d", "shared": true}, "window": {"id": "7d", "label": "Weekly", "durationMs": 604800000, "resetsAt": 4103049600000}, "amount": {"used": 11.48, "limit": 35, "usedFraction": 0.82, "unit": "credits"}, "status": "ok"},
        {"id": "commandcode:balance", "label": "Credit balance", "scope": {"provider": "commandcode", "accountId": "synth-cc-account-1", "orgId": "synth-cc-org-1", "windowId": "balance", "shared": true}, "amount": {"remaining": 70, "unit": "credits"}}
      ]
    },
    {
      "provider": "commandcode",
      "fetchedAt": 4102444860000,
      "metadata": {"accountId": "synth-cc-account-2", "email": "synth-cc-email-2@example.com"},
      "limits": [
        {"id": "commandcode:5h", "label": "5-hour limit", "scope": {"provider": "commandcode", "accountId": "synth-cc-account-2", "windowId": "5h", "shared": true}, "window": {"id": "5h", "resetsAt": 4102452000000}, "amount": {"usedFraction": 0.02, "unit": "credits"}, "status": "ok"},
        {"id": "commandcode:7d", "label": "Weekly limit", "scope": {"provider": "commandcode", "accountId": "synth-cc-account-2", "windowId": "7d", "shared": true}, "window": {"id": "7d", "resetsAt": 4103049600000}, "amount": {"usedFraction": 0.3, "unit": "credits"}, "status": "ok"},
        {"id": "commandcode:balance", "label": "Credit balance", "scope": {"provider": "commandcode", "accountId": "synth-cc-account-2", "orgId": "synth-cc-org-1", "windowId": "balance", "shared": true}, "amount": {"remaining": 70, "unit": "credits"}}
      ]
    },
    {
      "provider": "commandcode",
      "fetchedAt": 4102444920000,
      "metadata": {"accountId": "synth-cc-account-3"},
      "limits": [
        {"id": "commandcode:5h", "label": "5-hour limit", "scope": {"provider": "commandcode", "accountId": "synth-cc-account-3", "windowId": "5h", "shared": true}, "window": {"id": "5h", "resetsAt": 4102448400000}, "amount": {"usedFraction": 0, "unit": "credits"}, "status": "ok"},
        {"id": "commandcode:7d", "label": "Weekly limit", "scope": {"provider": "commandcode", "accountId": "synth-cc-account-3", "windowId": "7d", "shared": true}, "window": {"id": "7d", "resetsAt": 4103049600000}, "amount": {"usedFraction": 0.12, "unit": "credits"}, "status": "ok"},
        {"id": "commandcode:balance", "label": "Credit balance", "scope": {"provider": "commandcode", "accountId": "synth-cc-account-3", "orgId": "synth-cc-org-2", "windowId": "balance", "shared": true}, "amount": {"remaining": 100, "unit": "credits"}}
      ]
    }
  ],
  "accountsWithoutUsage": [],
  "disabledCredentials": [],
  "capacity": {
    "commandcode": [
      {"window": "5h", "durationMs": 18000000, "accounts": 3, "usedAccounts": 0, "remainingAccounts": 3},
      {"window": "7d", "durationMs": 604800000, "accounts": 3, "usedAccounts": 0, "remainingAccounts": 3}
    ]
  }
}
JSON
SH
chmod +x "$AI_USAGE_OMP_BIN"

probe_output="$("$BIN" probe commandcode 2>&1)"
[[ "$probe_output" == 'commandcode ok weekly=41.3333 session=2.3333 special=82 credits=170' ]] ||
  fail "unexpected probe summary: $probe_output"
[[ "$probe_output" != *synth-* ]] || fail "probe relayed secret-bearing OMP output"
[[ "$(wc -l <"$AI_USAGE_OMP_LOG")" == 1 ]] || fail "OMP was not invoked exactly once"
[[ ! -e "$AI_USAGE_FALLBACK_LOG" ]] || fail "probe ignored AI_USAGE_OMP_BIN or fell back to bl"
[[ "$(cat "$AI_USAGE_OMP_LOG")" == 'usage --provider commandcode --json' ]] ||
  fail "unexpected OMP command"

python3 - "$AI_USAGE_CACHE" <<'PY'
import json
import sys

with open(sys.argv[1], encoding="utf-8") as fh:
    cache = json.load(fh)
rec = cache["providers"]["commandcode"]
assert rec["status"] == "ok", rec
assert rec["name"] == "Command Code" and rec["logo"] == "⌘", rec
assert rec["windows"] == [
    {"kind": "weekly", "label": "3-account weekly", "used_pct": 41.3333, "resets_at": "2100-01-08T00:00:00Z"},
    {"kind": "session", "label": "3-account 5 Hour", "used_pct": 2.3333, "resets_at": "2100-01-01T01:00:00Z"},
    {"kind": "special", "label": "Hottest account", "used_pct": 82, "resets_at": "2100-01-08T00:00:00Z"},
    {"kind": "credits", "label": "Credit balance", "extra": {"remaining_credits": 170}},
], rec["windows"]
# Two credentials share org 1's pool: counted once, never twice.
assert rec["credits"] == {"remaining": 170}, rec["credits"]
assert rec["measured_at"] == "2100-01-01T00:00:00Z", rec
assert "reason" not in rec, rec
assert rec["snapshot"] == {
    "reports": 3,
    "accounts_without_usage": 0,
    "disabled_credentials": 0,
}, rec["snapshot"]
usage = rec["account_usage"]
assert [row.get("label") for row in usage] == ["Weekly limit", "Weekly limit", "Weekly limit"], usage
assert [row.get("used_pct") for row in usage] == [82, 30, 12], usage
assert [row.get("remaining_credits") for row in usage] == [70, 70, 100], usage
assert [row.get("resets_at") for row in usage] == [
    "2100-01-08T00:00:00Z",
    "2100-01-08T00:00:00Z",
    "2100-01-08T00:00:00Z",
], usage
assert all("account" not in row for row in usage), usage
encoded = json.dumps(cache, sort_keys=True)
for forbidden in (
    "synth-cc",
    "@example.com",
    "api.commandcode",
    "accountId",
    "orgId",
    "email",
):
    assert forbidden not in encoded, forbidden
PY

# Rendering must consume only the cache. Any second OMP invocation is a failure.
waybar_json="$("$BIN" waybar 2>&1)"
[[ "$(wc -l <"$AI_USAGE_OMP_LOG")" == 1 ]] || fail "Waybar rendering invoked OMP"

python3 - "$waybar_json" <<'PY'
import json
import re
import sys
import xml.etree.ElementTree as ET

payload = json.loads(sys.argv[1])
assert payload["alt"] == "commandcode", payload
text = payload["text"]
assert text.startswith("⌘ "), text
assert text.endswith(" 170cr"), text
assert text.count("bgcolor=") == 4, text
classes = payload["class"]
# The hottest account reads 82%, which is a warning, not a hard block.
assert "ok" in classes and "warn" in classes, classes
assert "critical" not in classes, classes
tooltip = payload["tooltip"]
# Waybar renders the tooltip as Pango markup; malformed markup shows nothing.
ET.fromstring(f"<t>{tooltip}</t>")
plain = re.sub(r"<[^>]+>", "", tooltip)
lines = [line.rstrip() for line in plain.splitlines()]
assert "3 account reports" in lines, plain
# A balance has no ceiling: a number, not a meter.
assert "Credit balance   170 credits left" in lines, plain
rows = [line for line in lines if line[:3] in (" 1 ", " 2 ", " 3 ")]
assert len(rows) == 3, plain
assert "Weekly · 70 credits left" in plain, plain
assert "Weekly · 100 credits left" in plain, plain
for forbidden in ("synth-cc", "commandcode.ai"):
    assert forbidden not in sys.argv[1], forbidden
PY

export AI_USAGE_CC_EXHAUSTED=1
exhausted_output="$("$BIN" probe commandcode 2>&1)"
[[ "$exhausted_output" == 'commandcode ok weekly=1.5 session=0 special=2 credits=0' ]] ||
  fail "unexpected exhausted summary: $exhausted_output"
[[ "$(wc -l <"$AI_USAGE_OMP_LOG")" == 2 ]] || fail "exhausted probe invoked OMP more than once"
exhausted_waybar="$("$BIN" waybar 2>&1)"
[[ "$(wc -l <"$AI_USAGE_OMP_LOG")" == 2 ]] || fail "cache consumers invoked OMP for exhausted data"
python3 - "$AI_USAGE_CACHE" "$exhausted_waybar" <<'PY'
import json
import sys

with open(sys.argv[1], encoding="utf-8") as fh:
    rec = json.load(fh)["providers"]["commandcode"]
assert rec["status"] == "ok", rec
assert rec["credits"] == {"remaining": 0}, rec["credits"]
assert [row.get("remaining_credits") for row in rec["account_usage"]] == [0, 0], rec["account_usage"]
waybar = json.loads(sys.argv[2])
assert waybar["text"].endswith(" 0cr"), waybar["text"]
# An empty balance is a hard block even though both windows read near idle.
assert "critical" in waybar["class"], waybar
assert "0 credits left" in waybar["tooltip"], waybar
PY

unset AI_USAGE_CC_EXHAUSTED
export AI_USAGE_CC_FAIL=1
failure_output="$("$BIN" probe commandcode 2>&1)"
[[ "$failure_output" == 'commandcode unknown exit_42' ]] || fail "failed OMP probe hid its bounded error: $failure_output"
[[ "$failure_output" != *synth-* ]] || fail "failed OMP probe relayed child output"
[[ "$(wc -l <"$AI_USAGE_OMP_LOG")" == 3 ]] || fail "failed probe invoked OMP more than once"

retained_waybar="$("$BIN" waybar 2>&1)"
[[ "$(wc -l <"$AI_USAGE_OMP_LOG")" == 3 ]] || fail "Waybar invoked OMP after a retained error"
python3 - "$AI_USAGE_CACHE" "$retained_waybar" <<'PY'
import json
import sys

with open(sys.argv[1], encoding="utf-8") as fh:
    rec = json.load(fh)["providers"]["commandcode"]
assert rec["status"] == "ok", rec
assert rec["last_error"] == "exit_42", rec
assert rec["credits"] == {"remaining": 0}, rec["credits"]
waybar = json.loads(sys.argv[2])
assert waybar["text"].endswith(" 0cr"), waybar["text"]
assert "last error: exit_42" in waybar["tooltip"], waybar
assert "synth-cc" not in json.dumps(waybar), waybar
PY

unset AI_USAGE_CC_FAIL
export AI_USAGE_CC_PARTIAL=1
partial_output="$("$BIN" probe commandcode 2>&1)"
[[ "$partial_output" == 'commandcode ok partial_usage weekly=30 session=15 special=40' ]] ||
  fail "unexpected partial summary: $partial_output"
[[ "$(wc -l <"$AI_USAGE_OMP_LOG")" == 4 ]] || fail "partial probe invoked OMP more than once"
partial_waybar="$("$BIN" waybar 2>&1)"
[[ "$(wc -l <"$AI_USAGE_OMP_LOG")" == 4 ]] || fail "cache consumers invoked OMP for partial data"
python3 - "$AI_USAGE_CACHE" "$partial_waybar" <<'PY'
import json
import re
import sys

with open(sys.argv[1], encoding="utf-8") as fh:
    rec = json.load(fh)["providers"]["commandcode"]
assert rec["status"] == "ok", rec
assert rec["reason"] == "partial_usage", rec
# One credential never answered its balance: the total is withheld, not summed.
assert rec["credits"] == {}, rec["credits"]
assert rec["windows"][-1] == {"kind": "credits", "label": "Credit balance"}, rec["windows"]
assert rec["account_usage"][0]["remaining_credits"] == 50, rec["account_usage"]
assert "remaining_credits" not in rec["account_usage"][1], rec["account_usage"]
waybar = json.loads(sys.argv[2])
assert not waybar["text"].endswith("cr"), waybar["text"]
plain = re.sub(r"<[^>]+>", "", waybar["tooltip"])
assert "partial_usage" in plain, plain
line = next(line for line in plain.splitlines() if line.startswith("Credit balance "))
# A withheld balance stays a dash, never an invented zero.
assert line.split()[2:] == ["—", "—"], line
PY
unset AI_USAGE_CC_PARTIAL

export AI_USAGE_CC_OVERDRAWN=1
overdrawn_output="$("$BIN" probe commandcode 2>&1)"
# Over-cap fractions are exhausted accounts, not 1% readings.
[[ "$overdrawn_output" == 'commandcode ok weekly=66.6667 session=0 special=100 credits=140' ]] ||
  fail "overdrawn weekly windows were not read as exhausted: $overdrawn_output"
unset AI_USAGE_CC_OVERDRAWN

"$BIN" validate || fail "cache with Command Code rows failed validation"

echo COMMANDCODE_OMP_OK

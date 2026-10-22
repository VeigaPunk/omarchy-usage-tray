#!/usr/bin/env bash
# Anthropic behavior: one isolated OMP probe, shared walls + per-model caps,
# one chip meter per account, cache-only Waybar.
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
printf 'anthropic\n' >"$AI_USAGE_SELECTED"
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
if [[ "${AI_USAGE_ANTHROPIC_FAIL:-}" == 1 ]]; then
  printf '%s\n' 'synth-anthropic-failure-stderr-secret' >&2
  printf '%s\n' 'synth-anthropic-failure-stdout-secret'
  exit 42
fi
printf '%s\n' 'synth-anthropic-stderr-secret' >&2
[[ "$#" == 4 ]]
[[ "$1" == usage ]]
[[ "$2" == --provider ]]
[[ "$3" == anthropic ]]
[[ "$4" == --json ]]
if [[ "${AI_USAGE_ANTHROPIC_PARTIAL:-}" == 1 ]]; then
  cat <<'JSON'
{
  "reports": [
    {
      "provider": "anthropic",
      "fetchedAt": 4102444800000,
      "limits": [
        {"id": "anthropic:5h", "label": "Claude 5 Hour", "scope": {"provider": "anthropic", "windowId": "5h", "shared": true}, "window": {"id": "5h", "resetsAt": 4102448400000}, "amount": {"usedFraction": 0.53, "unit": "percent"}, "status": "ok"},
        {"id": "anthropic:7d", "label": "Claude 7 Day", "scope": {"provider": "anthropic", "windowId": "7d", "shared": true}, "window": {"id": "7d", "resetsAt": 4103049600000}, "amount": {"usedFraction": 0.11, "unit": "percent"}, "status": "ok"},
        {"id": "anthropic:7d:fable", "label": "Claude 7 Day (Fable)", "scope": {"provider": "anthropic", "windowId": "7d", "tier": "fable"}, "window": {"id": "7d", "resetsAt": 4103049600000}, "amount": {"usedFraction": 0.0, "unit": "percent"}, "status": "ok"}
      ]
    },
    {
      "provider": "anthropic",
      "fetchedAt": 4102444860000,
      "limits": []
    }
  ],
  "accountsWithoutUsage": [{"provider": "anthropic", "type": "oauth"}],
  "disabledCredentials": [],
  "capacity": {
    "anthropic": [
      {"window": "5h", "durationMs": 18000000, "accounts": 2, "usedAccounts": 0.73, "remainingAccounts": 1.27},
      {"window": "7d", "durationMs": 604800000, "accounts": 2, "usedAccounts": 0.51, "remainingAccounts": 1.49},
      {"window": "7d", "durationMs": 604800000, "meter": "fable", "accounts": 2, "usedAccounts": 0.9, "remainingAccounts": 1.1}
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
      "provider": "anthropic",
      "fetchedAt": 4102444800000,
      "metadata": {
        "accountId": "synth-anthropic-account-secret",
        "email": "synth-anthropic-email-secret@example.com",
        "orgId": "synth-anthropic-org-secret",
        "orgName": "synth-anthropic-orgname-secret",
        "endpoint": "https://api.anthropic.com/api/oauth/usage"
      },
      "limits": [
        {"id": "anthropic:5h", "label": "Claude 5 Hour", "scope": {"provider": "anthropic", "windowId": "5h", "shared": true}, "window": {"id": "5h", "resetsAt": 4102448400000}, "amount": {"used": 53, "limit": 100, "remaining": 47, "usedFraction": 0.53, "unit": "percent"}, "status": "ok"},
        {"id": "anthropic:7d", "label": "Claude 7 Day", "scope": {"provider": "anthropic", "windowId": "7d", "shared": true}, "window": {"id": "7d", "resetsAt": 4103049600000}, "amount": {"used": 11, "limit": 100, "remaining": 89, "usedFraction": 0.11, "unit": "percent"}, "status": "ok"},
        {"id": "anthropic:7d:fable", "label": "Claude 7 Day (Fable)", "scope": {"provider": "anthropic", "windowId": "7d", "tier": "fable"}, "window": {"id": "7d", "resetsAt": 4103049600000}, "amount": {"used": 0, "limit": 100, "remaining": 100, "usedFraction": 0.0, "unit": "percent"}, "status": "ok"},
        {"id": "anthropic:extra", "label": "Extra Usage", "scope": {"provider": "anthropic", "windowId": "extra"}, "window": {"id": "extra", "resetsAt": 4103049600000}, "amount": {"used": 12.5, "limit": 100, "remaining": 87.5, "usedFraction": 0.125, "unit": "usd"}, "status": "ok"}
      ],
      "resetCredits": {"availableCount": 1, "nextCreditId": "synth-anthropic-reset-credit-secret"}
    },
    {
      "provider": "anthropic",
      "fetchedAt": 4102444860000,
      "metadata": {
        "accountId": "synth-anthropic-account-secret-2",
        "email": "synth-anthropic-email-secret@example.com",
        "endpoint": "https://api.anthropic.com/api/oauth/usage"
      },
      "limits": [
        {"id": "anthropic:5h", "label": "Claude 5 Hour", "scope": {"provider": "anthropic", "windowId": "5h", "shared": true}, "window": {"id": "5h", "resetsAt": 4102452000000}, "amount": {"used": 20, "limit": 100, "remaining": 80, "usedFraction": 0.2, "unit": "percent"}, "status": "ok"},
        {"id": "anthropic:7d", "label": "Claude 7 Day", "scope": {"provider": "anthropic", "windowId": "7d", "shared": true}, "window": {"id": "7d", "resetsAt": 4103049600000}, "amount": {"used": 40, "limit": 100, "remaining": 60, "usedFraction": 0.4, "unit": "percent"}, "status": "ok"},
        {"id": "anthropic:7d:fable", "label": "Claude 7 Day (Fable)", "scope": {"provider": "anthropic", "windowId": "7d", "tier": "fable"}, "window": {"id": "7d", "resetsAt": 4103049600000}, "amount": {"used": 90, "limit": 100, "remaining": 10, "usedFraction": 0.9, "unit": "percent"}, "status": "ok"}
      ]
    }
  ],
  "accountsWithoutUsage": [],
  "disabledCredentials": [],
  "capacity": {
    "anthropic": [
      {"window": "5h", "durationMs": 18000000, "accounts": 2, "usedAccounts": 0.73, "remainingAccounts": 1.27},
      {"window": "7d", "durationMs": 604800000, "accounts": 2, "usedAccounts": 0.51, "remainingAccounts": 1.49},
      {"window": "7d", "durationMs": 604800000, "meter": "fable", "accounts": 2, "usedAccounts": 0.9, "remainingAccounts": 1.1}
    ]
  }
}
JSON
SH
chmod +x "$AI_USAGE_OMP_BIN"

probe_output="$("$BIN" probe anthropic 2>&1)"
[[ "$probe_output" == 'anthropic ok weekly=25.5 session=36.5 tier-fable=45 special=90' ]] ||
  fail "probe summary: $probe_output"
[[ "$probe_output" != *synth-* ]] || fail "probe relayed secret-bearing OMP output"
[[ "$(wc -l <"$AI_USAGE_OMP_LOG")" == 1 ]] || fail "OMP was not invoked exactly once"
[[ ! -e "$AI_USAGE_FALLBACK_LOG" ]] || fail "probe ignored AI_USAGE_OMP_BIN or fell back to bl"
[[ "$(cat "$AI_USAGE_OMP_LOG")" == 'usage --provider anthropic --json' ]] || fail "unexpected OMP command"

python3 - "$AI_USAGE_CACHE" <<'PY'
import json
import sys

with open(sys.argv[1], encoding="utf-8") as fh:
    cache = json.load(fh)
rec = cache["providers"]["anthropic"]
assert rec["status"] == "ok", rec
assert rec["name"] == "Anthropic" and rec["logo"] == "A", rec
assert rec["windows"] == [
    {"kind": "weekly", "label": "2-account weekly", "used_pct": 25.5, "resets_at": "2100-01-08T00:00:00Z"},
    {"kind": "session", "label": "2-account 5 Hour", "used_pct": 36.5, "resets_at": "2100-01-01T01:00:00Z"},
    {"kind": "tier-fable", "label": "2-account Fable weekly", "used_pct": 45, "resets_at": "2100-01-08T00:00:00Z"},
    {"kind": "special", "label": "Hottest account", "used_pct": 90, "resets_at": "2100-01-08T00:00:00Z"},
], rec["windows"]
assert rec["measured_at"] == "2100-01-01T00:00:00Z", rec
usage = rec["account_usage"]
assert [row.get("used_pct") for row in usage] == [53, 90], usage
assert [row.get("label") for row in usage] == ["5 Hour limit", "Fable weekly"], usage
assert usage[0]["windows"]["weekly"] == {
    "label": "7d",
    "kind_label": "Weekly limit",
    "used_pct": 11,
    "resets_at": "2100-01-08T00:00:00Z",
}, usage[0]
assert usage[0]["windows"]["session"]["used_pct"] == 53, usage[0]
assert usage[0]["windows"]["tier-fable"] == {
    "label": "Fable 7d",
    "kind_label": "Fable weekly",
    "used_pct": 0,
    "resets_at": "2100-01-08T00:00:00Z",
}, usage[0]
assert [row.get("windows", {}).get("tier-fable", {}).get("used_pct") for row in usage] == [0, 90], usage
assert usage[1]["windows"]["weekly"]["used_pct"] == 40, usage[1]
assert usage[1]["resets_at"] == "2100-01-08T00:00:00Z", usage[1]
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
# Extra Usage is USD spend, not a rate window: no kind, label, or meter for it.
assert "extra" not in json.dumps(rec), rec
encoded = json.dumps(cache, sort_keys=True)
for forbidden in (
    "synth-anthropic-account-secret",
    "synth-anthropic-email-secret",
    "synth-anthropic-org-secret",
    "synth-anthropic-orgname-secret",
    "synth-anthropic-reset-credit-secret",
    "synth-anthropic-stderr-secret",
    "synth-anthropic-failure",
    "api.anthropic.com",
):
    assert forbidden not in encoded, forbidden
PY

# Rendering must consume only the cache. Any second OMP invocation is a failure.
waybar_json="$("$BIN" waybar 2>&1)"
[[ "$(wc -l <"$AI_USAGE_OMP_LOG")" == 1 ]] || fail "Waybar rendering invoked OMP"

python3 - "$waybar_json" "$BIN" <<'PY'
import importlib.machinery
import importlib.util
import json
import re
import sys
import xml.etree.ElementTree as ET

loader = importlib.machinery.SourceFileLoader("ai_usage", sys.argv[2])
spec = importlib.util.spec_from_loader("ai_usage", loader)
mod = importlib.util.module_from_spec(spec)
loader.exec_module(mod)

payload = json.loads(sys.argv[1])
# One meter per account in OMP's report order, each at the window that binds
# it (53% 5-hour, 90% Fable cap) — not the 26% weekly average.
assert payload["text"] == f"A {mod.meter(53)} {mod.meter(90)}", payload["text"]
classes = payload["class"]
assert "ok" in classes and "warn" in classes, classes
tooltip = payload["tooltip"]
ET.fromstring(f"<t>{tooltip}</t>")
plain = re.sub(r"<[^>]+>", "", tooltip).replace("━", "")


def row(prefix):
    return next(line.split() for line in plain.splitlines() if line.startswith(prefix))


assert "26%" in row("Weekly "), plain
assert "37%" in row("5 Hour "), plain
assert "45%" in row("Fable weekly"), plain
assert "90%" in row("Hottest account "), plain
# Per-account rows: percent plus the window that binds that account.
assert row(" 1 ")[1:4] == ["53%", "5", "Hour"], plain
assert row(" 2 ")[1:4] == ["90%", "Fable", "weekly"], plain
for forbidden in ("synth-anthropic", "api.anthropic.com"):
    assert forbidden not in sys.argv[1], forbidden
PY

export AI_USAGE_ANTHROPIC_FAIL=1
failure_output="$("$BIN" probe anthropic 2>&1)"
[[ "$failure_output" == *'anthropic unknown exit_42'* ]] || fail "failed OMP probe hid its bounded error"
[[ "$failure_output" != *synth-* ]] || fail "failed OMP probe relayed child output"
[[ "$(wc -l <"$AI_USAGE_OMP_LOG")" == 2 ]] || fail "failed probe invoked OMP more than once"

retained_waybar="$("$BIN" waybar 2>&1)"
[[ "$(wc -l <"$AI_USAGE_OMP_LOG")" == 2 ]] || fail "Waybar invoked OMP after a retained error"
python3 - "$AI_USAGE_CACHE" "$retained_waybar" <<'PY'
import json
import sys

with open(sys.argv[1], encoding="utf-8") as fh:
    rec = json.load(fh)["providers"]["anthropic"]
assert rec["status"] == "ok", rec
assert rec["last_error"] == "exit_42", rec
assert rec["windows"][0]["used_pct"] == 25.5, rec["windows"]
waybar = json.loads(sys.argv[2])
assert "last error: exit_42" in waybar["tooltip"], waybar
assert "synth-anthropic" not in json.dumps(waybar), waybar
PY

unset AI_USAGE_ANTHROPIC_FAIL
export AI_USAGE_ANTHROPIC_PARTIAL=1
partial_output="$("$BIN" probe anthropic 2>&1)"
[[ "$partial_output" == *'anthropic ok partial_usage'* ]] || fail "partial OMP probe lost its usable averages"
[[ "$(wc -l <"$AI_USAGE_OMP_LOG")" == 3 ]] || fail "partial probe invoked OMP more than once"
partial_waybar="$("$BIN" waybar 2>&1)"
[[ "$(wc -l <"$AI_USAGE_OMP_LOG")" == 3 ]] || fail "cache consumers invoked OMP for partial data"
python3 - "$AI_USAGE_CACHE" "$partial_waybar" "$BIN" <<'PY'
import importlib.machinery
import importlib.util
import json
import re
import sys

loader = importlib.machinery.SourceFileLoader("ai_usage", sys.argv[3])
spec = importlib.util.spec_from_loader("ai_usage", loader)
mod = importlib.util.module_from_spec(spec)
loader.exec_module(mod)

with open(sys.argv[1], encoding="utf-8") as fh:
    rec = json.load(fh)["providers"]["anthropic"]
assert rec["status"] == "ok", rec
assert rec["reason"] == "partial_usage", rec
assert "measured_at" not in rec, rec
assert rec["windows"] == [
    {"kind": "weekly", "label": "1-account weekly", "used_pct": 11, "resets_at": "2100-01-08T00:00:00Z"},
    {"kind": "session", "label": "1-account 5 Hour", "used_pct": 53, "resets_at": "2100-01-01T01:00:00Z"},
    {"kind": "tier-fable", "label": "1-account Fable weekly", "used_pct": 0, "resets_at": "2100-01-08T00:00:00Z"},
    {"kind": "special", "label": "Hottest account"},
], rec["windows"]
assert [row.get("used_pct") for row in rec["account_usage"]] == [53, None], rec["account_usage"]
assert rec["account_usage"][1] == {"fetched_at": "2100-01-01T00:01:00Z"}, rec["account_usage"][1]
waybar = json.loads(sys.argv[2])
assert "partial_usage" in waybar["tooltip"], waybar
# The answered account keeps its meter; the empty report and the credential
# OMP listed without usage stay on the chip as dashes, never as zeros.
assert waybar["text"] == f"A {mod.meter(53)} — —", waybar["text"]
plain = re.sub(r"<[^>]+>", "", waybar["tooltip"]).replace("━", "")
lines = plain.splitlines()
# An unanswered window reads as a dash, never an invented zero.
assert next(line for line in lines if line.startswith("Hottest account ")).split()[2:] == ["—", "—"], plain
assert next(line for line in lines if line.startswith(" 2 ")).split() == ["2", "—", "—"], plain
PY

"$BIN" validate || fail "cache with Anthropic rows failed validation"

echo ANTHROPIC_OMP_OK
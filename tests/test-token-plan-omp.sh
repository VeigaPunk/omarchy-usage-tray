#!/usr/bin/env bash
# OMP Token Plan behavior: one isolated probe, sanitized cache, cache-only Waybar.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BIN="$ROOT/bin/ai-usage"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  exit 1
}

export HOME="$TMP/home"
export XDG_CACHE_HOME="$TMP/cache-home"
export XDG_CONFIG_HOME="$TMP/config-home"
export XDG_STATE_HOME="$TMP/state-home"
export AI_USAGE_CACHE="$TMP/status.json"
export AI_USAGE_SELECTED="$TMP/selected"
export AI_USAGE_TOKEN_PLAN_CONF="$TMP/token-plan"
export AI_USAGE_OMP_BIN="$TMP/fake-omp"
export AI_USAGE_OMP_LOG="$TMP/omp.log"
export AI_USAGE_FALLBACK_LOG="$TMP/fallback.log"
export BAILIAN_TOKEN_PLAN_API_KEY="synth-bailian-env-secret"
export PATH="/usr/bin:/bin"
mkdir -p "$HOME/.local/bin" "$AI_USAGE_TOKEN_PLAN_CONF"
printf 'gmail\n' >"$AI_USAGE_TOKEN_PLAN_CONF/active"
cat >"$AI_USAGE_TOKEN_PLAN_CONF/slots" <<'EOF'
team|local://team|Team|team
gmail|local://gmail|Gmail|gmail
infnet|local://infnet|Infnet|infnet
EOF
printf 'token-plan\n' >"$AI_USAGE_SELECTED"
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
[[ -z "${BAILIAN_TOKEN_PLAN_API_KEY:-}" ]] || exit 96
if [[ "${AI_USAGE_OMP_FAIL:-}" == 1 ]]; then
  printf '%s\n' 'synth-failure-stderr-secret' >&2
  printf '%s\n' 'synth-failure-stdout-secret'
  exit 42
fi
printf '%s\n' 'synth-omp-stderr-secret' >&2
[[ "$#" == 4 ]]
[[ "$1" == usage ]]
[[ "$2" == --provider ]]
[[ "$3" == alibaba-token-plan ]]
[[ "$4" == --json ]]
if [[ "${AI_USAGE_OMP_SHORT:-}" == 1 ]]; then
  cat <<'JSON'
{
  "reports": [
    {
      "provider": "alibaba-token-plan",
      "fetchedAt": 4102444800000,
      "limits": [
        {
          "id": "credits:7d",
          "window": {"id": "7d"},
          "amount": {"usedFraction": 0.1},
          "status": "ok"
        }
      ]
    },
    {
      "provider": "alibaba-token-plan",
      "fetchedAt": 4102444860000,
      "limits": [
        {
          "id": "credits:7d",
          "window": {"id": "7d"},
          "amount": {"usedFraction": 0.2},
          "status": "ok"
        }
      ]
    }
  ],
  "accountsWithoutUsage": [],
  "disabledCredentials": [],
  "capacity": {
    "alibaba-token-plan": [
      {
        "window": "7d",
        "accounts": 3,
        "usedAccounts": 0.3,
        "remainingAccounts": 2.7
      }
    ]
  }
}
JSON
  exit 0
fi
if [[ "${AI_USAGE_OMP_PARTIAL:-}" == 1 ]]; then
  cat <<'JSON'
{
  "reports": [
    {
      "provider": "alibaba-token-plan",
      "fetchedAt": 4102444800000,
      "limits": [
        {
          "id": "credits:7d",
          "window": {"id": "7d"},
          "amount": {"usedFraction": 0},
          "status": "ok"
        }
      ]
    },
    {
      "provider": "alibaba-token-plan",
      "fetchedAt": 4102444860000,
      "limits": []
    },
    {
      "provider": "alibaba-token-plan",
      "fetchedAt": 4102444920000,
      "limits": [
        {
          "id": "credits:7d",
          "window": {"id": "7d"},
          "amount": {"usedFraction": 0.3},
          "status": "ok"
        }
      ]
    }
  ],
  "accountsWithoutUsage": [],
  "disabledCredentials": [],
  "capacity": {
    "alibaba-token-plan": [
      {
        "window": "7d",
        "accounts": 3,
        "usedAccounts": 0.3,
        "remainingAccounts": 2.7
      }
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
      "provider": "alibaba-token-plan",
      "fetchedAt": 4102444800000,
      "metadata": {
        "source": "synth-omp-metadata-secret",
        "credential": "synth-private-route-one"
      },
      "limits": [
        {
          "id": "credits:7d",
          "label": "7 Day Credits",
          "window": {"id": "7d", "durationMs": 604800000},
          "amount": {"usedFraction": 0},
          "status": "ok"
        }
      ]
    },
    {
      "provider": "alibaba-token-plan",
      "fetchedAt": 4102444860000,
      "metadata": {
        "source": "synth-omp-metadata-secret",
        "credential": "synth-private-route-two"
      },
      "limits": [
        {
          "id": "credits:7d",
          "label": "7 Day Credits",
          "window": {"id": "7d", "durationMs": 604800000},
          "amount": {"usedFraction": 0.036270291301974997},
          "status": "ok"
        }
      ]
    },
    {
      "provider": "alibaba-token-plan",
      "fetchedAt": 4102444920000,
      "metadata": {
        "source": "synth-omp-metadata-secret",
        "credential": "synth-private-route-three"
      },
      "limits": [
        {
          "id": "credits:7d",
          "label": "7 Day Credits",
          "window": {"id": "7d", "durationMs": 604800000},
          "amount": {"usedFraction": 0},
          "status": "ok"
        }
      ]
    }
  ],
  "accountsWithoutUsage": [],
  "disabledCredentials": [],
  "capacity": {
    "alibaba-token-plan": [
      {
        "window": "7d",
        "durationMs": 604800000,
        "accounts": 3,
        "usedAccounts": 0.036270291301975,
        "remainingAccounts": 2.963729708698025,
        "metadata": {"private": "synth-capacity-metadata-secret"}
      }
    ]
  }
}
JSON
SH
chmod +x "$AI_USAGE_OMP_BIN"

probe_output="$("$BIN" probe token-plan 2>&1)"
[[ "$probe_output" == *'token-plan ok'* ]] || fail "probe did not report Token Plan ready"
[[ "$probe_output" != *synth-* ]] || fail "probe relayed secret-bearing OMP output"
[[ "$(wc -l <"$AI_USAGE_OMP_LOG")" == 1 ]] || fail "OMP was not invoked exactly once"
[[ ! -e "$AI_USAGE_FALLBACK_LOG" ]] || fail "probe ignored AI_USAGE_OMP_BIN or fell back to bl"
[[ "$(cat "$AI_USAGE_OMP_LOG")" == 'usage --provider alibaba-token-plan --json' ]] || fail "unexpected OMP command"

python3 - "$AI_USAGE_CACHE" <<'PY'
import json
import sys

path = sys.argv[1]
with open(path, encoding="utf-8") as fh:
    cache = json.load(fh)
rec = cache["providers"]["token-plan"]
assert rec["status"] == "ok", rec
assert rec["windows"] == [
    {"kind": "weekly", "label": "3-account average", "used_pct": 1.209},
    {"kind": "special", "label": "Hottest account", "used_pct": 3.627},
], rec["windows"]
assert rec["capacity"] == {
    "accounts": 3,
    "used_accounts": 0.036270291301975,
    "remaining_accounts": 2.963729708698025,
}, rec["capacity"]
assert rec["snapshot"] == {
    "reports": 3,
    "accounts_without_usage": 0,
    "disabled_credentials": 0,
}, rec["snapshot"]
usage = rec["account_usage"]
assert [row.get("used_pct") for row in usage] == [0, 3.627, 0], usage
assert [row.get("fetched_at") for row in usage] == [
    "2100-01-01T00:00:00Z",
    "2100-01-01T00:01:00Z",
    "2100-01-01T00:02:00Z",
], usage
assert rec["measured_at"] == usage[0]["fetched_at"], rec
allowed = {"used_pct", "fetched_at", "resets_at"}
assert all(set(row) <= allowed for row in usage), usage
encoded = json.dumps(cache, sort_keys=True)
for forbidden in (
    "synth-omp-metadata-secret",
    "synth-capacity-metadata-secret",
    "synth-private-route",
    "synth-omp-stderr-secret",
    "synth-bailian-env-secret",
):
    assert forbidden not in encoded, forbidden
PY

# Rendering must consume only the cache. Any second OMP invocation is a failure.
waybar_json="$("$BIN" waybar 2>&1)"
[[ "$(wc -l <"$AI_USAGE_OMP_LOG")" == 1 ]] || fail "Waybar rendering invoked OMP"

python3 - "$waybar_json" <<'PY'
import json
import sys

raw = sys.argv[1]
payload = json.loads(raw)
assert payload["alt"] == "token-plan", payload
assert "ok" in payload["class"].split(), payload
assert payload["text"].startswith("T @gmail "), payload["text"]
assert payload["text"].count("bgcolor=") >= 2, payload["text"]
tooltip = payload["tooltip"]
for expected in (
    "Token Plan",
    "active route: gmail · routing only; not mapped to a snapshot",
    "3-account average: 1.209%",
    "Hottest account: 3.627% · snapshot 2",
    "snapshot 1: 0%",
    "snapshot 2: 3.627%",
    "snapshot 3: 0%",
    "2100-01-01T00:00:00Z",
    "2100-01-01T00:01:00Z",
    "2100-01-01T00:02:00Z",
    "snapshot coverage: 3 reports · 0 without usage · 0 disabled",
    "capacity: 0.036270291301975 / 3 account-equivalents used · 2.963729708698025 remaining",
):
    assert expected in tooltip, (expected, tooltip)
for forbidden in (
    "account 1",
    "gmail: 3.627%",
    "synth-omp-metadata-secret",
    "synth-capacity-metadata-secret",
    "synth-private-route",
    "synth-omp-stderr-secret",
    "synth-bailian-env-secret",
):
    assert forbidden not in raw, forbidden
PY

export AI_USAGE_OMP_FAIL=1
failure_output="$("$BIN" probe token-plan 2>&1)"
[[ "$failure_output" == *'token-plan unknown exit_42'* ]] || fail "failed OMP probe hid its bounded error"
[[ "$failure_output" != *synth-failure* ]] || fail "failed OMP probe relayed child output"
[[ "$(wc -l <"$AI_USAGE_OMP_LOG")" == 2 ]] || fail "failed probe invoked OMP more than once"

retained_waybar="$("$BIN" waybar 2>&1)"
[[ "$(wc -l <"$AI_USAGE_OMP_LOG")" == 2 ]] || fail "Waybar invoked OMP after a retained error"
python3 - "$AI_USAGE_CACHE" "$XDG_STATE_HOME/omarchy/agents/usage/token-plan.json" "$retained_waybar" <<'PY'
import json
import sys

with open(sys.argv[1], encoding="utf-8") as fh:
    rec = json.load(fh)["providers"]["token-plan"]
assert rec["status"] == "ok", rec
assert rec["last_error"] == "exit_42", rec
assert rec["measured_at"] == "2100-01-01T00:00:00Z", rec
assert rec["windows"] == [
    {"kind": "weekly", "label": "3-account average", "used_pct": 1.209},
    {"kind": "special", "label": "Hottest account", "used_pct": 3.627},
], rec
with open(sys.argv[2], encoding="utf-8") as fh:
    export = json.load(fh)
assert export["ready"] is False, export
assert export["updatedAt"] == rec["measured_at"], export
assert export["usageStatusText"] == "exit_42", export
waybar = json.loads(sys.argv[3])
assert "last error: exit_42" in waybar["tooltip"], waybar
encoded = json.dumps({"cache": rec, "export": export, "waybar": waybar})
assert "synth-failure" not in encoded, encoded
PY

unset AI_USAGE_OMP_FAIL
export AI_USAGE_OMP_PARTIAL=1
partial_output="$("$BIN" probe token-plan 2>&1)"
[[ "$partial_output" == *'token-plan ok partial_usage weekly=10'* ]] || fail "partial OMP probe lost its usable average"
[[ "$(wc -l <"$AI_USAGE_OMP_LOG")" == 3 ]] || fail "partial probe invoked OMP more than once"
partial_waybar="$("$BIN" waybar 2>&1)"
partial_tui="$("$BIN" tui 2>&1)"
[[ "$(wc -l <"$AI_USAGE_OMP_LOG")" == 3 ]] || fail "cache consumers invoked OMP for partial data"
python3 - "$AI_USAGE_CACHE" "$XDG_STATE_HOME/omarchy/agents/usage/token-plan.json" "$partial_waybar" "$partial_tui" <<'PY'
import json
import sys

with open(sys.argv[1], encoding="utf-8") as fh:
    rec = json.load(fh)["providers"]["token-plan"]
assert rec["status"] == "ok", rec
assert rec["reason"] == "partial_usage", rec
assert rec["measured_at"] == "2100-01-01T00:00:00Z", rec
assert rec["windows"] == [
    {"kind": "weekly", "label": "3-account average", "used_pct": 10},
    {"kind": "special", "label": "Hottest account"},
], rec
assert [row.get("used_pct") for row in rec["account_usage"]] == [0, None, 30], rec
with open(sys.argv[2], encoding="utf-8") as fh:
    export = json.load(fh)
assert export["ready"] is False, export
assert export["updatedAt"] == rec["measured_at"], export
assert export["usageStatusText"] == "partial_usage", export
waybar = json.loads(sys.argv[3])
assert "partial_usage" in waybar["tooltip"], waybar
assert "Hottest account: —" in waybar["tooltip"], waybar
assert "ok  partial_usage" in sys.argv[4], sys.argv[4]
PY

unset AI_USAGE_OMP_PARTIAL
export AI_USAGE_OMP_SHORT=1
short_output="$("$BIN" probe token-plan 2>&1)"
[[ "$short_output" == *'token-plan ok partial_usage weekly=10'* ]] || fail "short OMP snapshot lost its bounded partial state"
[[ "$(wc -l <"$AI_USAGE_OMP_LOG")" == 4 ]] || fail "short probe invoked OMP more than once"
python3 - "$AI_USAGE_CACHE" "$XDG_STATE_HOME/omarchy/agents/usage/token-plan.json" <<'PY'
import json
import sys

with open(sys.argv[1], encoding="utf-8") as fh:
    rec = json.load(fh)["providers"]["token-plan"]
assert rec["reason"] == "partial_usage", rec
assert "measured_at" not in rec, rec
with open(sys.argv[2], encoding="utf-8") as fh:
    export = json.load(fh)
assert export["ready"] is False, export
assert export["updatedAt"] == "", export
assert export["usageStatusText"] == "partial_usage", export
PY

echo TOKEN_PLAN_OMP_OK

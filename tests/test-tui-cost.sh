#!/usr/bin/env bash
# TUI cost honesty: priced buckets → exact dollar string; unknown model skipped;
# Kimi remaining+limit is 0% used, never an invented $.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BIN="$ROOT/bin/ai-usage"
KIMI_FIXTURE="$ROOT/fixtures/kimi.remaining.json"

if [[ ! -x "$BIN" ]]; then
  echo "FAIL: missing executable $BIN" >&2
  exit 1
fi
if [[ ! -f "$ROOT/prices.toml" ]]; then
  echo "FAIL: missing prices.toml" >&2
  exit 1
fi
if [[ ! -f "$KIMI_FIXTURE" ]]; then
  echo "FAIL: missing $KIMI_FIXTURE" >&2
  exit 1
fi

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
export AI_USAGE_CACHE="$TMP/status.json"
export AI_USAGE_SELECTED="$TMP/selected"
export AI_USAGE_PRICES="$ROOT/prices.toml"
export CODEX_HOME="$TMP/empty-codex"
export XDG_STATE_HOME="$TMP/state"
mkdir -p "$CODEX_HOME/sessions"

python3 - "$BIN" "$KIMI_FIXTURE" "$AI_USAGE_CACHE" "$AI_USAGE_SELECTED" <<'PY'
import importlib.machinery
import importlib.util
import json
import os
import subprocess
import sys
from pathlib import Path

bin_path = Path(sys.argv[1])
kimi_path = Path(sys.argv[2])
cache_path = Path(sys.argv[3])
selected_path = Path(sys.argv[4])
loader = importlib.machinery.SourceFileLoader("ai_usage", str(bin_path))
spec = importlib.util.spec_from_loader("ai_usage", loader)
mod = importlib.util.module_from_spec(spec)
loader.exec_module(mod)

# 1M in + 1M cache-read + 1M out of gpt-5.3-codex = 1.75+0.175+14 = 15.925 → $15.93
# Unknown model tokens must not change the dollar string.
codex = {
    "id": "codex",
    "name": "Codex",
    "logo": "C",
    "status": "ok",
    "plan": "pro",
    "windows": [
        {"kind": "weekly", "label": "Weekly", "used_pct": 75, "resets_at": "2026-08-27T08:31:12Z"},
        {"kind": "special", "label": "GPT-5.3-Codex-Spark", "used_pct": 62, "resets_at": "2026-08-29T01:24:00Z"},
    ],
    "modelUsage": {
        "gpt-5.3-codex": {
            "inputTokens": 1_000_000,
            "outputTokens": 1_000_000,
            "cacheReadInputTokens": 1_000_000,
            "cacheCreationInputTokens": 0,
        },
        "gpt-5.6-sol": {
            "inputTokens": 99_000_000,
            "outputTokens": 99_000_000,
            "cacheReadInputTokens": 99_000_000,
            "cacheCreationInputTokens": 0,
        },
    },
    "recentDays": [
        {"date": "2026-08-17", "messageCount": 0},
        {"date": "2026-08-18", "messageCount": 0},
        {"date": "2026-08-19", "messageCount": 0},
        {"date": "2026-08-20", "messageCount": 0},
        {"date": "2026-08-21", "messageCount": 1_000_000},
        {"date": "2026-08-22", "messageCount": 2_000_000},
        {"date": "2026-08-23", "messageCount": 0},
    ],
    "hasLocalStats": True,
}

kimi_payload = json.loads(kimi_path.read_text())
kimi_row = mod._kimi_report(kimi_payload)
kimi_windows_map = kimi_row.get("windows") or {}
weekly = kimi_windows_map.get("weekly") or {}
session = kimi_windows_map.get("session") or {}
if weekly.get("used_pct") != 0:
    raise SystemExit(f"FAIL: kimi remaining-only weekly used_pct={weekly.get('used_pct')!r} want 0")
if session.get("used_pct") != 0:
    raise SystemExit(f"FAIL: kimi remaining-only session used_pct={session.get('used_pct')!r} want 0")
if kimi_row.get("account") != "kimitestacct":
    raise SystemExit(f"FAIL: kimi account label missing: {kimi_row!r}")

kimi = {
    "id": "kimi",
    "name": "Kimi",
    "logo": "K",
    "status": "ok",
    "windows": [dict(entry, kind=kind) for kind, entry in kimi_windows_map.items()],
}

cache = {
    "version": 1,
    "updated_at": "2026-08-23T00:00:00Z",
    "selected": "codex",
    "providers": {
        "codex": codex,
        "token-plan": {
            "id": "token-plan",
            "name": "Token Plan",
            "logo": "T",
            "status": "unauth",
            "reason": "need_console_login",
            "windows": [{"kind": "weekly", "label": "Weekly"}, {"kind": "special", "label": "Special"}],
        },
        "grok": {
            "id": "grok",
            "name": "Grok",
            "logo": "G",
            "status": "ok",
            "plan": "SuperGrok Heavy",
            "windows": [{"kind": "weekly", "label": "Weekly", "used_pct": 61}],
        },
        "kimi": kimi,
    },
}
cache_path.write_text(json.dumps(cache, indent=2) + "\n")
selected_path.write_text("codex\n")
os.chmod(cache_path, 0o600)

# Cost math must not treat session tokens as quota percents.
prices = mod.load_prices()
amount, skipped = mod.api_equivalent_cost(codex["modelUsage"], prices)
if amount is None:
    raise SystemExit("FAIL: expected a priced cost for gpt-5.3-codex buckets")
dollar = mod.format_usd(amount)
if dollar != "$15.93":
    raise SystemExit(f"FAIL: dollar {dollar!r} want '$15.93'")
if "gpt-5.6-sol" not in skipped:
    raise SystemExit(f"FAIL: unknown model not skipped: {skipped!r}")

env = os.environ.copy()
dump = subprocess.check_output([str(bin_path), "tui", "--dump"], env=env, text=True)
if "API would have cost $15.93" not in dump:
    raise SystemExit(f"FAIL: missing exact dollar string in dump:\n{dump}")
if "OAuth incremental $0" not in dump:
    raise SystemExit(f"FAIL: missing OAuth incremental $0:\n{dump}")
if "LIMITS" not in dump or "TOKENS BY DAY" not in dump or "TOKENS BY MODEL" not in dump:
    raise SystemExit(f"FAIL: missing quattro sections:\n{dump}")
# Session tokens must not overwrite the 75/62 quota percents.
if "75%" not in dump or "62%" not in dump:
    raise SystemExit(f"FAIL: quota percents missing from dump:\n{dump}")
print("CODEX_COST_OK $15.93")

selected_path.write_text("kimi\n")
cache["selected"] = "kimi"
cache_path.write_text(json.dumps(cache, indent=2) + "\n")
dump = subprocess.check_output([str(bin_path), "tui", "--dump"], env=env, text=True)
if "0%" not in dump:
    raise SystemExit(f"FAIL: kimi remaining-only dump missing 0%:\n{dump}")
if "cost unknown" not in dump:
    raise SystemExit(f"FAIL: kimi dump must say cost unknown, not invent $:\n{dump}")
if "API would have cost $0.00" in dump or "API would have cost $0" in dump:
    raise SystemExit(f"FAIL: invented $0.00 API cost for Kimi credits:\n{dump}")
print("KIMI_REMAINING_OK 0% cost unknown")
PY

echo "TUI_COST_OK"

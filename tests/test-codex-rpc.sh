#!/usr/bin/env bash
# M02: live Codex app-server RPC. Skip cleanly if codex is missing.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BIN="$ROOT/bin/ai-usage"
CACHE="${AI_USAGE_CACHE:-$HOME/.cache/ai-usage/status.json}"

if ! command -v codex >/dev/null 2>&1; then
  echo "SKIP: codex not found"
  exit 0
fi
if [[ ! -x "$BIN" ]]; then
  echo "FAIL: missing executable $BIN" >&2
  exit 1
fi

login="$(codex login status 2>&1 || true)"
if ! grep -qiE 'chatgpt|logged in' <<<"$login"; then
  echo "SKIP: codex not logged in ($login)"
  exit 0
fi

probe_out="$("$BIN" probe codex 2>&1)"
printf '%s\n' "$probe_out"

if grep -E 'sk-sp-|sk-proj-|Bearer |eyJ' <<<"$probe_out"; then
  echo "FAIL: secrets in probe stdout" >&2
  exit 1
fi

jq -e '.providers.codex.status=="ok"
      and (.providers.codex.windows[]|select(.kind=="weekly").used_pct|type=="number")
      and (.providers.codex.windows[]|select(.kind=="special").used_pct|type=="number")
      ' "$CACHE" >/dev/null

python3 - "$BIN" "$CACHE" <<'PY'
import importlib.machinery
import importlib.util
import json
import sys
from pathlib import Path

bin_path = Path(sys.argv[1])
cache_path = Path(sys.argv[2])
loader = importlib.machinery.SourceFileLoader("ai_usage", str(bin_path))
spec = importlib.util.spec_from_loader("ai_usage", loader)
mod = importlib.util.module_from_spec(spec)
loader.exec_module(mod)
raw = mod.codex_rate_limits()
weekly_rpc = raw["rateLimits"]["primary"]["usedPercent"]
spark = (raw.get("rateLimitsByLimitId") or {}).get("codex_bengalfox") or {}
special_win = spark.get("secondary") if isinstance(spark.get("secondary"), dict) else spark.get("primary")
if not isinstance(special_win, dict) or "usedPercent" not in special_win:
    raise SystemExit("FAIL: RPC missing Spark weekly window")
special_rpc = special_win["usedPercent"]
cache = json.loads(cache_path.read_text())
windows = {w["kind"]: w for w in cache["providers"]["codex"]["windows"]}
if windows["weekly"]["used_pct"] != weekly_rpc:
    raise SystemExit(f"FAIL: weekly {windows['weekly']['used_pct']} != RPC {weekly_rpc}")
if windows["special"]["used_pct"] != special_rpc:
    raise SystemExit(f"FAIL: special {windows['special']['used_pct']} != RPC {special_rpc}")
print(f"CODEX_RPC_MATCH weekly={weekly_rpc} special={special_rpc}")
PY

if grep -E 'sk-sp-|sk-proj-|Bearer |eyJ' "$CACHE"; then
  echo "FAIL: secrets in cache" >&2
  exit 1
fi

echo "CODEX_RPC_OK"

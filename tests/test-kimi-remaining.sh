#!/usr/bin/env bash
# Kimi remaining-only payload: a fresh account reads 0% used on every window,
# never an invented number. Fixture-driven, no network.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BIN="$ROOT/bin/ai-usage"
FIXTURE="$ROOT/fixtures/kimi.remaining.json"

if [[ ! -x "$BIN" ]]; then
  echo "FAIL: missing executable $BIN" >&2
  exit 1
fi
if [[ ! -f "$FIXTURE" ]]; then
  echo "FAIL: missing $FIXTURE" >&2
  exit 1
fi

python3 - "$BIN" "$FIXTURE" <<'PY'
import importlib.machinery
import importlib.util
import json
import sys
from pathlib import Path

bin_path = Path(sys.argv[1])
loader = importlib.machinery.SourceFileLoader("ai_usage", str(bin_path))
spec = importlib.util.spec_from_loader("ai_usage", loader)
mod = importlib.util.module_from_spec(spec)
loader.exec_module(mod)

payload = json.loads(Path(sys.argv[2]).read_text())
row = mod._kimi_report(payload)
windows = row.get("windows") or {}
weekly = windows.get("weekly") or {}
session = windows.get("session") or {}
if weekly.get("used_pct") != 0:
    raise SystemExit(f"FAIL: kimi remaining-only weekly used_pct={weekly.get('used_pct')!r} want 0")
if session.get("used_pct") != 0:
    raise SystemExit(f"FAIL: kimi remaining-only session used_pct={session.get('used_pct')!r} want 0")
if row.get("account") != "kimitestacct":
    raise SystemExit(f"FAIL: kimi account label missing: {row!r}")
print("KIMI_REMAINING_OK 0%")
PY

echo "KIMI_OK"

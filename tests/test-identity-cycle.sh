#!/usr/bin/env bash
# Right-click skeleton: only Token Plan delegates to the existing local swapper.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BIN="$ROOT/bin/ai-usage"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
export AI_USAGE_CACHE="$TMP/status.json"
export AI_USAGE_SELECTED="$TMP/selected"
export AI_USAGE_TOKEN_PLAN_CONF="$TMP/tp"
export PATH="$TMP/bin:/usr/bin:/bin"
mkdir -p "$TMP/bin" "$TMP/tp"
printf 'team\n' >"$TMP/tp/active"
cat >"$TMP/tp/slots" <<'EOF'
team|local://team|Team|team
gmail|local://gmail|Gmail|gmail
EOF

cat >"$AI_USAGE_CACHE" <<'JSON'
{"version":1,"selected":"token-plan","providers":{"codex":{"status":"ok"},"token-plan":{"status":"ok"}}}
JSON
printf 'token-plan\n' >"$AI_USAGE_SELECTED"

cat >"$TMP/bin/token-plan-swap" <<'SH'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"$AI_USAGE_SWAP_LOG"
SH
chmod +x "$TMP/bin/token-plan-swap"
export AI_USAGE_SWAP_LOG="$TMP/swap.log"
export AI_USAGE_TOKEN_PLAN_SWAP="$TMP/bin/token-plan-swap"

out="$("$BIN" identity next 2>&1)"
[[ "$out" == team ]]
[[ "$out" != *synth-* ]]
[[ "$(cat "$AI_USAGE_SWAP_LOG")" == toggle ]]

python3 - "$BIN" <<'PY'
import importlib.machinery, importlib.util, sys
loader = importlib.machinery.SourceFileLoader("ai_usage", sys.argv[1])
spec = importlib.util.spec_from_loader("ai_usage", loader)
mod = importlib.util.module_from_spec(spec)
loader.exec_module(mod)
old = {"id": "token-plan", "status": "ok", "windows": [{"used_pct": 71}]}
switched = mod.blank_usage_windows(old)
if any("used_pct" in w for w in switched["windows"]):
    raise SystemExit("FAIL: pre-switch usage survived")
kept = mod.keep_last_good(old, switched)
if any("used_pct" in w for w in kept.get("windows") or []):
    raise SystemExit("FAIL: keep_last_good resurrected pre-switch usage")
if kept.get("reason") != "switched":
    raise SystemExit("FAIL: switched reason lost")
PY

printf 'codex\n' >"$AI_USAGE_SELECTED"
"$BIN" identity next >/dev/null
[[ "$(wc -l <"$AI_USAGE_SWAP_LOG")" == 1 ]]

# A failing helper may emit key material on both streams. identity-next must
# report only its exit status, never relay helper output.
cat >"$TMP/bin/token-plan-swap" <<'SH'
#!/usr/bin/env bash
printf '%s\n' 'synth-stdout-key-material'
printf '%s\n' 'synth-stderr-key-material' >&2
exit 23
SH
chmod +x "$TMP/bin/token-plan-swap"
printf 'token-plan\n' >"$AI_USAGE_SELECTED"
cp "$AI_USAGE_CACHE" "$TMP/cache-before-failure.json"
set +e
out="$("$BIN" identity next 2>&1)"
rc=$?
set -e
[[ "$rc" == 23 ]]
[[ "$out" == *'swap-failed: exit 23'* ]]
[[ "$out" != *synth-* ]]
cmp -s "$AI_USAGE_CACHE" "$TMP/cache-before-failure.json"

echo IDENTITY_CYCLE_OK

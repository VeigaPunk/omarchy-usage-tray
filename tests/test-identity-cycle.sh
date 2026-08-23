#!/usr/bin/env bash
# Right-click skeleton: only Token Plan delegates to the existing local swapper.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BIN="$ROOT/bin/ai-usage"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
export AI_USAGE_CACHE="$TMP/status.json"
export AI_USAGE_SELECTED="$TMP/selected"
export PATH="$TMP/bin:/usr/bin"
mkdir -p "$TMP/bin"

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

"$BIN" identity next
[[ "$(cat "$AI_USAGE_SWAP_LOG")" == toggle ]]

printf 'codex\n' >"$AI_USAGE_SELECTED"
"$BIN" identity next >/dev/null
[[ "$(wc -l <"$AI_USAGE_SWAP_LOG")" == 1 ]]

echo IDENTITY_CYCLE_OK

#!/usr/bin/env bash
# Isolated Cursor OAuth swap: two parked auth files, never host ~/.config/cursor.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BIN="$ROOT/bin/ai-usage"
SWAP="$ROOT/bin/cursor-oauth-swap"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

export AI_USAGE_CACHE="$TMP/status.json"
export AI_USAGE_SELECTED="$TMP/selected"
export AI_USAGE_CURSOR_OAUTH_CONF="$TMP/cursor-oauth"
export AI_USAGE_CURSOR_OAUTH_SWAP="$SWAP"
export CURSOR_OAUTH_HOME="$TMP/cursor-oauth"
export CURSOR_AUTH_FILE="$TMP/live/auth.json"
export PATH="$TMP/bin:/usr/bin:/bin"
mkdir -p "$TMP/live" "$TMP/bin"

write_auth() {
  local dest="$1" mark="$2"
  umask 077
  printf '{"accessToken":"%s","refreshToken":"%s"}\n' "$mark" "$mark-rt" >"$dest"
  chmod 600 "$dest"
}

write_auth "$CURSOR_AUTH_FILE" "slot-primary"
"$SWAP" capture primary >/dev/null
write_auth "$CURSOR_AUTH_FILE" "slot-second"
"$SWAP" capture second >/dev/null
printf 'primary\n' >"$CURSOR_OAUTH_HOME/active"
write_auth "$CURSOR_AUTH_FILE" "slot-primary"

cat >"$AI_USAGE_CACHE" <<'JSON'
{"version":1,"selected":"cursor","providers":{"codex":{"id":"codex","status":"ok","logo":"C"},"cursor":{"id":"cursor","status":"ok","logo":"R","windows":[{"kind":"weekly","used_pct":41}]}}}
JSON
printf 'cursor\n' >"$AI_USAGE_SELECTED"

out="$("$BIN" identity next 2>&1)"
[[ "$out" == second ]]
[[ "$out" != *slot-* ]]
grep -q 'slot-second' "$CURSOR_AUTH_FILE"
[[ "$(tr -d '[:space:]' <"$CURSOR_OAUTH_HOME/active")" == second ]]

out="$("$BIN" identity next 2>&1)"
[[ "$out" == primary ]]
grep -q 'slot-primary' "$CURSOR_AUTH_FILE"

printf 'codex\n' >"$AI_USAGE_SELECTED"
"$BIN" cycle next >/dev/null
[[ "$(tr -d '[:space:]' <"$CURSOR_OAUTH_HOME/active")" == primary ]]

printf 'cursor\n' >"$AI_USAGE_SELECTED"
"$BIN" identity next >/dev/null
[[ "$(tr -d '[:space:]' <"$CURSOR_OAUTH_HOME/active")" == second ]]

echo CURSOR_OAUTH_SWAP_OK

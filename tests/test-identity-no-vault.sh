#!/usr/bin/env bash
# Execution proof: identity-next is local-only and never invokes vault/key readers.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BIN="$ROOT/bin/ai-usage"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

export HOME="$TMP/home"
export XDG_CONFIG_HOME="$HOME/.config"
export XDG_CACHE_HOME="$HOME/.cache"
export AI_USAGE_CACHE="$XDG_CACHE_HOME/ai-usage/status.json"
export AI_USAGE_SELECTED="$XDG_CONFIG_HOME/ai-usage/selected"
export AI_USAGE_TOKEN_PLAN_CONF="$XDG_CONFIG_HOME/alibaba-token-plan"
export AI_USAGE_TRACE="$TMP/trace"
mkdir -p "$TMP/bin" "$(dirname "$AI_USAGE_CACHE")" "$(dirname "$AI_USAGE_SELECTED")" \
  "$AI_USAGE_TOKEN_PLAN_CONF/keys"

cat >"$AI_USAGE_TOKEN_PLAN_CONF/slots" <<'EOF'
team|local://team|Team|team
gmail|local://gmail|Gmail|gmail
EOF
printf 'team\n' >"$AI_USAGE_TOKEN_PLAN_CONF/active"
printf 'synthetic-team-key-only' >"$AI_USAGE_TOKEN_PLAN_CONF/keys/team"
printf 'synthetic-gmail-key-only' >"$AI_USAGE_TOKEN_PLAN_CONF/keys/gmail"
printf 'token-plan\n' >"$AI_USAGE_SELECTED"
printf '%s\n' '{"version":1,"selected":"token-plan","providers":{"token-plan":{"id":"token-plan","name":"Token Plan","status":"ok","windows":[]}}}' >"$AI_USAGE_CACHE"
chmod 600 "$AI_USAGE_CACHE" "$AI_USAGE_SELECTED" "$AI_USAGE_TOKEN_PLAN_CONF/active" \
  "$AI_USAGE_TOKEN_PLAN_CONF/slots" "$AI_USAGE_TOKEN_PLAN_CONF/keys/"*

# The only allowed child. It models the local-file swap without reading a vault.
cat >"$TMP/bin/token-plan-swap" <<'SH'
#!/usr/bin/env bash
printf 'swap:%s\n' "$1" >>"$AI_USAGE_TRACE"
[[ "$1" == toggle ]] || exit 90
printf 'gmail\n' >"$AI_USAGE_TOKEN_PLAN_CONF/active"
SH

# These sentinels turn any forbidden lookup/execution into a visible failure.
for name in op pull token-plan-key; do
  cat >"$TMP/bin/$name" <<'SH'
#!/usr/bin/env bash
printf 'FORBIDDEN:%s\n' "$(basename "$0")" >>"$AI_USAGE_TRACE"
exit 99
SH
done
chmod +x "$TMP/bin/"*
export PATH="$TMP/bin:/usr/bin:/bin"
export AI_USAGE_TOKEN_PLAN_SWAP="$TMP/bin/token-plan-swap"

out="$("$BIN" identity next 2>&1)"
[[ "$out" == gmail ]]
[[ "$out" != *synthetic-* ]]
[[ "$(cat "$AI_USAGE_TRACE")" == swap:toggle ]]
! grep -q FORBIDDEN "$AI_USAGE_TRACE"

# Waybar is cache-only and the shipped timer starts only ai-usage refresh.
waybar="$("$BIN" waybar)"
[[ "$waybar" != *synthetic-* ]]
[[ "$(cat "$AI_USAGE_TRACE")" == swap:toggle ]]
! grep -Eq 'token-plan-key|\bop\b|\bpull\b' "$ROOT/deploy/waybar-ai-usage.jsonc" "$ROOT/systemd/ai-usage.service" "$ROOT/systemd/ai-usage.timer"

echo IDENTITY_NO_VAULT_OK

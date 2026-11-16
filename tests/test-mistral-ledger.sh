#!/usr/bin/env bash
# Mistral ledger: month-to-date spend from OMP transcripts, read incrementally,
# never touching key material, omp, or the network.
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
export AI_USAGE_CACHE="$TMP/cache/status.json"
export AI_USAGE_SELECTED="$TMP/selected"
export AI_USAGE_OMP_AGENT_DIR="$TMP/agent"
export AI_USAGE_FALLBACK_LOG="$TMP/fallback.log"
# Key status stays inside $TMP: the host's resolver and status file never leak in.
export XDG_STATE_HOME="$TMP/state"
export AI_USAGE_MISTRAL_KEY_RESOLVER="$TMP/no-omp-mistral-key"
KEY_STATUS="$XDG_STATE_HOME/omp-mistral-key/status.json"
LEDGER="$TMP/cache/mistral-ledger.json"
export PATH="/usr/bin:/bin"
unset MISTRAL_API_KEY AI_USAGE_MISTRAL_MONTHLY_BUDGET
SESSIONS="$AI_USAGE_OMP_AGENT_DIR/sessions"
mkdir -p "$HOME/.local/bin" "$SESSIONS/-proj/sub"
printf 'mistral\n' >"$AI_USAGE_SELECTED"
# The probe must not shell out to omp: any call lands in the fallback log.
cat >"$HOME/.local/bin/omp" <<'SH'
#!/usr/bin/env bash
printf '%s\n' "$0 $*" >>"$AI_USAGE_FALLBACK_LOG"
exit 97
SH
chmod +x "$HOME/.local/bin/omp"

# --- no key configured --------------------------------------------------------

out="$("$BIN" probe mistral)"
[[ "$out" == 'mistral unauth no_credentials' ]] || fail "missing key printed: $out"

# --- key pinned in models.yml (command form; never executed) ------------------

cat >"$AI_USAGE_OMP_AGENT_DIR/models.yml" <<'YML'
providers:
  other:
    baseUrl: https://example.invalid/v1
  mistral:
    # comment lines inside the block are fine
    apiKey: '!cat /nonexistent/mistral.key'
YML

NOW_MS="$(python3 -c 'import time; print(int(time.time() * 1000))')"
OLD_MS=1704067200000 # 2024-01-01, outside the current month

# reply <provider> <model> <totalTokens> <costTotal> <responseId> <timestampMs> [role]
reply() {
  printf '{"type":"message","message":{"role":"%s","provider":"%s","model":"%s","usage":{"input":1,"output":1,"totalTokens":%s,"cost":{"total":%s}},"timestamp":%s,"responseId":"%s"}}\n' \
    "${7:-assistant}" "$1" "$2" "$3" "$4" "$6" "$5"
}

A="$SESSIONS/-proj/a.jsonl"
B="$SESSIONS/-proj/sub/b.jsonl"
{
  reply mistral deepseek-v4-1-flash-1017 30000 0.75 r1 "$NOW_MS"
  reply mistral zai-glm-5-3-flash 10000 0.25 r2 "$NOW_MS"
  reply mistral deepseek-v4-1-flash-1017 99999 9.99 r3 "$OLD_MS"
  # Another provider serving a Mistral-named model is not Mistral spend.
  reply opencode-zen mistral-large-4 50000 5.00 r4 "$NOW_MS"
  reply mistral deepseek-v4-1-flash-1017 77777 7.77 r5 "$NOW_MS" user
  printf '{"message": "provider":"mistral" not json\n'
} >"$A"
{
  # A fork copies r1 forward; it must count once.
  reply mistral deepseek-v4-1-flash-1017 30000 0.75 r1 "$NOW_MS"
  reply mistral deepseek-v4-1-flash-1017 20000 0.50 r6 "$NOW_MS"
} >"$B"

out="$("$BIN" probe mistral)"
[[ "$out" == 'mistral ok spent=$1.50' ]] || fail "unbudgeted probe printed: $out"
[[ ! -s "$AI_USAGE_FALLBACK_LOG" ]] || fail "probe called omp: $(cat "$AI_USAGE_FALLBACK_LOG")"

python3 - "$AI_USAGE_CACHE" <<'PY'
import json, sys
rec = json.load(open(sys.argv[1]))["providers"]["mistral"]
spend = rec["spend"]
assert spend["usd"] == 1.5, spend
assert spend["tokens"] == 60000, spend
assert spend["replies"] == 3, spend
models = [(r["model"], r["usd"], r["tokens"], r["replies"]) for r in spend["by_model"]]
assert models == [("deepseek-v4-1-flash-1017", 1.25, 50000, 2), ("zai-glm-5-3-flash", 0.25, 10000, 1)], models
assert rec["windows"][0]["resets_at"].endswith("-01T00:00:00Z"), rec["windows"][0]
PY

payload="$("$BIN" waybar)"
text="$(printf '%s' "$payload" | jq -r .text)"
[[ "$text" == 'ⓜ $1.50' ]] || fail "unbudgeted chip text: $text"
tooltip="$(printf '%s' "$payload" | jq -r .tooltip)"
[[ "$tooltip" == *'Month spend  $1.50 spent'* ]] || fail "tooltip lacks month spend: $tooltip"
[[ "$tooltip" == *'deepseek-v4-1-flash-1017'* ]] || fail "tooltip lacks per-model spend: $tooltip"

# --- budget meters the month; incremental append is picked up -----------------

reply mistral zai-glm-5-3-flash 5000 0.50 r7 "$NOW_MS" >>"$B"
export AI_USAGE_MISTRAL_MONTHLY_BUDGET=4
out="$("$BIN" probe mistral)"
[[ "$out" == 'mistral ok monthly=50 spent=$2.00' ]] || fail "budgeted probe printed: $out"
text="$("$BIN" waybar | jq -r .text)"
[[ "$text" == ⓜ*' $2.00' && "$text" != 'ⓜ $2.00' ]] || fail "budgeted chip lacks a meter: $text"

# A truncated (replaced) transcript is read again from the start.
reply mistral zai-glm-5-3-flash 1000 0.10 r8 "$NOW_MS" >"$B"
out="$("$BIN" probe mistral)"
[[ "$out" == 'mistral ok monthly=27.5 spent=$1.10' ]] || fail "rewritten transcript printed: $out"

# --- the key in use is out of budget (HTTP 402) -------------------------------

NOW_S=$((NOW_MS / 1000))
mkdir -p "$(dirname "$KEY_STATUS")"
# key_status <active slot> <primary status> <primary http> <fallback status> <fallback http>
key_status() {
  printf '{"checked_at":%s,"active_slot":%s,"keys":[{"slot":1,"role":"primary","suffix":"aaaa","status":"%s","http":%s,"checked_at":%s},{"slot":2,"role":"fallback","suffix":"bbbb","status":"%s","http":%s,"checked_at":%s}]}\n' \
    "$NOW_S" "$1" "$2" "$3" "$NOW_S" "$4" "$5" "$NOW_S" >"$KEY_STATUS"
}

# check_keys <expected monthly used_pct or none> <expected reason or none>
check_keys() {
  python3 - "$AI_USAGE_CACHE" "$1" "$2" <<'PY'
import json, sys
rec = json.load(open(sys.argv[1]))["providers"]["mistral"]
want_pct, want_reason = sys.argv[2], sys.argv[3]
assert rec["status"] == "ok", rec
month = rec["windows"][0]
assert month["kind"] == "monthly", month
assert month.get("used_pct") == (None if want_pct == "none" else float(want_pct)), month
assert rec.get("reason") == (None if want_reason == "none" else want_reason), rec
rows = {row["slot"]: row for row in rec["account_usage"]}
for row in rows.values():
    want = 100 if row["label"].startswith("exhausted") else None
    assert row["used_pct"] == want, row
PY
}

key_status 1 exhausted 402 valid 200
out="$("$BIN" probe mistral)"
[[ "$out" == *' budget_exhausted '* && "$out" == *' spent=$1.10' ]] || fail "exhausted budgeted probe printed: $out"
check_keys 100 budget_exhausted || fail "exhausted key with a budget"
payload="$("$BIN" waybar)"
printf '%s' "$payload" | jq -e '.class | index("critical")' >/dev/null || fail "exhausted chip not critical: $payload"
tooltip="$(printf '%s' "$payload" | jq -r .tooltip)"
[[ "$tooltip" == *'exhausted · in use'* ]] || fail "tooltip lacks the exhausted key row: $tooltip"
[[ "$tooltip" == *'HTTP 402'* ]] || fail "tooltip does not explain the refusal: $tooltip"

unset AI_USAGE_MISTRAL_MONTHLY_BUDGET
out="$("$BIN" probe mistral)"
[[ "$out" == *' budget_exhausted '* && "$out" == *' spent=$1.10' ]] || fail "exhausted unbudgeted probe printed: $out"
check_keys 100 budget_exhausted || fail "exhausted key without a budget"
payload="$("$BIN" waybar)"
printf '%s' "$payload" | jq -e '.class | index("critical")' >/dev/null || fail "unbudgeted exhausted chip not critical: $payload"
text="$(printf '%s' "$payload" | jq -r .text)"
[[ "$text" == ⓜ*' $1.10' && "$text" != 'ⓜ $1.10' ]] || fail "exhausted chip lacks a meter: $text"
[[ "$("$BIN" tui --dump)" == *'HTTP 402'* ]] || fail "dashboard does not explain the refusal"

# Only the key in use decides: an exhausted fallback leaves the meter alone.
key_status 1 valid 200 exhausted 402
out="$("$BIN" probe mistral)"
[[ "$out" == 'mistral ok spent=$1.10' ]] || fail "exhausted fallback probe printed: $out"
check_keys none none || fail "exhausted fallback key"
"$BIN" waybar | jq -e '.class | index("critical") | not' >/dev/null || fail "exhausted fallback chip is critical"

# --- replies from deleted transcripts keep counting this month ----------------

rm "$A"
for round in 1 2; do
  out="$("$BIN" probe mistral)"
  [[ "$out" == 'mistral ok spent=$1.10' ]] || fail "spend after deleting a transcript (round $round): $out"
done
python3 - "$LEDGER" <<'PY' || fail "ledger carries a reply from an earlier month"
import json, sys
ledger = json.load(open(sys.argv[1]))
entries = list(ledger["deleted"]) + [e for f in ledger["files"].values() for e in f["entries"]]
keys = [entry[0] for entry in entries]
assert "r3" not in keys, keys
assert sorted(k for k in keys if k in ("r1", "r2")) == ["r1", "r2"], keys
PY
[[ ! -s "$AI_USAGE_FALLBACK_LOG" ]] || fail "probe called omp: $(cat "$AI_USAGE_FALLBACK_LOG")"

echo "PASS: test-mistral-ledger"

#!/usr/bin/env bash
# Inception ledger: per-key token totals from OMP transcripts against the
# per-key grant, read incrementally, never touching key material or omp.
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
export PATH="/usr/bin:/bin"
LEDGER="$TMP/cache/inception-ledger.json"
SESSIONS="$AI_USAGE_OMP_AGENT_DIR/sessions"
mkdir -p "$HOME/.local/bin" "$SESSIONS/-proj/sub"
printf 'inception\n' >"$AI_USAGE_SELECTED"
# The probe must not shell out to omp: any call lands in the fallback log.
cat >"$HOME/.local/bin/omp" <<'SH'
#!/usr/bin/env bash
printf '%s\n' "$0 $*" >>"$AI_USAGE_FALLBACK_LOG"
exit 97
SH
chmod +x "$HOME/.local/bin/omp"

# --- no auth store -----------------------------------------------------------

out="$("$BIN" probe inception)"
[[ "$out" == 'inception unauth no_auth_store' ]] || fail "missing auth store printed: $out"

# --- auth store: three live keys, one disabled, one other provider -----------

python3 - "$AI_USAGE_OMP_AGENT_DIR/agent.db" <<'PY'
import sqlite3, sys
con = sqlite3.connect(sys.argv[1])
con.execute("CREATE TABLE auth_credentials (id INTEGER PRIMARY KEY, provider TEXT, credential_type TEXT, data TEXT, disabled_cause TEXT, identity_key TEXT, created_at INTEGER, updated_at INTEGER)")
rows = [
    (37, "inception", '{"key":"synth-inception-key-37"}', None),
    (38, "inception", '{"key":"synth-inception-key-38"}', None),
    (39, "inception", '{"key":"synth-inception-key-39"}', None),
    (40, "inception", '{"key":"synth-inception-key-40"}', "revoked"),
    (41, "zai", '{"key":"synth-zai-key"}', None),
]
con.executemany("INSERT INTO auth_credentials (id, provider, credential_type, data, disabled_cause) VALUES (?, ?, 'api_key', ?, ?)", rows)
con.commit()
PY

# reply <provider> <credentialId|null> <totalTokens> <responseId> [role]
reply() {
  printf '{"type":"message","message":{"role":"%s","provider":"%s","model":"mercury-2","usage":{"input":1,"output":1,"totalTokens":%s},"timestamp":1,"credentialId":%s,"responseId":"%s"}}\n' \
    "${5:-assistant}" "$1" "$3" "$2" "$4"
}

A="$SESSIONS/-proj/a.jsonl"
B="$SESSIONS/-proj/sub/b.jsonl"
{
  reply inception 37 30000000 r1
  reply inception 38 120000000 r2
  reply inception null 1000000 r3
  reply zai 3 50000000 r4
  reply inception 37 9999999 r5 user
  printf '{"message": inception not json\n'
} >"$A"
{
  # A fork copies r1 forward; it must count once.
  reply inception 37 30000000 r1
  reply inception 37 30000000 r6
} >"$B"

out="$("$BIN" probe inception)"
[[ "$out" == 'inception ok partial_usage weekly=53.6667 special=100 tokens_left=139M' ]] ||
  fail "first probe printed: $out"

python3 - "$AI_USAGE_CACHE" <<'PY'
import json, sys
rec = json.load(open(sys.argv[1]))["providers"]["inception"]
assert rec["tokens"] == {"used": 161000000, "total": 300000000, "remaining": 139000000, "unattributed": 1000000}, rec["tokens"]
rows = {row["label"]: row for row in rec["account_usage"]}
assert list(rows) == ["key 37", "key 38", "key 39"], list(rows)
assert rows["key 37"]["tokens_used"] == 60000000 and rows["key 37"]["used_pct"] == 60, rows["key 37"]
# A key past its grant reads exhausted, not over 100%.
assert rows["key 38"]["tokens_used"] == 100000000 and rows["key 38"]["tokens_remaining"] == 0, rows["key 38"]
assert rows["key 39"]["tokens_used"] == 0, rows["key 39"]
assert rec["snapshot"] == {"reports": 3, "accounts_without_usage": 0, "disabled_credentials": 1}, rec["snapshot"]
PY

waybar="$("$BIN" waybar)"
python3 - "$waybar" <<'PY'
import json, re, sys
import xml.etree.ElementTree as ET
payload = json.loads(sys.argv[1])
assert payload["alt"] == "inception", payload
assert payload["text"].startswith("I ") and payload["text"].endswith(" 139M left"), payload["text"]
assert "critical" in payload["class"], payload["class"]
ET.fromstring(f"<t>{payload['tooltip']}</t>")
plain = re.sub(r"<[^>]+>", "", payload["tooltip"])
assert "139M of 300M tokens left" in plain, plain
assert "1M without a key id" in plain, plain
assert "key 38 · 0 of 100M tokens left" in plain, plain
PY

# A user-declared fourth key outside OMP is shown, but its usage stays unknown.
out="$(AI_USAGE_INCEPTION_EXPECTED_KEYS=4 "$BIN" probe inception)"
[[ "$out" == *'keys=4' ]] || fail "declared key count was not retained: $out"
python3 - "$AI_USAGE_CACHE" "$("$BIN" waybar)" <<'PY'
import json, re, sys
rec = json.load(open(sys.argv[1]))["providers"]["inception"]
assert rec["tokens"] == {
    "used": 161000000, "total": 400000000, "remaining": None,
    "key_count": 4, "unmetered_keys": 1, "unattributed": 1000000,
}, rec["tokens"]
assert rec["snapshot"]["reports"] == 3, rec["snapshot"]
assert len(rec["account_usage"]) == 4, rec["account_usage"]
unknown = rec["account_usage"][-1]
assert unknown["used_pct"] is None and unknown["tokens_remaining"] is None, unknown
payload = json.loads(sys.argv[2])
assert payload["text"].endswith("4 keys"), payload["text"]
plain = re.sub(r"<[^>]+>", "", payload["tooltip"])
assert "400M grant across 4 keys" in plain, plain
assert "1 key(s) not in OMP; usage unknown" in plain, plain
assert "key not in OMP 1" in plain, plain
assert "400M of 400M tokens left" not in plain, plain
PY

for f in "$AI_USAGE_CACHE" "$LEDGER"; do
  ! grep -q synth- "$f" || fail "$f carries key material"
done

# --- appends are read from the saved offset ----------------------------------

reply inception 39 10000000 r7 >>"$A"
# A reply still being written has no newline yet and must wait.
printf '{"type":"message","message":{"role":"assistant","provider":"inception","usage":{"totalTokens":5000000},"credentialId":39,' >>"$A"
out="$("$BIN" probe inception)"
[[ "$out" == *'tokens_left=129M'* ]] || fail "append probe printed: $out"
printf '"responseId":"r8"}}\n' >>"$A"
out="$("$BIN" probe inception)"
[[ "$out" == *'tokens_left=124M'* ]] || fail "completed partial line probe printed: $out"

# --- a replaced transcript is recounted, not added to ------------------------

reply inception 37 1000000 r9 >"$B.new"
mv "$B.new" "$B"
out="$("$BIN" probe inception)"
# key 37 drops from 60M to 31M (r1 in A + r9).
[[ "$out" == *'tokens_left=153M'* ]] || fail "replaced transcript probe printed: $out"

rm "$B"
out="$("$BIN" probe inception)"
[[ "$out" == *'tokens_left=154M'* ]] || fail "deleted transcript probe printed: $out"

[[ ! -e "$AI_USAGE_FALLBACK_LOG" ]] || fail "probe invoked omp: $(cat "$AI_USAGE_FALLBACK_LOG")"
echo "PASS: test-inception-ledger"

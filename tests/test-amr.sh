#!/usr/bin/env bash
# OpenDesign (AMR): sign-in slots feed the account API (workspaces + billing
# preflight) through a local stub — no_login, plan windows, wallet rows,
# duplicate / expired / unreachable slots, secret hygiene, Waybar / TUI
# rendering, and `login amr` driving a fake vela. Network stays on
# 127.0.0.1; nothing touches the real CLI state (isolated HOME / XDG +
# AI_USAGE_* overrides + pgrep stub, same isolation as
# tests/test-provider-roster.sh).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BIN="$ROOT/bin/ai-usage"
TMP="$(mktemp -d)"
STUB_PID=""
trap '[[ -z "$STUB_PID" ]] || kill "$STUB_PID" 2>/dev/null || true; rm -rf "$TMP"' EXIT

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

[[ -x "$BIN" ]] || fail "missing executable $BIN"

export HOME="$TMP/home"
export XDG_CACHE_HOME="$TMP/cache-home"
export XDG_CONFIG_HOME="$TMP/config-home"
export XDG_STATE_HOME="$TMP/state-home"
export AI_USAGE_CACHE="$TMP/status.json"
export AI_USAGE_SELECTED="$TMP/selected"
export AI_USAGE_PROVIDERS_FILE="$TMP/roster-absent"
export AI_USAGE_OMP_BIN="$TMP/bin/fake-omp"
export AI_USAGE_WAYBAR_CONFIG="$TMP/waybar-absent.jsonc"
export AI_USAGE_PGREP_LOG="$TMP/pgrep.log"
export AI_USAGE_AMR_DIR="$TMP/amr"
# A real `vela` on the host opens the user's browser: keep PATH to the stubs
# plus system dirs, and point every login below at the fake vela (or a path
# that does not exist) through AI_USAGE_VELA_BIN.
export PATH="$TMP/bin:/usr/bin:/bin"
unset AI_USAGE_PROVIDERS
mkdir -p "$TMP/bin" "$HOME/.local/bin" "$XDG_CACHE_HOME" "$XDG_CONFIG_HOME"

# select/cycle poke Waybar through pgrep, and ensure_path() prepends
# ~/.local/bin ahead of PATH — so the stub lives in both places and the test
# never signals the real desktop's waybar.
cat >"$TMP/bin/pgrep" <<'SH'
#!/usr/bin/env bash
printf 'pgrep %s\n' "$*" >>"$AI_USAGE_PGREP_LOG"
exit 1
SH
chmod +x "$TMP/bin/pgrep"
cp "$TMP/bin/pgrep" "$HOME/.local/bin/pgrep"

# Probing amr never consults OMP; anything that falls back to it fails closed.
cat >"$AI_USAGE_OMP_BIN" <<'SH'
#!/usr/bin/env bash
exit 1
SH
chmod +x "$AI_USAGE_OMP_BIN"

version="$("$BIN" --version)" # prints "ai-usage X.Y.Z"
[[ "$version" == ai-usage\ * ]] || fail "unexpected --version output: $version"
WANT_UA="ai-usage/${version#ai-usage }"

# --- local amr-api stub ------------------------------------------------------

STUB_PORT_FILE="$TMP/stub-port"
STUB_REQUESTS_LOG="$TMP/requests.log"
: >"$STUB_REQUESTS_LOG"

cat >"$TMP/amr-stub.py" <<'PY'
import json
import sys
from http.server import BaseHTTPRequestHandler, HTTPServer

port_file, log_path = sys.argv[1], sys.argv[2]


def item(ws_id, name, wtype, member_status, lifecycle):
    return {
        "workspaceId": ws_id,
        "workspaceMemberId": "wmem-" + ws_id,
        "workspaceName": name,
        "workspaceType": wtype,
        "role": "owner",
        "memberStatus": member_status,
        "lifecycleState": lifecycle,
    }


GO_ITEMS = [
    item("ws-team-a", "Team Alpha", "team", "active", "active"),
    item("ws-removed", "Former Space", "personal", "removed", "active"),
    item("ws-go-a", "Personal Go", "personal", "active", "active"),
]
WORKSPACES = {
    "vela_ctrl_go_a": GO_ITEMS,
    "vela_ctrl_go_dup": GO_ITEMS,
    "vela_ctrl_plus_b": [item("ws-plus-b", "Personal Plus", "personal", "active", "active")],
    "vela_ctrl_wallet_c": [item("ws-wallet-c", "Personal Wallet", "personal", "active", "active")],
}


def win(policy_id, duration, reset_mode, used, limit, remaining, window_start, resets_at):
    return {
        "policyId": policy_id,
        "durationSeconds": duration,
        "resetMode": reset_mode,
        "usedCredits": used,
        "limitCredits": limit,
        "remainingCredits": remaining,
        "windowStart": window_start,
        "resetsAt": resets_at,
    }


def preflight(ws_id, generated_at, balance, funding, model_covered, tier, windows):
    return {
        "schemaVersion": 1,
        "workspaceId": ws_id,
        "workspaceMemberId": "wmem-" + ws_id,
        "modelId": None,
        "generatedAt": generated_at,
        "balanceUsd": balance,
        "funding": funding,
        "modelCovered": model_covered,
        "codingPlan": {
            "workspaceId": ws_id,
            "generatedAt": generated_at,
            "eligible": tier is not None,
            "tier": tier,
            "windows": windows,
        },
    }


PREFLIGHTS = {
    "ws-go-a": preflight(
        "ws-go-a", "2100-01-01T00:00:00.123456789Z", "12.50", "coding_plan", True, "go", [
            win("pol-go-session", 18000, "activity_triggered", "25", "100", "75",
                "2099-12-31T19:00:00Z", "2100-01-01T03:00:00.5Z"),
            win("pol-go-weekly", 604800, "anchored_recurring", "42", "100", "58",
                None, "2100-01-05T00:00:00Z"),
        ]),
    "ws-plus-b": preflight(
        "ws-plus-b", "2100-01-01T00:05:00Z", "3.20", "coding_plan", True, "plus", [
            win("pol-plus-weekly", 604800, "anchored_recurring",
                "675539944105574475000", "900719925474099300000",
                "225179981368524825000", None, "2100-01-03T00:00:00Z"),
            win("pol-plus-day", 86400, "activity_triggered", "10", "100", "90",
                None, None),
        ]),
    "ws-wallet-c": preflight(
        "ws-wallet-c", "2100-01-01T00:10:00Z", "4", "wallet", False, None, []),
}


class Handler(BaseHTTPRequestHandler):
    def log_message(self, *args):
        pass

    def _send(self, code, obj):
        body = json.dumps(obj).encode("utf-8")
        self.send_response(code)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def _record(self):
        entry = {
            "method": self.command,
            "path": self.path,
            "user_agent": self.headers.get("User-Agent", ""),
            "authorization": self.headers.get("Authorization", ""),
            "workspace_header": self.headers.get("x-vela-workspace-id", ""),
        }
        with open(log_path, "a", encoding="utf-8") as fh:
            fh.write(json.dumps(entry) + "\n")

    def do_GET(self):
        self._record()
        # Cloudflare emulation: Python's default UA is banned on the real API.
        if self.headers.get("User-Agent", "").startswith("Python-urllib"):
            self._send(403, {"title": "Error 1010: Access denied"})
            return
        auth = self.headers.get("Authorization", "")
        key = auth[len("Bearer "):] if auth.startswith("Bearer ") else ""
        if key not in WORKSPACES: # unknown keys and vela_ctrl_expired_d
            self._send(401, {"error": "unauthenticated"})
            return
        if self.path == "/api/v1/workspaces":
            self._send(200, {"items": WORKSPACES[key]})
            return
        prefix, suffix = "/api/v1/workspaces/", "/billing/preflight"
        if self.path.startswith(prefix) and self.path.endswith(suffix):
            ws_id = self.path[len(prefix):-len(suffix)]
            payload = PREFLIGHTS.get(ws_id)
            if payload is None:
                self._send(404, {"error": "unknown workspace"})
                return
            if ws_id == "ws-plus-b":
                self._send(200, {"preflight": payload})
            else:
                self._send(200, payload)
            return
        self._send(404, {"error": "unknown route"})


server = HTTPServer(("127.0.0.1", 0), Handler)
with open(port_file, "w", encoding="utf-8") as fh:
    fh.write(str(server.server_address[1]))
server.serve_forever()
PY

python3 "$TMP/amr-stub.py" "$STUB_PORT_FILE" "$STUB_REQUESTS_LOG" &
STUB_PID=$!
for _ in $(seq 1 50); do
  [[ -s "$STUB_PORT_FILE" ]] && break
  sleep 0.1
done
[[ -s "$STUB_PORT_FILE" ]] || fail "amr stub never wrote its port"
STUB_PORT="$(cat "$STUB_PORT_FILE")"
export AI_USAGE_AMR_API_URL="http://127.0.0.1:$STUB_PORT"

# --- helpers -----------------------------------------------------------------

# slot <n> <key> — one OpenDesign sign-in slot. The config's apiUrl points at
# an unroutable host on purpose: AI_USAGE_AMR_API_URL must override it.
slot() {
  local n="$1" key="$2"
  mkdir -p "$AI_USAGE_AMR_DIR/$n"
  KEY="$key" N="$n" python3 - <<'PY'
import json
import os
cfg = {"profiles": {"prod": {
    "controlKey": os.environ["KEY"],
    "runtimeKey": "rt-secret",
    "apiUrl": "https://amr-api.invalid",
    "user": {"id": "user-" + os.environ["N"], "email": "user" + os.environ["N"] + "@example.com"},
}}}
path = os.path.join(os.environ["AI_USAGE_AMR_DIR"], os.environ["N"], "config.json")
with open(path, "w", encoding="utf-8") as fh:
    json.dump(cfg, fh)
PY
}

SECRET_PAT='vela_ctrl_|rt-secret|@example\.com|user-1|ws-go-a|ws-plus-b'
# The login success line may name the account email; keys, runtime keys,
# user ids, and workspace ids are still forbidden there.
LOGIN_STDOUT_PAT='vela_ctrl_|rt-secret|user-1|ws-go-a|ws-plus-b'

assert_clean() { # assert_clean <label> <file>
  local pat="${3:-$SECRET_PAT}"
  if grep -Eq "$pat" "$2"; then
    fail "$1 leaked a secret: $(grep -E "$pat" "$2" | sed -n 1p)"
  fi
}

# --- 1: no sign-in slots -----------------------------------------------------

rm -f "$AI_USAGE_CACHE"
: >"$STUB_REQUESTS_LOG"
"$BIN" probe amr >"$TMP/probe-s1.out" 2>"$TMP/probe-s1.err" ||
  fail "scenario-1 probe exited $?"
[[ "$(wc -l <"$STUB_REQUESTS_LOG")" == 0 ]] ||
  fail "no-slot probe hit the network ($(wc -l <"$STUB_REQUESTS_LOG") requests)"
python3 - "$AI_USAGE_CACHE" <<'PY'
import json
import sys
rec = json.load(open(sys.argv[1], encoding="utf-8"))["providers"]["amr"]
assert rec["status"] == "unauth", rec
assert rec["reason"] == "no_login", rec
assert rec["account_usage"] == [], rec
PY
assert_clean "scenario-1 cache" "$AI_USAGE_CACHE"
assert_clean "scenario-1 probe stdout" "$TMP/probe-s1.out"

# --- 2: two accounts — plan windows, wallet, rendering ------------------------

rm -f "$AI_USAGE_CACHE"
: >"$STUB_REQUESTS_LOG"
rm -rf "$AI_USAGE_AMR_DIR"
slot 1 vela_ctrl_go_a
slot 2 vela_ctrl_plus_b
# Silently skipped: a non-numeric dir holding a valid config, an empty numeric
# one. The notes key must never show up in the request log.
slot notes vela_ctrl_notes_x
mkdir -p "$AI_USAGE_AMR_DIR/7"

"$BIN" probe amr >"$TMP/probe-s2.out" 2>"$TMP/probe-s2.err" ||
  fail "scenario-2 probe exited $?"

python3 - "$AI_USAGE_CACHE" <<'PY'
import json
import sys
rec = json.load(open(sys.argv[1], encoding="utf-8"))["providers"]["amr"]


def num(value):
    assert value is not None
    return float(value)


def window_matches(win, kind, pct, reset):
    # Label wording (e.g. "2-account Weekly" vs "weekly") is the
    # implementation's business: behavior is kind, percent, reset.
    assert win["kind"] == kind, win
    if pct is None:
        assert "used_pct" not in win, win
    else:
        assert num(win.get("used_pct")) == float(pct), win
    if reset is None:
        assert "resets_at" not in win, win
    else:
        assert win.get("resets_at") == reset, win


assert rec["status"] == "ok", rec
assert "reason" not in rec, rec
assert rec["plan"] == "Go · Plus", rec

rows = rec["account_usage"]
assert [r["slot"] for r in rows] == [1, 2], rows

r1, r2 = rows
assert r1["fetched_at"] == "2100-01-01T00:00:00Z", r1
assert r1["plan"] == "Go", r1
assert set(r1["windows"]) == {"session", "weekly"}, r1
s1 = r1["windows"]["session"]
assert s1["label"] == "5h" and s1["kind_label"] == "5 Hour limit", s1
assert num(s1["used_pct"]) == 25.0, s1
assert s1["resets_at"] == "2100-01-01T03:00:00Z", s1
w1 = r1["windows"]["weekly"]
assert w1["label"] == "7d" and w1["kind_label"] == "Weekly limit", w1
assert num(w1["used_pct"]) == 42.0, w1
assert w1["resets_at"] == "2100-01-05T00:00:00Z", w1
assert r1["label"] == "Weekly limit", r1
assert num(r1["used_pct"]) == 42.0, r1
assert r1["resets_at"] == "2100-01-05T00:00:00Z", r1
assert num(r1["remaining_usd"]) == 12.5, r1

assert r2["fetched_at"] == "2100-01-01T00:05:00Z", r2
assert r2["plan"] == "Plus", r2
assert set(r2["windows"]) == {"weekly", "window-86400"}, r2
w2 = r2["windows"]["weekly"]
assert num(w2["used_pct"]) == 75.0, w2
assert w2["resets_at"] == "2100-01-03T00:00:00Z", w2
d2 = r2["windows"]["window-86400"]
assert d2["label"] == "1d" and d2["kind_label"] == "1d limit", d2
assert num(d2["used_pct"]) == 10.0, d2
assert "resets_at" not in d2, d2
assert r2["label"] == "Weekly limit", r2
assert num(r2["used_pct"]) == 75.0, r2
assert r2["resets_at"] == "2100-01-03T00:00:00Z", r2
assert num(r2["remaining_usd"]) == 3.2, r2

kinds = [w["kind"] for w in rec["windows"]]
assert kinds == ["weekly", "session", "window-86400", "special", "credits"], rec["windows"]
window_matches(rec["windows"][0], "weekly", 58.5, "2100-01-03T00:00:00Z")
window_matches(rec["windows"][1], "session", 25, "2100-01-01T03:00:00Z")
window_matches(rec["windows"][2], "window-86400", 10, None)
window_matches(rec["windows"][3], "special", 75, "2100-01-03T00:00:00Z")
credits = rec["windows"][4]
assert "used_pct" not in credits, credits
assert num(credits["extra"]["remaining_usd"]) == 15.7, credits

assert rec["snapshot"] == {"reports": 2, "accounts_without_usage": 0, "disabled_credentials": 0}, rec
assert rec["measured_at"] == "2100-01-01T00:00:00Z", rec
PY

# Every request identifies as ai-usage/<version>, slot 1's preflight quotes
# the personal workspace it picked, and the notes dir never got a request.
python3 - "$STUB_REQUESTS_LOG" "$WANT_UA" <<'PY'
import json
import sys
entries = [json.loads(line) for line in open(sys.argv[1], encoding="utf-8")]
want_ua = sys.argv[2]
assert len(entries) == 4, entries
for entry in entries:
    assert entry["user_agent"] == want_ua, entry
by_path = {e["path"]: e for e in entries}
pre = by_path.get("/api/v1/workspaces/ws-go-a/billing/preflight")
assert pre is not None and pre["workspace_header"] == "ws-go-a", entries
# Concatenate so the synthetic Bearer never appears as a token-shaped literal
# (tests/test-secrets.sh gates `Bearer <16+ chars>` in repo sources).
assert pre["authorization"] == "Bearer " + "vela_ctrl_go_a", pre
for entry in entries:
    assert entry["authorization"] != "Bearer " + "vela_ctrl_notes_x", entry
PY

"$BIN" select amr >/dev/null
"$BIN" waybar >"$TMP/waybar-s2.json" 2>"$TMP/waybar-s2.err"
python3 - "$TMP/waybar-s2.json" <<'PY'
import json
import sys
payload = json.load(open(sys.argv[1], encoding="utf-8"))
text = payload["text"]
assert text.startswith("◇ "), text
assert text.count("<span bgcolor='#3a3a3a'>") == 2, text
assert payload["alt"] == "amr", payload
tip = payload["tooltip"]
for needle in ("OpenDesign", "Go · Plus", "$15.70 left", "2 account reports"):
    assert needle in tip, (needle, tip)
PY
assert_clean "scenario-2 cache" "$AI_USAGE_CACHE"
assert_clean "scenario-2 probe stdout" "$TMP/probe-s2.out"
assert_clean "scenario-2 waybar json" "$TMP/waybar-s2.json"

dump="$("$BIN" tui --dump 2>/dev/null)"
grep -F '$15.70' <<<"$dump" >/dev/null || fail "TUI dump lacks the wallet total: $dump"
grep -F 'wallet balance · spent after the Coding Plan windows' <<<"$dump" >/dev/null ||
  fail "TUI dump lacks the wallet note: $dump"

"$BIN" validate >/dev/null || fail "scenario-2 cache failed validation"

# --- 3: wallet-only + expired slots — partial usage ---------------------------

slot 3 vela_ctrl_wallet_c
slot 4 vela_ctrl_expired_d
"$BIN" probe amr >"$TMP/probe-s3.out" 2>"$TMP/probe-s3.err" ||
  fail "scenario-3 probe exited $?"

python3 - "$AI_USAGE_CACHE" <<'PY'
import json
import sys
rec = json.load(open(sys.argv[1], encoding="utf-8"))["providers"]["amr"]
assert rec["status"] == "ok", rec
assert rec["reason"] == "partial_usage", rec
rows = rec["account_usage"]
assert [r["slot"] for r in rows] == [1, 2, 3, 4], rows
r3 = rows[2]
assert float(r3["remaining_usd"]) == 4.0, r3
assert "used_pct" not in r3, r3
assert "plan" not in r3, r3
assert "label" not in r3, r3
assert rows[3] == {"slot": 4, "error": "login_expired"}, rows[3]
kinds = [w["kind"] for w in rec["windows"]]
assert kinds == ["weekly", "session", "window-86400", "special"], kinds
special = rec["windows"][3]
assert "used_pct" not in special, special
assert rec["snapshot"] == {"reports": 3, "accounts_without_usage": 1, "disabled_credentials": 0}, rec
assert "measured_at" not in rec, rec
PY

"$BIN" select amr >/dev/null
"$BIN" waybar >"$TMP/waybar-s3.json" 2>"$TMP/waybar-s3.err"
python3 - "$TMP/waybar-s3.json" <<'PY'
import json
import sys
payload = json.load(open(sys.argv[1], encoding="utf-8"))
text = payload["text"]
assert text.endswith(" $4.00 —"), text
assert text.count("<span bgcolor='#3a3a3a'>") == 2, text
lines = payload["tooltip"].splitlines()
row4 = [line for line in lines if line.startswith(" 4 ")]
assert row4 and "login expired" in row4[0], lines
PY
assert_clean "scenario-3 cache" "$AI_USAGE_CACHE"
assert_clean "scenario-3 probe stdout" "$TMP/probe-s3.out"
assert_clean "scenario-3 waybar json" "$TMP/waybar-s3.json"

# --- 4: two slots signing in to the same account ------------------------------

rm -f "$AI_USAGE_CACHE"
rm -rf "$AI_USAGE_AMR_DIR"
slot 1 vela_ctrl_go_a
slot 2 vela_ctrl_go_dup
"$BIN" probe amr >"$TMP/probe-s4.out" 2>"$TMP/probe-s4.err" ||
  fail "scenario-4 probe exited $?"
python3 - "$AI_USAGE_CACHE" <<'PY'
import json
import sys
rec = json.load(open(sys.argv[1], encoding="utf-8"))["providers"]["amr"]
rows = rec["account_usage"]
assert [r["slot"] for r in rows] == [1], rows
assert rec["snapshot"]["reports"] == 1, rec
PY
assert_clean "scenario-4 cache" "$AI_USAGE_CACHE"
assert_clean "scenario-4 probe stdout" "$TMP/probe-s4.out"

# --- 5: every login expired, then keep-last-good ------------------------------

rm -f "$AI_USAGE_CACHE"
rm -rf "$AI_USAGE_AMR_DIR"
slot 4 vela_ctrl_expired_d
"$BIN" probe amr >"$TMP/probe-s5.out" 2>"$TMP/probe-s5.err" ||
  fail "scenario-5 probe exited $?"
python3 - "$AI_USAGE_CACHE" <<'PY'
import json
import sys
rec = json.load(open(sys.argv[1], encoding="utf-8"))["providers"]["amr"]
assert rec["status"] == "unauth", rec
assert rec["reason"] == "login_expired", rec
PY
assert_clean "scenario-5 cache" "$AI_USAGE_CACHE"
assert_clean "scenario-5 probe stdout" "$TMP/probe-s5.out"

rm -f "$AI_USAGE_CACHE"
rm -rf "$AI_USAGE_AMR_DIR"
slot 1 vela_ctrl_go_a
slot 2 vela_ctrl_plus_b
"$BIN" probe amr >"$TMP/probe-s5b.out" 2>"$TMP/probe-s5b.err" ||
  fail "scenario-5 keep-good probe exited $?"
rm -rf "$AI_USAGE_AMR_DIR"
slot 4 vela_ctrl_expired_d
"$BIN" probe amr >"$TMP/probe-s5c.out" 2>"$TMP/probe-s5c.err" ||
  fail "scenario-5 re-probe exited $?"
python3 - "$AI_USAGE_CACHE" <<'PY'
import json
import sys
rec = json.load(open(sys.argv[1], encoding="utf-8"))["providers"]["amr"]
assert rec["status"] == "ok", rec
assert rec["last_error"] == "login_expired", rec
PY
assert_clean "scenario-5 re-probe cache" "$AI_USAGE_CACHE"
assert_clean "scenario-5 re-probe stdout" "$TMP/probe-s5c.out"

# --- 6: account API unreachable -----------------------------------------------

rm -f "$AI_USAGE_CACHE"
rm -rf "$AI_USAGE_AMR_DIR"
slot 1 vela_ctrl_go_a
slot 2 vela_ctrl_plus_b
closed_port="$(python3 -c 'import socket; s = socket.socket(); s.bind(("127.0.0.1", 0)); print(s.getsockname()[1]); s.close()')"
: >"$STUB_REQUESTS_LOG"
AI_USAGE_AMR_API_URL="http://127.0.0.1:$closed_port" "$BIN" probe amr \
  >"$TMP/probe-s6.out" 2>"$TMP/probe-s6.err" ||
  fail "scenario-6 probe exited $?"
python3 - "$AI_USAGE_CACHE" <<'PY'
import json
import sys
rec = json.load(open(sys.argv[1], encoding="utf-8"))["providers"]["amr"]
assert rec["account_usage"] == [
    {"slot": 1, "error": "network"},
    {"slot": 2, "error": "network"},
], rec
assert rec["status"] == "unknown", rec
assert rec["reason"] == "network", rec
PY
[[ "$(wc -l <"$STUB_REQUESTS_LOG")" == 0 ]] ||
  fail "unreachable probe still reached the stub"
assert_clean "scenario-6 cache" "$AI_USAGE_CACHE"
assert_clean "scenario-6 probe stdout" "$TMP/probe-s6.out"

# --- 7: secrets stay out of cache, stdout, and Waybar --------------------------
# (covered by the assert_clean calls after every probe and waybar run above)

# --- 8: login amr drives the vela slots ----------------------------------------

rm -f "$AI_USAGE_CACHE"
export AI_USAGE_AMR_DIR="$TMP/amr-login"
mkdir -p "$TMP/fakebin"
export AI_USAGE_VELA_BIN="$TMP/fakebin/vela"
export FAKE_VELA_LOG="$TMP/vela.log"
export VELA_CONTROL_KEY=leak

cat >"$AI_USAGE_VELA_BIN" <<'SH'
#!/usr/bin/env bash
# Fake `vela login`: record the env the CLI handed it, then write the slot
# config vela would have written (control key only in `ok` mode).
printf '%s|%s|%s\n' "${AMR_HOME:-}" "${VELA_PROFILE:-}" "${VELA_CONTROL_KEY-unset}" >>"$FAKE_VELA_LOG"
mode="${FAKE_VELA_MODE:-ok}"
if [[ "$mode" == fail ]]; then
  exit 1
fi
mkdir -p "$AMR_HOME"
MODE="$mode" python3 - <<'PY'
import json
import os
profiles = {"prod": {"runtimeKey": "rt-secret", "apiUrl": "https://amr-api.invalid"}}
if os.environ["MODE"] == "ok":
    profiles["prod"].update({
        "controlKey": os.environ["FAKE_VELA_KEY"],
        "user": {
            "id": os.environ["FAKE_VELA_USER"],
            "email": os.environ["FAKE_VELA_USER"] + "@example.com",
        },
    })
with open(os.path.join(os.environ["AMR_HOME"], "config.json"), "w", encoding="utf-8") as fh:
    json.dump({"profiles": profiles}, fh)
PY
SH
chmod +x "$AI_USAGE_VELA_BIN"

: >"$FAKE_VELA_LOG"
FAKE_VELA_MODE=ok FAKE_VELA_USER=user-u1 FAKE_VELA_KEY=vela_ctrl_go_a \
  "$BIN" login amr >"$TMP/login-1.out" 2>"$TMP/login-1.err" ||
  fail "login amr (user-u1) exited $?"
[[ "$(stat -c %a "$AI_USAGE_AMR_DIR/1")" == 700 ]] ||
  fail "slot 1 dir mode is $(stat -c %a "$AI_USAGE_AMR_DIR/1"), want 700"
[[ "$(stat -c %a "$AI_USAGE_AMR_DIR/1/config.json")" == 600 ]] ||
  fail "slot 1 config mode is $(stat -c %a "$AI_USAGE_AMR_DIR/1/config.json"), want 600"
grep -q 'signed in as slot 1' "$TMP/login-1.out" ||
  fail "login stdout: $(cat "$TMP/login-1.out")"
[[ "$(cat "$FAKE_VELA_LOG")" == "$AI_USAGE_AMR_DIR/1|prod|unset" ]] ||
  fail "vela env log: $(cat "$FAKE_VELA_LOG")"
python3 - "$AI_USAGE_CACHE" <<'PY'
import json
import sys
rec = json.load(open(sys.argv[1], encoding="utf-8"))["providers"]["amr"]
assert rec["status"] == "ok", rec
PY
assert_clean "scenario-8 login cache" "$AI_USAGE_CACHE"
assert_clean "scenario-8 login stdout" "$TMP/login-1.out" "$LOGIN_STDOUT_PAT"

FAKE_VELA_MODE=ok FAKE_VELA_USER=user-u2 FAKE_VELA_KEY=vela_ctrl_plus_b \
  "$BIN" login amr >"$TMP/login-2.out" 2>"$TMP/login-2.err" ||
  fail "login amr (user-u2) exited $?"
grep -q 'signed in as slot 2' "$TMP/login-2.out" ||
  fail "second login stdout: $(cat "$TMP/login-2.out")"
[[ -d "$AI_USAGE_AMR_DIR/2" ]] || fail "slot 2 missing after the second login"

FAKE_VELA_MODE=ok FAKE_VELA_USER=user-u1 FAKE_VELA_KEY=vela_ctrl_go_a \
  "$BIN" login amr >"$TMP/login-3.out" 2>"$TMP/login-3.err" ||
  fail "re-login exited $?"
[[ -d "$AI_USAGE_AMR_DIR/3" ]] || fail "slot 3 missing after the re-login"
[[ ! -e "$AI_USAGE_AMR_DIR/1" ]] || fail "re-login left the replaced slot 1 behind"
grep -q 'replaced slot 1' "$TMP/login-3.out" ||
  fail "re-login stdout: $(cat "$TMP/login-3.out")"

if FAKE_VELA_MODE=fail FAKE_VELA_USER=user-bad FAKE_VELA_KEY=vela_ctrl_go_a \
  "$BIN" login amr >"$TMP/login-fail.out" 2>"$TMP/login-fail.err"; then
  fail "failed vela login exited 0"
fi
grep -q 'did not complete' "$TMP/login-fail.err" ||
  fail "failed login stderr: $(cat "$TMP/login-fail.err")"
[[ ! -e "$AI_USAGE_AMR_DIR/4" ]] || fail "failed login left slot 4 behind"

if FAKE_VELA_MODE=nokey FAKE_VELA_USER=user-nokey FAKE_VELA_KEY=vela_ctrl_go_a \
  "$BIN" login amr >"$TMP/login-nokey.out" 2>"$TMP/login-nokey.err"; then
  fail "keyless vela login exited 0"
fi
grep -q 'did not complete' "$TMP/login-nokey.err" ||
  fail "keyless login stderr: $(cat "$TMP/login-nokey.err")"
[[ ! -e "$AI_USAGE_AMR_DIR/4" ]] || fail "keyless login left slot 4 behind"

if AI_USAGE_VELA_BIN="$TMP/does-not-exist" \
  "$BIN" login amr >"$TMP/login-missing.out" 2>"$TMP/login-missing.err"; then
  fail "login with a missing vela exited 0"
fi
grep -q '@powerformer/vela-cli' "$TMP/login-missing.err" ||
  fail "missing-vela stderr: $(cat "$TMP/login-missing.err")"
[[ ! -e "$AI_USAGE_AMR_DIR/4" ]] || fail "missing-vela login created a slot dir"

"$BIN" validate >/dev/null || fail "scenario-8 cache failed validation"

echo AMR_OK

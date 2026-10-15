#!/usr/bin/env bash
# Opt-in provider roster: AI_USAGE_PROVIDERS (env) and ~/.config/ai-usage/providers
# (file, path overridable with AI_USAGE_PROVIDERS_FILE) scope probing, cycling,
# the chip row, and the TUI id list. No roster keeps every provider. Seeded
# cache + fake omp, no network.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BIN="$ROOT/bin/ai-usage"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

if [[ ! -x "$BIN" ]]; then
  fail "missing executable $BIN"
fi

export HOME="$TMP/home"
export XDG_CACHE_HOME="$TMP/cache-home"
export XDG_CONFIG_HOME="$TMP/config-home"
export XDG_STATE_HOME="$TMP/state-home"
export AI_USAGE_CACHE="$TMP/status.json"
export AI_USAGE_SELECTED="$TMP/selected"
export AI_USAGE_OMP_BIN="$TMP/bin/fake-omp"
export AI_USAGE_OMP_LOG="$TMP/omp.log"
export AI_USAGE_WAYBAR_CONFIG="$TMP/waybar-absent.jsonc"
export AI_USAGE_PGREP_LOG="$TMP/pgrep.log"
export PATH="$TMP/bin:$PATH"
mkdir -p "$TMP/bin" "$HOME/.local/bin" "$XDG_CACHE_HOME" "$XDG_CONFIG_HOME"

# cycle/select poke Waybar through pgrep, and ensure_path() prepends
# ~/.local/bin ahead of PATH — so the stub lives in both places to be sure the
# test never signals the real desktop's waybar.
cat >"$TMP/bin/pgrep" <<'SH'
#!/usr/bin/env bash
printf 'pgrep %s\n' "$*" >>"$AI_USAGE_PGREP_LOG"
exit 1
SH
chmod +x "$TMP/bin/pgrep"
cp "$TMP/bin/pgrep" "$HOME/.local/bin/pgrep"

cat >"$TMP/bin/fake-omp" <<'SH'
#!/usr/bin/env bash
# Log the OMP provider asked for, then answer an empty (but valid) payload.
printf '%s\n' "$*" >>"$AI_USAGE_OMP_LOG"
printf '%s\n' '{"reports":[],"accountsWithoutUsage":[],"disabledCredentials":[]}'
SH
chmod +x "$TMP/bin/fake-omp"

ABSENT_ROSTER="$TMP/roster-absent"

# seed_cache <selected> <pid>... — every listed provider gets a usable record;
# prefix a pid with `!` to seed an unauth (unusable) one instead.
seed_cache() {
  local selected="$1"
  shift
  python3 - "$AI_USAGE_CACHE" "$AI_USAGE_SELECTED" "$selected" "$@" <<'PY'
import json
import sys
from datetime import datetime, timezone

cache_path, selected_path, selected, specs = sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4:]
names = {
    "codex": ("Codex", "C"), "token-plan": ("Token Plan", "T"), "grok": ("Grok", "G"),
    "kimi": ("Kimi", "K"), "cursor": ("Cursor", "R"), "devin": ("Devin", "D"),
    "devin2": ("Devin 2", "d"), "opencode-go": ("OpenCode Go", "O"),
    "charm-hyper": ("Charm Hyper", "H"), "zai": ("Z.ai", "Z"), "google": ("Google", "g"),
}
providers = {}
for step, spec in enumerate(specs, start=1):
    usable = not spec.startswith("!")
    pid = spec.lstrip("!")
    name, logo = names[pid]
    rec = {"id": pid, "name": name, "logo": logo, "status": "ok" if usable else "unauth"}
    if usable:
        rec["windows"] = [
            {"kind": "weekly", "label": "Weekly", "used_pct": step * 5},
            {"kind": "special", "label": "Hottest", "used_pct": step * 5},
        ]
    else:
        rec["reason"] = "no_omp_usage"
        rec["windows"] = [
            {"kind": "weekly", "label": "Weekly"},
            {"kind": "special", "label": "Hottest"},
        ]
    providers[pid] = rec
cache = {
    "version": 2,
    "updated_at": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
    "selected": selected,
    "providers": providers,
}
with open(cache_path, "w", encoding="utf-8") as fh:
    json.dump(cache, fh, indent=2, ensure_ascii=False)
    fh.write("\n")
with open(selected_path, "w", encoding="utf-8") as fh:
    fh.write(selected + "\n")
PY
}

# cycle_walk <direction> <times> — one selected id per line.
cycle_walk() {
  local direction="$1" times="$2" i
  for ((i = 0; i < times; i++)); do
    "$BIN" cycle "$direction"
  done
}

# --- env roster scopes cycle -------------------------------------------------

seed_cache kimi codex kimi zai google devin
export AI_USAGE_PROVIDERS="kimi zai"
export AI_USAGE_PROVIDERS_FILE="$ABSENT_ROSTER"

err="$TMP/err-env-cycle"
visited="$(
  {
    cycle_walk next 2
    cycle_walk prev 1
  } 2>"$err"
)"
[[ ! -s "$err" ]] || fail "clean env roster warned: $(cat "$err")"
# codex, google, and devin are usable in the cache but off-roster: the cycle
# must stay inside kimi <-> zai and wrap both ways.
[[ "$visited" == "$(printf 'zai\nkimi\nzai')" ]] ||
  fail "env roster cycle visited $(printf '%s' "$visited" | tr '\n' ' ')want 'zai kimi zai'"
[[ "$(cat "$AI_USAGE_SELECTED")" == zai ]] || fail "selected file not roster-scoped"
alt="$("$BIN" waybar | jq -r .alt)"
[[ "$alt" == zai ]] || fail "waybar alt=$alt want zai"

# The roster filters PROVIDERS, it does not reorder them: written backwards, the
# cycle still walks canonical order.
export AI_USAGE_PROVIDERS="zai kimi codex"
seed_cache kimi codex kimi zai google
err="$TMP/err-order"
visited="$(cycle_walk next 3 2>"$err")"
[[ ! -s "$err" ]] || fail "reordered roster warned: $(cat "$err")"
[[ "$visited" == "$(printf 'zai\ncodex\nkimi')" ]] ||
  fail "reordered roster cycled $(printf '%s' "$visited" | tr '\n' ' ')want 'zai codex kimi'"

# --- file roster scopes cycle ------------------------------------------------

cat >"$TMP/roster" <<'EOF'
# only the models authed on this machine
codex
kimi   # inline comment is skipped

zai
EOF
unset AI_USAGE_PROVIDERS
export AI_USAGE_PROVIDERS_FILE="$TMP/roster"

seed_cache codex codex kimi zai google devin
err="$TMP/err-file-cycle"
visited="$(
  {
    cycle_walk next 3
    cycle_walk prev 1
  } 2>"$err"
)"
[[ ! -s "$err" ]] || fail "clean file roster warned: $(cat "$err")"
[[ "$visited" == "$(printf 'kimi\nzai\ncodex\nzai')" ]] ||
  fail "file roster cycle visited $(printf '%s' "$visited" | tr '\n' ' ')want 'kimi zai codex zai'"

# --- no roster: every usable provider cycles ---------------------------------

export AI_USAGE_PROVIDERS_FILE="$ABSENT_ROSTER"
seed_cache codex codex kimi zai google devin
err="$TMP/err-no-roster"
visited="$(cycle_walk next 5 2>"$err")"
[[ ! -s "$err" ]] || fail "no roster warned: $(cat "$err")"
# PROVIDERS order over the five usable records, wrapping back to the start.
[[ "$visited" == "$(printf 'kimi\ndevin\nzai\ngoogle\ncodex')" ]] ||
  fail "no-roster cycle visited $(printf '%s' "$visited" | tr '\n' ' ')want 'kimi devin zai google codex'"

# --- unknown id warns once and is skipped ------------------------------------

export AI_USAGE_PROVIDERS="codex bogus-model kimi"
seed_cache codex codex kimi zai
err="$TMP/err-unknown"
out="$("$BIN" cycle next 2>"$err")"
[[ "$out" == kimi ]] || fail "unknown id changed the cycle: got '$out' want 'kimi'"
[[ "$(grep -c 'bogus-model' "$err")" == 1 ]] ||
  fail "want exactly one warning naming bogus-model, got: $(cat "$err")"
[[ "$(wc -l <"$err")" == 1 ]] || fail "warning is not one line: $(cat "$err")"

# Same roster, but now the selection is unusable too, so cmd_cycle and
# pick_selected each resolve the roster: still one warning per bad id per run.
seed_cache codex '!codex' kimi zai
err="$TMP/err-unknown-twice"
out="$("$BIN" cycle next 2>"$err")"
[[ "$out" == kimi ]] || fail "unusable selection with a bad id in the roster: got '$out' want 'kimi'"
[[ "$(wc -l <"$err")" == 1 ]] || fail "warning repeated per roster read: $(cat "$err")"

# A roster of nothing but unknown ids falls back to every provider instead of
# blanking the chip.
export AI_USAGE_PROVIDERS="bogus-model,nope-2"
seed_cache codex codex kimi zai
err="$TMP/err-all-unknown"
out="$("$BIN" cycle next 2>"$err")"
[[ "$out" == kimi ]] || fail "all-unknown roster did not fall back: got '$out' want 'kimi'"
grep -q 'bogus-model' "$err" || fail "all-unknown roster stayed silent"
grep -q 'nope-2' "$err" || fail "all-unknown roster named only one bad id"

# --- unusable selection falls back in the roster -----------------------------

# codex is selected but unauth, so the chip must land on the first *rostered*
# usable provider (zai) and never on an off-roster one (kimi).
export AI_USAGE_PROVIDERS="zai google"
export AI_USAGE_PROVIDERS_FILE="$ABSENT_ROSTER"
seed_cache codex '!codex' kimi zai google
alt="$("$BIN" waybar | jq -r .alt)"
[[ "$alt" == zai ]] || fail "unusable selection fell back off-roster: alt=$alt want zai"
nxt="$("$BIN" cycle next)"
[[ "$nxt" == google ]] || fail "cycle from a rostered fallback: got '$nxt' want 'google'"

# --- probe: default targets are the roster, explicit ids are not -------------

export AI_USAGE_PROVIDERS="codex kimi"
export AI_USAGE_PROVIDERS_FILE="$ABSENT_ROSTER"
rm -f "$AI_USAGE_CACHE"
: >"$AI_USAGE_OMP_LOG"
err="$TMP/err-probe"
out="$("$BIN" probe 2>"$err")"
[[ ! -s "$err" ]] || fail "clean roster probe warned: $(cat "$err")"
probed="$(printf '%s\n' "$out" | awk '{print $1}' | tr '\n' ' ')"
[[ "$probed" == "codex kimi " ]] || fail "roster probe printed: $probed"
[[ "$(wc -l <"$AI_USAGE_OMP_LOG")" == 2 ]] ||
  fail "roster probe ran $(wc -l <"$AI_USAGE_OMP_LOG") omp calls, want 2"
cached="$(jq -r '.providers | keys | join(" ")' "$AI_USAGE_CACHE")"
[[ "$cached" == "codex kimi" ]] || fail "roster probe cached: $cached"

# An explicit id is unrestricted: zai is off-roster but still probed on demand.
: >"$AI_USAGE_OMP_LOG"
out="$("$BIN" probe zai)"
[[ "$out" == zai* ]] || fail "explicit off-roster probe printed: $out"
[[ "$(cat "$AI_USAGE_OMP_LOG")" == 'usage --provider zai --json' ]] ||
  fail "explicit off-roster probe queried omp with: $(cat "$AI_USAGE_OMP_LOG")"
if "$BIN" probe bogus-model >/dev/null 2>&1; then
  fail "probe accepted an unknown provider id"
fi

# No roster probes all 11 providers, as before.
unset AI_USAGE_PROVIDERS
rm -f "$AI_USAGE_CACHE"
: >"$AI_USAGE_OMP_LOG"
"$BIN" probe >/dev/null
[[ "$(wc -l <"$AI_USAGE_OMP_LOG")" == 11 ]] ||
  fail "no-roster probe ran $(wc -l <"$AI_USAGE_OMP_LOG") omp calls, want 11"
[[ "$(jq -r '.providers | length' "$AI_USAGE_CACHE")" == 11 ]] ||
  fail "no-roster probe did not cache 11 providers"

# --- select stays unrestricted; chip row is roster-scoped --------------------

export AI_USAGE_PROVIDERS="codex kimi"
seed_cache codex codex kimi zai google
"$BIN" select zai >/dev/null
[[ "$(cat "$AI_USAGE_SELECTED")" == zai ]] || fail "select refused an off-roster provider"
alt="$("$BIN" waybar | jq -r .alt)"
[[ "$alt" == zai ]] || fail "off-roster selection not honored: alt=$alt want zai"
if "$BIN" select bogus-model >/dev/null 2>&1; then
  fail "select accepted an unknown provider id"
fi

"$BIN" select kimi >/dev/null
dump="$("$BIN" tui --dump)"
chips="$(printf '%s\n' "$dump" | awk 'NR>1 && $0=="" {getline; print; exit}')"
[[ "$chips" == *"[Kimi]"* ]] || fail "chip row lost the selected marker: '$chips'"
[[ "$chips" == *Codex* ]] || fail "chip row dropped a rostered provider: '$chips'"
[[ "$chips" != *Google* ]] || fail "chip row shows an off-roster provider: '$chips'"
[[ "$chips" != *Z.ai* ]] || fail "chip row shows an off-roster provider: '$chips'"

# --- TUI: number keys map onto the roster, and a short roster cannot crash ---

seed_cache codex codex kimi zai google
python3 - "$BIN" "$AI_USAGE_SELECTED" <<'PY'
import contextlib
import importlib.machinery
import importlib.util
import io
import sys
import types
from pathlib import Path

loader = importlib.machinery.SourceFileLoader("ai_usage", sys.argv[1])
spec = importlib.util.spec_from_loader("ai_usage", loader)
mod = importlib.util.module_from_spec(spec)
loader.exec_module(mod)


class _Err(Exception):
    pass


fake = types.ModuleType("curses")
fake.error = _Err
fake.KEY_RIGHT = "KEY_RIGHT"
fake.KEY_LEFT = "KEY_LEFT"
fake.KEY_RESIZE = "KEY_RESIZE"
fake.curs_set = lambda _n: None
sys.modules["curses"] = fake


class FakeScreen:
    """Scripted keys; `5` is out of range for a two-provider roster."""

    def __init__(self, keys):
        self.keys = list(keys)

    def keypad(self, _flag):
        pass

    def nodelay(self, _flag):
        pass

    def erase(self):
        pass

    def getmaxyx(self):
        return (40, 120)

    def addnstr(self, _y, _x, _text, _n):
        pass

    def refresh(self):
        pass

    def get_wch(self):
        return self.keys.pop(0) if self.keys else "q"


with contextlib.redirect_stdout(io.StringIO()):
    rc = mod._tui_loop(FakeScreen(["5", "2", "q"]))
if rc != 0:
    raise SystemExit(f"FAIL: TUI loop exited {rc} on an out-of-range digit")
selected = Path(sys.argv[2]).read_text(encoding="utf-8").strip()
if selected != "kimi":
    raise SystemExit(f"FAIL: TUI key 2 selected '{selected}' want 'kimi' (2nd rostered provider)")
print("TUI_ROSTER_OK")
PY

# Every Waybar poke must have hit the stub; a real pgrep would mean the test
# signalled the desktop it is running on.
[[ -s "$AI_USAGE_PGREP_LOG" ]] || fail "pgrep stub never ran: Waybar pokes escaped isolation"

echo PROVIDER_ROSTER_OK

#!/usr/bin/env bash
# Secret-safety gate. Prints PATH:line only — never matching secret values.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CACHE_DIR="${XDG_CACHE_HOME:-$HOME/.cache}/ai-usage"
FAIL=0
note() { printf '%s\n' "$*"; }
fail() { printf 'FAIL: %s\n' "$*" >&2; FAIL=1; }

# ripgrep if present; else grep -R. Suppress match text.
scan_hits() {
  local pattern=$1
  shift
  if command -v rg >/dev/null 2>&1; then
    rg -n --hidden --glob '!.git/**' -l -- "$pattern" "$@" 2>/dev/null || true
  else
    grep -RIl --exclude-dir=.git -- "$pattern" "$@" 2>/dev/null || true
  fi
}

note "== secret material in repo (fixtures/bin/deploy/systemd/tests) =="
# Require token-shaped values, not denylist documentation (`sk-sp-|Bearer |eyJ`).
SECRET_RE='sk-sp-[A-Za-z0-9]{8,}|sk-proj-[A-Za-z0-9]{8,}|sk-[A-Za-z0-9]{20,}|Bearer [A-Za-z0-9._-]{16,}|eyJ[A-Za-z0-9_-]{20,}\.[A-Za-z0-9_-]+\.'
for dir in fixtures bin deploy systemd tests; do
  [[ -d "$ROOT/$dir" ]] || continue
  while IFS= read -r f; do
    [[ -n "$f" ]] || continue
    [[ "$f" == *"/tests/test-secrets.sh" ]] && continue
    fail "secret-pattern in $f"
  done < <(scan_hits "$SECRET_RE" "$ROOT/$dir")
done

note "== banned invocations in ship paths =="
# token-plan-key prints the API key to stdout — never exec from bar/timer.
# omarchy refresh waybar copies stock config over ~/.config/waybar.
# bl --verbose / grok --debug dump HTTP auth material to stderr.
# Comments that document the ban do not count.
BANNED=(
  'token-plan-key'
  'omarchy refresh waybar'
  'omarchy-refresh-waybar'
  'bl --verbose'
  'bl usage token-plan --verbose'
  'grok --debug'
  'jq . ~/.codex/auth.json'
  'jq . ~/.grok/auth.json'
)
strip_c_and_hash_comments() {
  python3 - "$1" <<'PY'
import sys
from pathlib import Path
text = Path(sys.argv[1]).read_text(errors="replace")
out = []
for line in text.splitlines():
    s = line
    if "//" in s:
        s = s.split("//", 1)[0]
    if "#" in s:
        s = s.split("#", 1)[0]
    out.append(s)
print("\n".join(out))
PY
}
for dir in bin deploy systemd; do
  [[ -d "$ROOT/$dir" ]] || continue
  while IFS= read -r f; do
    [[ -n "$f" ]] || continue
    body=$(strip_c_and_hash_comments "$f")
    for pat in "${BANNED[@]}"; do
      if grep -Fq -- "$pat" <<<"$body"; then
        fail "banned pattern '$pat' in $f"
      fi
    done
  done < <(find "$ROOT/$dir" -type f)
done

note "== omarchy-share writes =="
if [[ -d "$ROOT/deploy" ]]; then
  while IFS= read -r f; do
    [[ -n "$f" ]] || continue
    body=$(strip_c_and_hash_comments "$f")
    if grep -Fq -- '.local/share/omarchy' <<<"$body"; then
      fail "omarchy share path in $f"
    fi
  done < <(find "$ROOT/deploy" "$ROOT/bin" -type f)
fi

note "== waybar exec must be cache-only =="
snippet="$ROOT/deploy/waybar-ai-usage.jsonc"
if [[ -f "$snippet" ]]; then
  if command -v rg >/dev/null 2>&1; then
    exec_line=$(rg -n '"exec"' "$snippet" || true)
  else
    exec_line=$(grep -n '"exec"' "$snippet" || true)
  fi
  if [[ -z "$exec_line" ]]; then
    fail "deploy/waybar-ai-usage.jsonc missing exec"
  else
    # path+line only
    printf 'exec at %s\n' "$(printf '%s\n' "$exec_line" | sed 's/:.*//')"
    if printf '%s\n' "$exec_line" | grep -Eq 'probe|refresh|token-plan-key|bl |grok |kimi |codex '; then
      fail "waybar exec is not cache-only (PATH: deploy/waybar-ai-usage.jsonc)"
    fi
    if ! printf '%s\n' "$exec_line" | grep -Eq 'ai-usage waybar|usage\.py'; then
      fail "waybar exec does not look like a cache renderer"
    fi
  fi
  if grep -Eq 'ai-usage refresh|ai-usage probe' "$snippet"; then
    fail "waybar snippet invokes probe/refresh (on-click/on-scroll leak) PATH:deploy/waybar-ai-usage.jsonc"
  fi
fi

note "== cache mode if present =="
if [[ -e "$CACHE_DIR" ]]; then
  dmode=$(stat -c '%a' "$CACHE_DIR")
  [[ "$dmode" == "700" ]] || fail "cache dir mode ${dmode} want 700 PATH:$CACHE_DIR"
  if [[ -f "$CACHE_DIR/status.json" ]]; then
    fmode=$(stat -c '%a' "$CACHE_DIR/status.json")
    [[ "$fmode" == "600" ]] || fail "cache file mode ${fmode} want 600 PATH:$CACHE_DIR/status.json"
    while IFS= read -r f; do
      [[ -n "$f" ]] || continue
      fail "secret-pattern in cache PATH:$CACHE_DIR/status.json"
    done < <(scan_hits "$SECRET_RE" "$CACHE_DIR/status.json")
  fi
fi

note "== redact must not emit Bearer prefix =="
python3 - "$ROOT/bin/ai-usage" <<'PY'
import importlib.machinery
import importlib.util
import sys
from pathlib import Path

bin_path = Path(sys.argv[1])
loader = importlib.machinery.SourceFileLoader("ai_usage", str(bin_path))
spec = importlib.util.spec_from_loader("ai_usage", loader)
mod = importlib.util.module_from_spec(spec)
loader.exec_module(mod)
sample = "Authorization: Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.aaa.bbb and sk-abcdefghijklmnopqrstuvwxyz"
out = mod.redact(sample)
if "Bearer " in out:
    raise SystemExit("FAIL: redact still emits Bearer prefix")
if "eyJ" in out or "sk-abcdefghijklmnop" in out:
    raise SystemExit("FAIL: redact leaked secret material")
if "[redacted]" not in out:
    raise SystemExit("FAIL: redact missing [redacted]")
print("REDACT_OK")
PY

if [[ "$FAIL" -ne 0 ]]; then
  note "SECRETS_GATE_FAIL"
  exit 1
fi
note "SECRETS_GATE_OK"
exit 0

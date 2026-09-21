#!/usr/bin/env bash
# Merge the Waybar chip + user timer on this Omarchy machine.
# Never touch ~/.local/share/omarchy. Never `omarchy refresh waybar`.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BIN="$ROOT/bin/ai-usage"
WAYBAR_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/waybar"
CFG="$WAYBAR_DIR/config.jsonc"
CSS="$WAYBAR_DIR/style.css"
HYPR="${XDG_CONFIG_HOME:-$HOME/.config}/hypr"
STAMP="$(date +%s)"

chmod +x "$BIN" "$ROOT/bin/cursor-oauth-swap" "$ROOT/install.sh" "$ROOT/deploy/install.sh" || true

if [[ ! -x "$BIN" ]]; then
  echo "install: missing $BIN" >&2
  exit 1
fi
if [[ ! -f "$CFG" ]]; then
  echo "install: missing $CFG (is this an Omarchy / Waybar machine?)" >&2
  exit 1
fi

cp -a "$CFG" "$CFG.bak.$STAMP"
[[ -f "$CSS" ]] && cp -a "$CSS" "$CSS.bak.$STAMP"

# The chip points at the installed symlink, not at this checkout: Waybar runs
# module commands through sh, so the module keeps working if the repo moves.
mkdir -p "$HOME/.local/bin"
ln -sfn "$BIN" "$HOME/.local/bin/ai-usage"
ln -sfn "$ROOT/bin/cursor-oauth-swap" "$HOME/.local/bin/cursor-oauth-swap"

python3 "$ROOT/deploy/merge_waybar.py" \
  "$CFG" "$CSS" "$ROOT/deploy/waybar-ai-usage.css" "~/.local/bin/ai-usage"

UNIT_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/systemd/user"
mkdir -p "$UNIT_DIR"
install -m 644 "$ROOT/systemd/ai-usage.service" "$UNIT_DIR/ai-usage.service"
install -m 644 "$ROOT/systemd/ai-usage.timer" "$UNIT_DIR/ai-usage.timer"

# Machine-local knobs (AI_USAGE_OMP_BIN, pool sizes, …) live outside the unit
# so re-running this installer never clobbers them. systemd expands neither
# variables nor %h inside the file, so the template carries literal paths.
ENV_FILE="${XDG_CONFIG_HOME:-$HOME/.config}/ai-usage/env"
mkdir -p "$(dirname "$ENV_FILE")"
if [[ ! -f "$ENV_FILE" ]]; then
  cat >"$ENV_FILE" <<EOF
# Local environment for ai-usage.service (optional; the unit tolerates it
# being absent). Values are literal: no shell expansion happens here.
#AI_USAGE_OMP_BIN=$HOME/.local/bin/omp
#AI_USAGE_TOKEN_PLAN_WEEKLY_CREDITS=40000
#AI_USAGE_TOKEN_PLAN_ADDON_CREDITS=20000
#AI_USAGE_CHARM_HYPER_LOW_CREDITS=25
EOF
  chmod 600 "$ENV_FILE"
fi
systemctl --user daemon-reload
systemctl --user enable --now ai-usage.timer

HYPR_RULES="$HYPR/ai-usage.conf"
if [[ -d "$HYPR" ]]; then
  cat >"$HYPR_RULES" <<'EOF'
# omarchy-usage-tray TUI — same float as other Omarchy TUIs
windowrule = tag +floating-window, match:class ^(org.omarchy.ai-usage)$
windowrule = float on, match:class ^(org.omarchy.ai-usage)$
windowrule = center on, match:class ^(org.omarchy.ai-usage)$
windowrule = size 875 600, match:class ^(org.omarchy.ai-usage)$
EOF
  HYPR_MAIN="$HYPR/hyprland.conf"
  if [[ -f "$HYPR_MAIN" ]] && ! grep -q 'org.omarchy.ai-usage' "$HYPR_MAIN" && ! grep -q 'hypr/ai-usage.conf' "$HYPR_MAIN"; then
    printf '\n# omarchy-usage-tray\nsource = ~/.config/hypr/ai-usage.conf\n' >>"$HYPR_MAIN"
  fi
  if command -v hyprctl >/dev/null 2>&1; then
    hyprctl reload >/dev/null 2>&1 || true
  fi
fi

"$BIN" probe >/dev/null 2>&1 || true

if command -v omarchy >/dev/null 2>&1; then
  omarchy restart waybar >/dev/null 2>&1 || true
elif command -v hyprctl >/dev/null 2>&1; then
  pkill -x waybar >/dev/null 2>&1 || true
  hyprctl dispatch exec waybar >/dev/null 2>&1 || true
fi

echo "omarchy-usage-tray installed"
echo "  binary  $HOME/.local/bin/ai-usage -> $BIN"
echo "  waybar  custom/ai-usage  (left/scroll = providers; right-click = identity)"
echo "  timer   systemd --user ai-usage.timer (5 min)"
echo "  backup  $CFG.bak.$STAMP"

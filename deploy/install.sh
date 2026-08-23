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

chmod +x "$BIN" "$ROOT/install.sh" "$ROOT/deploy/install.sh" || true

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

python3 "$ROOT/deploy/merge_waybar.py" "$CFG" "$CSS" "$ROOT/deploy/waybar-ai-usage.css" "$BIN"

mkdir -p "$HOME/.local/bin"
ln -sfn "$BIN" "$HOME/.local/bin/ai-usage"

UNIT_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/systemd/user"
mkdir -p "$UNIT_DIR"
cat >"$UNIT_DIR/ai-usage.service" <<EOF
[Unit]
Description=Probe AI CLI usage limits into cache

[Service]
Type=oneshot
TimeoutStartSec=180
Nice=10
Environment=PATH=%h/.local/bin:%h/.grok/bin:%h/.local/share/mise/shims:/usr/local/bin:/usr/bin
ExecStart=%h/.local/bin/ai-usage refresh
EOF
install -m 644 "$ROOT/systemd/ai-usage.timer" "$UNIT_DIR/ai-usage.timer"
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
echo "  waybar  custom/ai-usage  (left-click cycle, right-click TUI, scroll cycle)"
echo "  timer   systemd --user ai-usage.timer (5 min)"
echo "  backup  $CFG.bak.$STAMP"

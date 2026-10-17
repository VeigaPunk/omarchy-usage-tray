#!/usr/bin/env bash
# Stop the usage timer and remove the launcher symlink and user units.
# Leaves ~/.config/ai-usage/env in place. Does not delete Waybar backups.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
BIN="$ROOT/bin/ai-usage"
LINK="${HOME}/.local/bin/ai-usage"
UNIT_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/systemd/user"

systemctl --user disable --now ai-usage.timer >/dev/null 2>&1 || true
rm -f "$UNIT_DIR/ai-usage.service" "$UNIT_DIR/ai-usage.timer"
systemctl --user daemon-reload >/dev/null 2>&1 || true

if [[ -L "$LINK" ]]; then
  target="$(readlink -f "$LINK" || true)"
  if [[ "$target" == "$BIN" ]]; then
    rm -f "$LINK"
    echo "removed $LINK"
  fi
fi

python3 - <<'PY'
from pathlib import Path
home = Path.home()
waybar = home / ".config" / "waybar" / "config.jsonc"
if waybar.exists():
    text = waybar.read_text()
    original = text
    text = text.replace('\n    "custom/ai-usage",', "\n")
    start = text.find('  "custom/ai-usage": {')
    if start != -1:
        end = text.find("\n  }", start)
        if end != -1:
            text = text[:start] + text[end + 4 :]
    if text != original:
        waybar.write_text(text)
        print(f"removed custom/ai-usage from {waybar}")
css = home / ".config" / "waybar" / "style.css"
if css.exists() and "#custom-ai-usage" in css.read_text():
    print(f"edit {css} and delete the #custom-ai-usage rules")
hypr = home / ".config" / "hypr" / "hyprland.conf"
if hypr.exists():
    lines = hypr.read_text().splitlines(keepends=True)
    kept = [line for line in lines if "hypr/ai-usage.conf" not in line and line.strip() != "# omarchy-usage-tray"]
    if kept != lines:
        hypr.write_text("".join(kept))
        print(f"removed usage source from {hypr}")
rule = home / ".config" / "hypr" / "ai-usage.conf"
if rule.exists():
    rule.unlink()
    print(f"removed {rule}")
PY

if command -v omarchy >/dev/null 2>&1; then
  omarchy restart waybar >/dev/null 2>&1 || true
fi

echo "Waybar timer and units removed."
echo "Quattro: omarchy plugin remove io.github.veigapunk.usage-tray"

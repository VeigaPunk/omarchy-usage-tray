#!/usr/bin/env bash
# Install omarchy-usage-tray on any Omarchy (Waybar) machine.
#
#   curl -fsSL https://raw.githubusercontent.com/VeigaPunk/omarchy-usage-tray/main/install.sh | bash
set -euo pipefail

DEST="${OMARCHY_USAGE_TRAY_HOME:-${XDG_DATA_HOME:-$HOME/.local/share}/omarchy-usage-tray}"
REPO="${OMARCHY_USAGE_TRAY_REPO:-https://github.com/VeigaPunk/omarchy-usage-tray.git}"

self="${BASH_SOURCE[0]:-}"
if [[ -n "$self" && -f "$self" ]]; then
  here="$(cd "$(dirname "$self")" && pwd)"
  if [[ -x "$here/bin/ai-usage" && -f "$here/deploy/install.sh" ]]; then
    exec bash "$here/deploy/install.sh"
  fi
fi

command -v git >/dev/null 2>&1 || { echo "install.sh: git is required" >&2; exit 1; }
command -v python3 >/dev/null 2>&1 || { echo "install.sh: python3 is required" >&2; exit 1; }

if [[ -d "$DEST/.git" ]]; then
  git -C "$DEST" fetch --depth 1 origin
  git -C "$DEST" reset --hard FETCH_HEAD
else
  mkdir -p "$(dirname "$DEST")"
  git clone --depth 1 "$REPO" "$DEST"
fi

exec bash "$DEST/deploy/install.sh"

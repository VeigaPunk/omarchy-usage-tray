#!/usr/bin/env bash
# Install omarchy-usage-tray from a local checkout.
#   git clone https://github.com/VeigaPunk/omarchy-usage-tray.git
#   cd omarchy-usage-tray && ./install.sh
set -euo pipefail

self="${BASH_SOURCE[0]:-}"
if [[ -n "$self" && -f "$self" ]]; then
  here="$(cd "$(dirname "$self")" && pwd)"
  if [[ -x "$here/bin/ai-usage" && -f "$here/deploy/install.sh" ]]; then
    exec bash "$here/deploy/install.sh"
  fi
fi

echo "install.sh: run it from a clone of this repository" >&2
exit 1

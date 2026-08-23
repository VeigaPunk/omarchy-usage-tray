#!/usr/bin/env bash
# Cycle provider and poke Waybar. Probes belong to the systemd timer, not click.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
"$ROOT/bin/ai-usage" cycle next >/dev/null
pkill -x -RTMIN+11 waybar || true

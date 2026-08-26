#!/usr/bin/env bash
# M01: cursor fixture → cache → Waybar JSON. No network.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BIN="$ROOT/bin/ai-usage"
FIXTURE="$ROOT/fixtures/cursor.ultra.json"
ONDEMAND="$ROOT/fixtures/cursor.ondemand.json"

if [[ ! -x "$BIN" ]]; then
  echo "FAIL: missing executable $BIN" >&2
  exit 1
fi
if [[ ! -f "$FIXTURE" ]]; then
  echo "FAIL: missing $FIXTURE" >&2
  exit 1
fi
if [[ ! -f "$ONDEMAND" ]]; then
  echo "FAIL: missing $ONDEMAND" >&2
  exit 1
fi

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
export AI_USAGE_CACHE="$TMP/status.json"
export AI_USAGE_SELECTED="$TMP/selected"
export AI_USAGE_CURSOR_OAUTH_CONF="$TMP/cursor-oauth"

"$BIN" probe cursor --fixture "$FIXTURE"

mode="$(stat -c '%a' "$AI_USAGE_CACHE")"
if [[ "$mode" != "600" ]]; then
  echo "FAIL: cache mode $mode want 600" >&2
  exit 1
fi

json="$("$BIN" waybar)"
echo "$json"

echo "$json" | jq -e '.text and .tooltip and .class and .alt' >/dev/null

text="$(echo "$json" | jq -r .text)"
tooltip="$(echo "$json" | jq -r .tooltip)"
class="$(echo "$json" | jq -r .class)"

if [[ "$text" == *$'\n'* ]]; then
  echo "FAIL: expected one-line text, got: $text" >&2
  exit 1
fi
if [[ "$text" != *bgcolor* ]]; then
  echo "FAIL: expected pango bgcolor meters, got: $text" >&2
  exit 1
fi
if [[ "$text" != *R* ]]; then
  echo "FAIL: expected cursor logo R in text: $text" >&2
  exit 1
fi
if [[ "$text" == *▓* || "$text" == *░* ]]; then
  echo "FAIL: block-grid glyphs still in text: $text" >&2
  exit 1
fi
if [[ -z "$tooltip" ]]; then
  echo "FAIL: empty tooltip" >&2
  exit 1
fi
if [[ "$tooltip" != *Cursor* ]]; then
  echo "FAIL: tooltip missing Cursor name: $tooltip" >&2
  exit 1
fi
if [[ "$class" != *ok* ]]; then
  echo "FAIL: class '$class' does not include ok" >&2
  exit 1
fi
if [[ "$class" != *cursor* && "$class" != ok ]]; then
  : # class is status only, not provider id; no extra requirement
fi

# On-demand fixture should expose a credits window in the tooltip.
export AI_USAGE_CACHE="$TMP/status-ondemand.json"
export AI_USAGE_SELECTED="$TMP/selected-ondemand"
"$BIN" probe cursor --fixture "$ONDEMAND"
ondemand_json="$("$BIN" waybar)"
echo "$ondemand_json"
ondemand_tooltip="$(echo "$ondemand_json" | jq -r .tooltip)"
if [[ "$ondemand_tooltip" != *On-demand* ]]; then
  echo "FAIL: on-demand tooltip missing credits window: $ondemand_tooltip" >&2
  exit 1
fi
if [[ "$ondemand_tooltip" != *\$* ]]; then
  echo "FAIL: on-demand tooltip missing dollar amount: $ondemand_tooltip" >&2
  exit 1
fi

echo "CURSOR_FIXTURE_OK"

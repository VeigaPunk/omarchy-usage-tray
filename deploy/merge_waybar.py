#!/usr/bin/env python3
"""Merge custom/ai-usage into a Waybar JSONC config. Comments are preserved only
as a rewritten JSON file (JSONC comments are stripped)."""
from __future__ import annotations

import json
import re
import sys
from pathlib import Path


def strip_jsonc(text: str) -> str:
    out: list[str] = []
    i = 0
    n = len(text)
    in_str = False
    escape = False
    while i < n:
        ch = text[i]
        nxt = text[i + 1] if i + 1 < n else ""
        if in_str:
            out.append(ch)
            if escape:
                escape = False
            elif ch == "\\":
                escape = True
            elif ch == '"':
                in_str = False
            i += 1
            continue
        if ch == '"':
            in_str = True
            out.append(ch)
            i += 1
            continue
        if ch == "/" and nxt == "/":
            while i < n and text[i] not in "\n":
                i += 1
            continue
        if ch == "/" and nxt == "*":
            i += 2
            while i < n - 1 and not (text[i] == "*" and text[i + 1] == "/"):
                i += 1
            i = min(n, i + 2)
            continue
        out.append(ch)
        i += 1
    stripped = "".join(out)
    stripped = re.sub(r",(\s*[}\]])", r"\1", stripped)
    return stripped


def load_jsonc(path: Path) -> dict:
    raw = path.read_text(encoding="utf-8")
    try:
        data = json.loads(raw)
    except json.JSONDecodeError:
        data = json.loads(strip_jsonc(raw))
    if not isinstance(data, dict):
        raise SystemExit(f"{path}: expected JSON object")
    return data


def pick_signal(data: dict, raw: str) -> int:
    """Signal for custom/ai-usage.

    Reuse the module's current slot so re-installs do not churn the number the
    CLI pokes; otherwise take the first free one from 11.
    """
    current = data.get("custom/ai-usage")
    if isinstance(current, dict):
        sig = current.get("signal")
        if isinstance(sig, int) and not isinstance(sig, bool) and 11 <= sig < 31:
            return sig
    taken = {int(x) for x in re.findall(r'"signal"\s*:\s*(\d+)', raw)}
    sig = 11
    while sig in taken and sig < 31:
        sig += 1
    return sig


def main() -> int:
    cfg_path = Path(sys.argv[1])
    css_path = Path(sys.argv[2])
    css_src = Path(sys.argv[3])
    bin_path = sys.argv[4]
    raw = cfg_path.read_text(encoding="utf-8")
    data = load_jsonc(cfg_path)
    mods = data.get("modules-right")
    if not isinstance(mods, list):
        raise SystemExit("modules-right missing")
    if "custom/ai-usage" not in mods:
        if "bluetooth" in mods:
            mods.insert(mods.index("bluetooth"), "custom/ai-usage")
        elif "group/tray-expander" in mods:
            mods.insert(mods.index("group/tray-expander") + 1, "custom/ai-usage")
        else:
            mods.append("custom/ai-usage")
    sig = pick_signal(data, raw)
    data["custom/ai-usage"] = {
        "exec": f"{bin_path} waybar",
        "return-type": "json",
        "interval": 60,
        "signal": sig,
        "tooltip": True,
        "escape": False,
        "exec-on-event": False,
        "format": "{}",
        # cycle/identity poke Waybar themselves: `pkill -RTMIN+N` is not a
        # signal procps-ng accepts, so the shell form never refreshed the chip.
        "on-scroll-up": f"{bin_path} cycle next",
        "on-scroll-down": f"{bin_path} cycle prev",
        "on-click": f"{bin_path} cycle next",
        "on-click-right": f"{bin_path} identity next",
    }
    cfg_path.write_text(json.dumps(data, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    snippet = css_src.read_text(encoding="utf-8").strip()
    existing = css_path.read_text(encoding="utf-8") if css_path.exists() else ""
    pat = re.compile(
        r"(?:\n*/\*[^*]*custom-ai-usage[^*]*\*/\s*)?#custom-ai-usage\b.*?\{[^}]*\}(?:\s*#custom-ai-usage[^{]*\{[^}]*\})*",
        re.S,
    )
    if "#custom-ai-usage" in existing:
        existing = pat.sub("\n\n" + snippet, existing, count=1)
        if "#custom-ai-usage" not in existing:
            existing = existing.rstrip() + "\n\n" + snippet + "\n"
        css_path.write_text(existing.rstrip() + "\n", encoding="utf-8")
    else:
        css_path.write_text(existing.rstrip() + "\n\n" + snippet + "\n", encoding="utf-8")
    print(f"merged custom/ai-usage (signal {sig}) into {cfg_path}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

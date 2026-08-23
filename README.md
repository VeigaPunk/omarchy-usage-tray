# omarchy-usage-tray

Waybar chip for Omarchy: Codex, Grok, Kimi, and Alibaba Token Plan usage.
Click or scroll to cycle providers.

## Install

```bash
curl -fsSL https://raw.githubusercontent.com/VeigaPunk/omarchy-usage-tray/main/install.sh | bash
```

Re-run the same line to update.

## What it does

- Writes into `~/.config/waybar/` (backs up first). Never touches `~/.local/share/omarchy/`.
- Symlinks `~/.local/bin/ai-usage`
- Enables a user systemd timer (5 minutes)
- Floats the TUI on Hyprland like other Omarchy TUIs

## Clicks

| Gesture | Action |
|---|---|
| Click | Next provider |
| Scroll | Cycle providers |

## Local clone

```bash
git clone https://github.com/VeigaPunk/omarchy-usage-tray.git
cd omarchy-usage-tray
./install.sh
```

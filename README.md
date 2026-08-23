# omarchy-usage-tray

Waybar chip for Omarchy: Codex, Grok, Kimi, and Alibaba Token Plan usage.
Left-click cycles providers. Right-click opens a small TUI. Scroll cycles too.

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
| Left-click | Next provider |
| Right-click | Usage TUI |
| Scroll | Cycle providers |

## Local clone

```bash
git clone https://github.com/VeigaPunk/omarchy-usage-tray.git
cd omarchy-usage-tray
./install.sh
```

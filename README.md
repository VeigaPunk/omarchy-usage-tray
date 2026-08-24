# omarchy-usage-tray

Waybar chip for Omarchy: Codex, Grok, Kimi, Cursor, and Alibaba Token Plan usage.
Left-click or scroll to cycle providers; right-click cycles identities for the
selected provider when supported.

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
| Right-click | Next identity (Token Plan: `team` / `gmail`) |
| Scroll | Cycle providers |

Token Plan right-click runs `token-plan-swap toggle`. That helper flips
`~/.config/alibaba-token-plan/active` and rewrites `~/.bailian/config.json`
from the matching local key file (`keys/team` or `keys/gmail`). Codex, xask,
and `token-plan-key` all read that slot. 1Password is only used by
`token-plan-swap pull`.

OAuth multi-account (not used on this host) is documented in
[`docs/identity-swap.md`](docs/identity-swap.md). Right-click is a no-op
until a provider has two live stores.

## Local clone

```bash
git clone https://github.com/VeigaPunk/omarchy-usage-tray.git
cd omarchy-usage-tray
./install.sh
```

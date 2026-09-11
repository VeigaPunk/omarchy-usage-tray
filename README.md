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
- Reads Alibaba Token Plan quota through `omp usage --provider alibaba-token-plan --json`
- Floats the TUI on Hyprland like other Omarchy TUIs

## Clicks

| Gesture | Action |
|---|---|
| Left-click | Next provider |
| Right-click | Next identity / active route (Token Plan slots; Cursor parked OAuth) |
| Scroll | Cycle providers |

Token Plan's compact bars show the average utilization across OMP-metered
credentials and the hottest reported snapshot. The tooltip lists anonymous
snapshot values because OMP does not expose a stable report-to-slot identity.
`T @<slot>` is the active execution route, not the owner of either meter.

Token Plan right-click runs `token-plan-swap toggle`. That helper cycles the
slots in `~/.config/alibaba-token-plan/slots` and rewrites
`~/.bailian/config.json` from `keys/$active`. Codex, xask, and
`token-plan-key` follow that route. The route change preserves OMP's fleet
meters; 1Password is only used by `token-plan-swap pull`.

Cursor dual-OAuth uses `cursor-oauth-swap` (same Token Plan shape). Codex /
Grok / Kimi stay no-ops until a second store exists. See
[`docs/identity-swap.md`](docs/identity-swap.md).

## Local clone

```bash
git clone https://github.com/VeigaPunk/omarchy-usage-tray.git
cd omarchy-usage-tray
./install.sh
```

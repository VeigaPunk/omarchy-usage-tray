# omarchy-usage-tray

Waybar chip for Omarchy: Codex, Token Plan, Grok, Kimi, Cursor, Devin, and
OpenCode Go usage. Left-click or scroll to cycle providers; right-click cycles
identities for the selected provider when supported.

Current release: **1.0.0** (`ai-usage --version`).

## Providers

Every provider below is metered on every probe, from the source listed, and the
chip renders whichever one is selected.

| Logo | Provider | Windows the chip shows | Source |
|---|---|---|---|
| `C` | Codex | Weekly, plus Spark when the account reports it | `codex` app-server JSON-RPC |
| `T` | Token Plan | Per-account credits across the fleet, hottest account, add-on packs | `omp usage --provider alibaba-token-plan --json` |
| `G` | Grok | Weekly | `grok` CLI billing RPC |
| `K` | Kimi | Weekly, 5-hour | Kimi `/usages` |
| `R` | Cursor | Weekly, Auto, on-demand balance when reported | `cursor.com` usage + parked OAuth sessions |
| `D` | Devin | Weekly quota, plan cycle | CLI `GetUserStatus` session |
| `O` | OpenCode Go | Rolling 5-hour, weekly, monthly, per key | `omp usage --provider opencode-go --json` |

Missing data is never invented: a window the provider did not answer renders as
`—`, and a provider that cannot be reached keeps its last good meters and shows
the bounded reason instead.

### Token Plan add-on credits

Token Plan meters the weekly plan window and purchased add-on bundles (Credit
Pack, $15) as separate pools. The chip supports both: when a report carries a
`credits:addon` window, that account's row is `weekly + packs`, the tooltip
prints `x/y credits` per snapshot, and an account whose plan reads 100% while a
pack still holds credits shows its real headroom instead of a false zero.

Pool sizes are declared rather than scraped — the console usage RPC answers
percentages only (verified 2026-09-20 on every stored credential) — so override
them per tier with `AI_USAGE_TOKEN_PLAN_WEEKLY_CREDITS` and
`AI_USAGE_TOKEN_PLAN_ADDON_CREDITS` (both **per account**). OMP emits only the
7-day window today, so the add-on path stays dormant until it reports one.

## Install

```bash
curl -fsSL https://raw.githubusercontent.com/VeigaPunk/omarchy-usage-tray/main/install.sh | bash
```

Re-run the same line to update.

## What it does

- Writes into `~/.config/waybar/` (backs up first). Never touches `~/.local/share/omarchy/`.
- Symlinks `~/.local/bin/ai-usage` and points the Waybar module at that symlink
  (not at the checkout), so the chip survives moving the repo
- Enables a user systemd timer (5 minutes); machine-local probe knobs live in
  `~/.config/ai-usage/env`, which the installer never overwrites
- Reads each provider from the source listed under [Providers](#providers)
- Floats the TUI on Hyprland like other Omarchy TUIs

## Clicks

| Gesture | Action |
|---|---|
| Left-click | Next provider |
| Right-click | Next identity / active route (Token Plan slots; Cursor parked OAuth) |
| Scroll | Cycle providers |

Click and scroll change the chip immediately: `cycle` / `identity` signal
Waybar themselves. The 60s interval is only a safety net, so the chart can
never sit on a stale provider.

Multi-account providers report one snapshot per stored credential. The chip
shows an `N-account` average followed by the hottest account, and the tooltip
lists every snapshot with its binding window, fetch age, and reset. OMP exposes
no stable account identity, so rows stay anonymous by design.

OpenCode Go meters three windows per key: rolling 5-hour, weekly, and monthly.
Monthly anchors on the subscription anniversary, so a key can sit at its
monthly cap while the weekly window still reads empty — the hottest-account
slot tracks whichever window is closest to its limit, and the chip turns red
past 95%. `O` is the logo; right-click there is a no-op because OMP already
rotates those keys per request.

Token Plan's compact bars show the average utilization across OMP-metered
credentials and the hottest reported snapshot, followed by remaining/total
credits. `T @<slot>` is the active execution route, not the owner of either
meter. See [Token Plan add-on credits](#token-plan-add-on-credits) for the
credit model.

Token Plan right-click runs `token-plan-swap toggle`. That helper cycles the
slots in `~/.config/alibaba-token-plan/slots` and rewrites
`~/.bailian/config.json` from `keys/$active`. Codex, xask, and
`token-plan-key` follow that route. The route change preserves OMP's fleet
meters; 1Password is only used by `token-plan-swap pull`.

Cursor dual-OAuth uses `cursor-oauth-swap` (same Token Plan shape). Codex /
Grok / Kimi / OpenCode Go stay no-ops until a second store exists — OpenCode Go
keys rotate inside OMP, so there is no live file for the chip to flip. See
[`docs/identity-swap.md`](docs/identity-swap.md).

## Configuration

`~/.config/ai-usage/env` (created on first install, never overwritten) is the
service environment for the 5-minute probe:

```ini
#AI_USAGE_OMP_BIN=/home/you/.local/bin/omp
#AI_USAGE_TOKEN_PLAN_WEEKLY_CREDITS=40000
#AI_USAGE_TOKEN_PLAN_ADDON_CREDITS=20000
```

Values are literal — systemd expands nothing inside the file. The same
`AI_USAGE_*` variables work when set in your shell for one-off runs.

## Local clone

```bash
git clone https://github.com/VeigaPunk/omarchy-usage-tray.git
cd omarchy-usage-tray
./install.sh
```

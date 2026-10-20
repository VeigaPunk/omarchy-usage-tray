# omarchy-usage-tray

Waybar chip for Omarchy: Codex, Token Plan, Grok, Kimi, Cursor, Devin (both
accounts), OpenCode Go, Charm Hyper, Z.ai, Google, Anthropic, and Command Code
usage.
Left-click or scroll to cycle providers; right-click cycles identities for the
selected provider when supported.

Current release: **1.9.0** (`ai-usage --version`).

Every usage meter comes from `omp usage --provider <id> --json` — the native
CLIs (codex, grok, cursor-agent, devin) are not required, because OMP meters
those same subscriptions from its auth store. The chip only scopes to authed,
metered providers (status ok, a numeric window, or a credit balance — see
`_provider_usable`): a provider that cannot show a real number drops out of
the cycle instead of rendering an invented zero.

**Wiki:** [Devin wiki](https://app.devin.ai/org/veigapunk/wiki/VeigaPunk/omarchy-usage-tray?branch=main)

## Providers

Every provider below is metered on every probe, from `omp usage --json`, and
the chip renders whichever one is selected.

| Logo | Provider | Windows the chip shows | Source |
|---|---|---|---|
| `C` | Codex | Weekly 7-day, hottest account | `omp usage --provider openai-codex --json` |
| `T` | Token Plan | Per-account credits across the fleet, hottest account, add-on packs | `omp usage --provider alibaba-token-plan --json` |
| `G` | Grok | Weekly credits, hottest account | `omp usage --provider xai-oauth --json` |
| `K` | Kimi | Monthly total, 5-hour, monthly code — per OAuth account, averaged + hottest | `omp usage --provider kimi-code --json` |
| `R` | Cursor | Monthly models + other models, hottest | `omp usage --provider cursor --json` |
| `D` | Devin | Weekly quota, hottest account | `omp usage --provider devin --json` |
| `d` | Devin 2 | Weekly quota, second account | `omp usage --provider devin --json` (second report row) |
| `O` | OpenCode Go | Rolling 5-hour, weekly, monthly, per key | `omp usage --provider opencode-go --json` |
| `H` | Charm Hyper | Prepaid credit balance, summed over every credential | `omp usage --provider charm-hyper --json` |
| `Z` | Z.ai | 5-hour, weekly, hottest account | `omp usage --provider zai --json` |
| `g` | Google | Gemini weekly + 5-hour, shared Claude & GPT pools, hottest account | `omp usage --provider google-antigravity --json` |
| `A` | Anthropic | Weekly 7-day, 5-hour, per-model weekly caps (e.g. Fable), hottest account | `omp usage --provider anthropic --json` |
| `⌘` | Command Code | Weekly + 5-hour credit windows, hottest account, credit balance across accounts | `omp usage --provider commandcode --json` |

Missing data is never invented: a window the provider did not answer renders as
`—`, and a provider that cannot be reached keeps its last good meters and shows
the bounded reason instead.

### Token Plan console authentication

Token Plan API keys can serve model requests without exposing quota data.
Each stored OMP credential also needs the matching account's QwenCloud or
Bailian console Cookie header for usage reporting. See OMP's
[Token Plan login guidance](https://github.com/can1357/oh-my-pi/blob/main/packages/ai/README.md).
Cookies are sensitive and session-lived: keep them in OMP's credential store,
never in the provider roster, service environment, usage cache, or repository.
Reconnect the corresponding console session when it expires.

For multiple keys, check that `omp usage --provider alibaba-token-plan --json`
returns one report per account, then run `ai-usage probe token-plan`. A working
key listed under `accountsWithoutUsage` has no quota report; it is not a zero
usage reading.

### Token Plan add-on credits

Token Plan meters the monthly plan window and purchased add-on bundles (Credit
Pack, $15) as separate pools. The chip supports both: when a report carries a
`credits:addon` window, that account's row is `monthly + packs`, the tooltip
prints `x/y credits` per snapshot, and an account whose plan reads 100% while a
pack still holds credits shows its real headroom instead of a false zero.

Pool sizes are declared rather than scraped — the console usage RPC answers
percentages only — so override them per tier with
`AI_USAGE_TOKEN_PLAN_MONTHLY_CREDITS` (legacy
`AI_USAGE_TOKEN_PLAN_WEEKLY_CREDITS` still honored) and
`AI_USAGE_TOKEN_PLAN_ADDON_CREDITS` (both **per account**). OMP emits only the
monthly window today, so the add-on path stays dormant until it reports one.

The default monthly pool is **45,000 credits per account (Standard)**. Pro
grants **180,000 per account**: set
`AI_USAGE_TOKEN_PLAN_MONTHLY_CREDITS=180000` in `~/.config/ai-usage/env` for a
Pro-only pool. Three Pro accounts therefore total 540,000 monthly credits.
For an immediate one-off refresh, pass the same variable to
`ai-usage probe token-plan`; the environment file is loaded by the timer,
not by interactive shell commands.

### Charm Hyper credits

Charm Hyper is prepaid, and OMP answers with a balance rather than a
percentage: the endpoint reports how many credits are left and there is no
window to fill. The chip therefore renders a counter (`H 238cr`) and no bar.
Balances from every stored credential are added up; if one credential answers
nothing, the total is withheld instead of understated, and the chip keeps the
last good count alongside the bounded reason. A retained count is labelled
`last good` in the tooltip.

`AI_USAGE_CHARM_HYPER_LOW_CREDITS` (in credits, compared against the reported
total) turns the chip red below a floor; zero credits is always critical. Left
unset, only an exhausted balance alarms.

### Google shared pools

The Google Antigravity account carries four quota pools: Gemini weekly, Gemini
rolling 5-hour, and the shared third-party pools (Claude & GPT) on the same
two windows. OMP reports each shared pool once per backing model under one
`sharedGroup`, so the chip dedupes them and keeps the highest reading — one
quota, never a sum. The compact bars show the Gemini weekly average and the
hottest account; the tooltip shows the four pool averages and each account's
binding pool. `g` is the logo; right-click is a no-op because the credential
lives in OMP's auth store with no local file to flip.

### Anthropic model caps

The Claude subscription carries two shared, account-wide walls — a rolling
5-hour window and the weekly window — plus one weekly cap per model family
(Fable, Opus, Sonnet, …). A cap is not a slice of the wall: it reads and blocks
only its own model family, but an exhausted cap still counts toward the
hottest-account slot, so the chip warns while the shared walls read idle. The
compact bars show the shared weekly average and the hottest account; the
tooltip adds the shared 5-hour average and one row per model cap. Pay-as-you-go
Extra Usage is reported in dollars, not a rate window, so it is not metered.
`A` is the logo; right-click is a no-op because the credential lives in OMP's
auth store with no local file to flip.

### Command Code credits

Command Code meters each API-key credential with a rolling 5-hour and a weekly
credit window, reported as a share of the plan cap (GOAT: 14 and 35 credits for
the 5-hour and weekly windows), plus the credit balance — monthly + purchased +
free credits, a counter with no ceiling and no reported reset time. The chip
renders the `⌘` logo, a weekly-average bar, a hottest-account bar, and the
summed balance as a counter (`⌘ ▭ ▭ 140cr`). The balance is summed once per
credit pool: credentials in the same org share one pool and count once. If any
credential answers no balance the total is withheld instead of understated —
the chip drops the counter, the tooltip shows `—`, and the reason reads
`partial_usage`. An account at zero balance turns the chip red even while its
windows read idle, because it is blocked. The tooltip shows the weekly and
5-hour averages, the hottest account, a `Credit balance … credits left` line,
and one numbered row per account with its binding window and balance.
Pay-as-you-go accounts report only the balance. `⌘` is the logo; right-click
is a no-op because the credentials live in OMP's auth store.

## Install

Quattro bar:

```bash
omarchy plugin add https://github.com/VeigaPunk/omarchy-usage-tray.git --enable
```

The plugin refreshes its own meters: its service runs `ai-usage refresh` when
the shell loads it and every 5 minutes after, writing the cache the chip
renders, so a Quattro install needs no installer and no systemd timer. `omp`
must be on `PATH` and signed in to the providers you want metered.

Waybar on this machine. The installer edits `~/.config/waybar/` only after you run it, and it backs up the files first. It does not write under `~/.local/share/omarchy`.

```bash
git clone https://github.com/VeigaPunk/omarchy-usage-tray.git
cd omarchy-usage-tray
./install.sh
```

Re-run `./install.sh` from the checkout to update.

Dependencies: Python 3, `omp` on `PATH` for the meters, and either the Omarchy Quattro shell or Waybar. The Waybar install's refresh timer is a systemd user unit; Quattro needs none. No sudo.

## Remove

```bash
./uninstall.sh
omarchy plugin remove io.github.veigapunk.usage-tray
```

`./uninstall.sh` stops `ai-usage.timer`, deletes the user units, and drops the `custom/ai-usage` Waybar module and Hyprland rule. It leaves `~/.config/ai-usage/env` alone. Delete the `#custom-ai-usage` rules in `~/.config/waybar/style.css` if you still want them gone. `omarchy plugin remove` disables the Quattro widget and its refresh service before deleting the checkout; the cache in `~/.cache/ai-usage/` stays until you delete it.

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
| Right-click | Next identity / active route (Token Plan slots) |
| Scroll | Cycle providers |

Click and scroll change the chip immediately: `cycle` / `identity` signal
Waybar themselves. The 60s interval is only a safety net, so the chart can
never sit on a stale provider.

Multi-account providers report one snapshot per stored credential. The chip
shows an average followed by the hottest account. Hover for aligned visual
meters, whole percentages, and short reset countdowns (`2d 14h`, `45m`).
Multi-account rows focus on each snapshot's binding window; fetch ages appear
only when stale, and missing/disabled credentials remain explicit. The account
count appears once in the header unless a window has fewer reports. OMP exposes
no stable account identity, so rows stay anonymous by design.

OpenCode Go meters three windows per key: rolling 5-hour, weekly, and monthly.
Monthly anchors on the subscription anniversary, so a key can sit at its
monthly cap while the weekly window still reads empty — the hottest-account
slot tracks whichever window is closest to its limit. A red underline warns
at 95% without dimming the label. New OMP keys are included automatically on
the next probe; run `ai-usage probe opencode-go` to refresh immediately.
`O` is the logo; right-click there is a no-op because OMP already rotates
those keys per request.

Token Plan's compact bars show the average utilization across OMP-metered
credentials and the hottest reported snapshot, followed by a rounded remaining
balance (`24k left`). The tooltip retains the remaining/total credits and the
per-account breakdown. `T @<slot>` is the active execution route, not the owner
of either meter. See [Token Plan add-on credits](#token-plan-add-on-credits) for
the credit model.

Token Plan right-click runs `token-plan-swap toggle`. That helper cycles the
slots in `~/.config/alibaba-token-plan/slots` and rewrites
`~/.bailian/config.json` from `keys/$active`. Codex, xask, and
`token-plan-key` follow that route. The route change preserves OMP's fleet
meters; 1Password is only used by `token-plan-swap pull`.

Kimi runs both OAuth accounts through `omp auth-gateway` (127.0.0.1:8791): the
gateway round-robins new sessions across the stored `kimi-code` credentials and
retries on the other account after a usage-limit block, so the chip meters the
fleet and right-click just reports the balanced state. Cursor / Codex / Grok /
OpenCode Go / Charm Hyper / Z.ai / Google / Anthropic / Command Code stay
no-ops — OpenCode Go keys rotate inside OMP, and Charm Hyper's, Cursor's,
Google's, Anthropic's, and Command Code's credentials live in OMP's auth
store, so none has a live file for the chip to flip.

## Configuration

`~/.config/ai-usage/env` (created on first install, never overwritten) is the
service environment for the 5-minute probe:

```ini
#AI_USAGE_OMP_BIN=/home/you/.local/bin/omp
#AI_USAGE_TOKEN_PLAN_MONTHLY_CREDITS=45000
#AI_USAGE_TOKEN_PLAN_ADDON_CREDITS=20000
#AI_USAGE_CHARM_HYPER_LOW_CREDITS=25
```

Values are literal — systemd expands nothing inside the file. The same
`AI_USAGE_*` variables work when set in your shell for one-off runs.

### Provider roster

By default every provider above is probed and cycled. An installation can opt in
to a subset — the models actually authed on that machine — so the probe skips
subscriptions nobody uses and the chip cycles only through providers that can
show a number.

`AI_USAGE_PROVIDERS` takes a comma and/or whitespace separated id list
(`AI_USAGE_PROVIDERS="codex kimi"`) and wins when set, so a shell can narrow a
one-off run; it also works from `~/.config/ai-usage/env` to scope the timer.
Otherwise the roster comes from `~/.config/ai-usage/providers`, one id per line,
with `#` comments and blank lines skipped:

```
# authed on this machine
codex
kimi
zai
```

`AI_USAGE_PROVIDERS_FILE` overrides that path (the tests point it at a temp
file). With neither source set — or with a roster that names no known provider —
all 13 providers stay active, so the default behaviour is unchanged. An unknown
id prints one warning line to stderr (`ai-usage: unknown provider in roster:
<id>`, once per run) and is skipped; it never fails a probe.

The roster scopes the defaults: `probe` / `refresh` with no id, the click and
scroll cycle, the TUI chip row and its number keys, and the provider the chip
falls back to when the selected one has no usable record. Nothing named
explicitly is restricted — `ai-usage probe zai` and `ai-usage select zai` both
work while `zai` is off the roster, and the chip renders that selection as soon
as a record for it exists.

To add a provider you have just authed, add a line to
`~/.config/ai-usage/providers`. The systemd timer picks it up on its next run
(5 minutes), or run `ai-usage probe` to fetch it immediately.

## Local clone

```bash
git clone https://github.com/VeigaPunk/omarchy-usage-tray.git
cd omarchy-usage-tray
./install.sh
```

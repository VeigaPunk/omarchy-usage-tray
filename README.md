# omarchy-usage-tray

Waybar chip for Omarchy: Codex, OpenCode Go, MiniMax, Google, Anthropic,
Command Code, Mistral, and OpenDesign usage.
Left-click or scroll to cycle providers; right-click is a no-op.

Current release: **1.15.0** (`ai-usage --version`).

Every usage meter except Mistral's and OpenDesign's comes from
`omp usage --provider <id> --json` — the native CLIs (such as codex) are not
required, because OMP meters those same subscriptions from its auth store.
Mistral has no usage API, so its meter is a ledger of what OMP spent (see
[Mistral spend](#mistral-spend)).
OpenDesign's API keys cannot read their quota, so the chip signs in to each
OpenDesign account with the official `vela` CLI and reads the Coding Plan from
the account API (see [OpenDesign Coding Plan](#opendesign-coding-plan)).
The chip only scopes to authed, metered providers (status ok, a numeric window,
or a credit balance — see `_provider_usable`): a provider that cannot show a
real number drops out of the cycle instead of rendering an invented zero.

**Wiki:** [Devin wiki](https://app.devin.ai/org/veigapunk/wiki/VeigaPunk/omarchy-usage-tray?branch=main)

## Providers

Every provider below is metered on every probe, from `omp usage --json` (or,
for Mistral, OMP's transcripts, and for OpenDesign, its account API), and the chip renders whichever one is selected.

| Logo | Provider | Windows the chip shows | Source |
|---|---|---|---|
| `C` | Codex | Weekly 7-day, hottest account | `omp usage --provider openai-codex --json` |
| `O` | OpenCode Go | Rolling 5-hour, weekly, monthly, per key | `omp usage --provider opencode-go --json` |
| `M` | MiniMax | 7-day, 5-hour, hottest account | `omp usage --provider minimax-code --json` |
| `g` | Google | Gemini weekly + 5-hour, shared Claude & GPT pools, hottest account | `omp usage --provider google-antigravity --json` |
| `A` | Anthropic | One meter per account, filled to its binding window: 5-hour, weekly 7-day, or a per-model weekly cap (e.g. Fable) | `omp usage --provider anthropic --json` |
| `⌘` | Command Code | Weekly + 5-hour credit windows, hottest account, credit balance across accounts | `omp usage --provider commandcode --json` |
| `ⓜ` | Mistral | Month-to-date spend (USD, OMP catalog prices); optional monthly budget meter, full when the key OMP uses is exhausted | OMP session transcripts + `models.yml` / auth store (no usage API); key verdicts from `omp-mistral-key --check` |
| `◇` | OpenDesign | One meter per account, filled to its binding Coding Plan window (5-hour or weekly credits); wallet balance | `ai-usage login amr` (`vela login`) + `amr-api.open-design.ai` billing preflight |

Missing data is never invented: a window the provider did not answer renders as
`—`, and a provider that cannot be reached keeps its last good meters and shows
the bounded reason instead.

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
only its own model family, but an exhausted cap still binds its account's
meter, so the chip warns while the shared walls read idle. The chip shows one
meter per Claude account, left to right in OMP's credential order, each filled
to the window that binds that account: an exhausted account next to an idle one
reads as a full bar and an empty bar, not a half-full average. An account OMP
lists without usage stays on the chip as `—`. The tooltip keeps the shared
weekly and 5-hour averages, one row per model cap, the hottest account, and
numbered account rows that match the meters left to right. Pay-as-you-go
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

### Mistral spend

Mistral API keys cannot read their own spend or limits: `/v1` has no usage or
billing route (`/v1/usage`, `/v1/billing`, … answer 404), chat responses carry
only per-minute rate-limit headers, and the console's monthly usage sits behind
a browser session. Spend is therefore a ledger of what OMP spent.

Mistral bills per calendar month, so the chip meters what OMP spent this UTC
month: the probe sums `usage.cost.total` (OMP's catalog price estimate, in USD)
and tokens of every `provider: mistral` reply in
`~/.omp/agent/sessions/**/*.jsonl`. It reads the transcripts incrementally
through `~/.cache/ai-usage/mistral-ledger.json`, which stores each file's read
offset so only appended or replaced transcripts are read, and counts each reply
once by response id. A reply read from a transcript that OMP later deletes or
garbage-collects stays counted until its UTC month ends, so pruning sessions
does not lower the month's spend. Spend forgotten that way before 1.15.0 cannot
be recovered. The probe checks that a key is wired into OMP (`MISTRAL_API_KEY`,
a `providers.mistral.apiKey` entry in `models.yml`, or a stored `mistral`
credential) without reading the key. Override the OMP directory with
`AI_USAGE_OMP_AGENT_DIR`.

The chip renders `ⓜ $1.50`: spend so far this month. Set
`AI_USAGE_MISTRAL_MONTHLY_BUDGET` to your workspace's monthly spend limit (USD;
e.g. `165` for a $165/month limit) to add a meter against it, e.g.
`ⓜ ▬ $1.50`, with `$1.50 of $165 · resets in …` in the tooltip. The limit
resets with each calendar month. The tooltip lists the month's totals (spend,
tokens, replies, today's spend) and spend per model, costliest first.

The only authoritative sign of a spent budget is Mistral refusing requests: an
exhausted key answers chat requests with HTTP 402
`billing_vibe_budget_exhausted` ("Vibe budget exhausted.") while
`GET /v1/models` still answers 200, which is why a key check based on
`/v1/models` alone reported the key as valid. The host's key resolver,
`omp-mistral-key` (optional; `~/.local/bin/omp-mistral-key`, overridable with
`AI_USAGE_MISTRAL_KEY_RESOLVER`), runs as `omp-mistral-key --check` on each
probe and records one verdict per key in
`$XDG_STATE_HOME/omp-mistral-key/status.json` (default
`~/.local/state/omp-mistral-key/status.json`): `valid`, `exhausted` (402),
`rejected` (401/403), `unverified`, `unreachable`, or `unchecked`, plus the
slot OMP uses — the first key Mistral does not reject, so an exhausted key can
still be the one in use. The chip reads only that record, never the keys.

When the key OMP uses is exhausted, the meter reads full and critical
regardless of the ledger figure, with or without a budget set, the reason reads
`budget_exhausted`, and the tooltip says the budget is exhausted. The tooltip
lists each key by slot, role (primary or fallback), and last four characters
with its verdict; an exhausted key reads 100%. Without the resolver or its
record the meter is the ledger alone.

Limits: requests made outside OMP are not seen, and the cost is OMP's price
estimate, not Mistral's invoice. Right-click is a no-op.

### OpenDesign Coding Plan

OpenDesign `sk-amr-` API keys have no usage endpoint
([nexu-io/open-design#8674](https://github.com/nexu-io/open-design/issues/8674)),
so `omp usage` lists them under `accountsWithoutUsage`. The quota lives on the
account instead, and the account API needs a sign-in.

Install the official CLI once with `npm install -g @powerformer/vela-cli`, then
run `ai-usage login amr` once per OpenDesign account. It runs `vela login`,
which prints a URL and a code and opens the browser; approve while signed in to
that account. Re-running it for the same account replaces that account's slot.
The meter is per account, not per key: keys created under one account share
its plan.

Each sign-in is stored as `~/.config/ai-usage/amr/<n>/config.json` (0600). The
`vela_ctrl_` control key in it can read workspace and billing data and cannot
yet be revoked from the console
([#8870](https://github.com/nexu-io/open-design/issues/8870)). Delete a slot
directory to drop that account.

The probe reads `/api/v1/workspaces` to pick the personal workspace, then
`/api/v1/workspaces/{id}/billing/preflight` for each window's used vs. limit
credits — the same numbers as the console. Go plans have 5-hour and weekly
windows; Plus, Pro and Max only weekly.

The chip shows one slot per account in slot order, e.g. `◇ ▭ ▭ $4.00 —`: a meter
for each plan account filled to its binding window, the wallet in dollars for
a wallet-only account, and `—` for an account whose sign-in expired. The
tooltip shows the weekly and 5-hour averages, the hottest account, the wallet
total, and rows numbered by slot with the tier, binding window, and wallet, or
an error such as `login expired`. If any account fails, the hottest account and
the wallet total are withheld instead of understated. When at least one account
still reports, the reason reads `partial_usage`.

The meters refresh with the 5-minute probe. Override the slot directory with
`AI_USAGE_AMR_DIR`, the `vela` binary with `AI_USAGE_VELA_BIN`, and the API
base URL with `AI_USAGE_AMR_API_URL`. Right-click is a no-op.

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

Dependencies: Python 3, `omp` on `PATH` for the meters, and either the Omarchy Quattro shell or Waybar. `vela` is needed only to sign in to OpenDesign. The Waybar install's refresh timer is a systemd user unit; Quattro needs none. No sudo.

## Remove

```bash
./uninstall.sh
omarchy plugin remove io.github.veigapunk.usage-tray
```

`./uninstall.sh` stops `ai-usage.timer`, deletes the user units, and drops the `custom/ai-usage` Waybar module and Hyprland rule. It leaves `~/.config/ai-usage/env` and the OpenDesign sign-ins in `~/.config/ai-usage/amr` alone; delete that directory to remove them. Delete the `#custom-ai-usage` rules in `~/.config/waybar/style.css` if you still want them gone. `omarchy plugin remove` disables the Quattro widget and its refresh service before deleting the checkout; the cache in `~/.cache/ai-usage/` stays until you delete it.

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
| Right-click | No-op |
| Scroll | Cycle providers |

Click and scroll change the chip immediately: `cycle` signals Waybar
itself. The 60s interval is only a safety net, so the chart can
never sit on a stale provider.

Multi-account providers report one snapshot per stored credential. The chip
shows an average followed by the hottest account (Anthropic and OpenDesign:
one meter per account). Hover for aligned visual meters, whole percentages,
and short reset countdowns (`2d 14h`, `45m`).
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

Right-click is a no-op for every provider: OMP owns the credentials (and
rotates OpenCode Go keys per request), and OpenDesign's sign-ins live in the
tray's own slots and are all metered at once, so there is no identity for the
chip to flip. Right-click stays wired to `ai-usage identity next`, which prints
`<provider>: no identity cycle configured`.

## Configuration

`~/.config/ai-usage/env` (created on first install, never overwritten) is the
service environment for the 5-minute probe:

```ini
#AI_USAGE_OMP_BIN=/home/you/.local/bin/omp
#AI_USAGE_MISTRAL_MONTHLY_BUDGET=165
#AI_USAGE_AMR_DIR=/home/you/.config/ai-usage/amr
```

Values are literal — systemd expands nothing inside the file. The same
`AI_USAGE_*` variables work when set in your shell for one-off runs.

### Provider roster

By default every provider above is probed and cycled. An installation can opt in
to a subset — the models actually authed on that machine — so the probe skips
subscriptions nobody uses and the chip cycles only through providers that can
show a number.

`AI_USAGE_PROVIDERS` takes a comma and/or whitespace separated id list
(`AI_USAGE_PROVIDERS="codex opencode-go"`) and wins when set, so a shell can narrow a
one-off run; it also works from `~/.config/ai-usage/env` to scope the timer.
Otherwise the roster comes from `~/.config/ai-usage/providers`, one id per line,
with `#` comments and blank lines skipped:

```
# authed on this machine
codex
opencode-go
google
```

`AI_USAGE_PROVIDERS_FILE` overrides that path (the tests point it at a temp
file). With neither source set — or with a roster that names no known provider —
all 8 providers stay active, so the default behaviour is unchanged. An unknown
id prints one warning line to stderr (`ai-usage: unknown provider in roster:
<id>`, once per run) and is skipped; it never fails a probe.

The roster scopes the defaults: `probe` / `refresh` with no id, the click and
scroll cycle, the TUI chip row and its number keys, and the provider the chip
falls back to when the selected one has no usable record. Nothing named
explicitly is restricted — `ai-usage probe google` and `ai-usage select google`
both work while `google` is off the roster, and the chip renders that selection as soon
as a record for it exists.

To add a provider you have just authed, add a line to
`~/.config/ai-usage/providers`. The systemd timer picks it up on its next run
(5 minutes), or run `ai-usage probe` to fetch it immediately.
An existing `~/.config/ai-usage/providers` must list `amr` for the chip to
cycle to OpenDesign.

## Local clone

```bash
git clone https://github.com/VeigaPunk/omarchy-usage-tray.git
cd omarchy-usage-tray
./install.sh
```

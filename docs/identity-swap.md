# Identity swap

Right-click on the Waybar chip cycles **identities inside the selected
provider**. Left-click / scroll still cycle **providers**.

## Token Plan (shipped)

- Key files (mode 0600): `~/.config/alibaba-token-plan/keys/<slot>`
- Slot metadata (names and pull references only): `~/.config/alibaba-token-plan/slots`
- Live route: `~/.config/alibaba-token-plan/active`
- Swap helper: `token-plan-swap` (`status|team|gmail|infnet|toggle|due|pull`)
- Route commands rewrite `~/.bailian/config.json` locally. No `op`, no `bl login`.
- `pull` is the only 1Password path (rotate vault keys into the local files).
- Codex / xask Token Plan calls `token-plan-key`, which reads `keys/$active`.
  They follow the toggle without a second write.

Quota metering is independent of the active route. `ai-usage` reads all
available reports through `omp usage --provider alibaba-token-plan --json`,
shows an account-average and hottest-snapshot meter, and keeps report rows
anonymous because OMP exposes no stable slot identity.

`ai-usage identity next` execs `token-plan-swap toggle`, re-reads `active`
(never the key files), preserves the OMP fleet meters, and prints the slot id.

## Cursor OAuth (shipped helper)

Same shape as Token Plan. The live file `cursor-agent` already reads is
`~/.config/cursor/auth.json` (override: `CURSOR_AUTH_FILE`).

- Slots file (names only): `~/.config/cursor-oauth/slots`
- Active pointer: `~/.config/cursor-oauth/active`
- Parked sessions: `~/.config/cursor-oauth/identities/<id>/auth.json` (0600)
- Helper: `cursor-oauth-swap` (`status|capture <id>|toggle|<id>`)

`capture` copies the live file into a slot. `toggle` harvests the live
file back into the current slot (so a refreshed JWT is not lost), then
atomic-replaces `auth.json` with the other parked file.

Park the second account yourself:

```bash
cursor-oauth-swap capture primary
cursor-agent logout
cursor-agent login
cursor-oauth-swap capture second
cursor-oauth-swap toggle
```

Right-click on the Cursor chip calls `ai-usage identity next` →
`cursor-oauth-swap toggle`. Running `cursor-agent` processes keep the old
JWT in memory until they restart.

Never put tokens in this repo or in Waybar JSON. Never `op` on click.

## OAuth / extra API keys (outline only)

Codex / Grok / Kimi still have one OAuth each on this host, so identity
cycle stays a no-op there. Do not build a swapper without a second store.

When someone else has two live identities for the **same** provider, copy
the Token Plan / Cursor shape. Do not invent a plugin framework.

1. **Inventory, names only.** Count stores. If count &lt; 2, keep the no-op.
2. **Slots file without secrets.** Same idea as `alibaba-token-plan/slots`:
   id, title, maybe an `op://` ref for *pull*. Never put tokens in the tray
   repo or in Waybar JSON.
3. **`active` pointer.** One small file the chip can read on every render.
4. **A helper that writes what the CLI actually reads.**
5. **Display from `active`.** Suffix the logo. Blank `used_pct` on switch only
   when the meter belongs to that identity; preserve provider-wide fleet meters.
6. **`pull` optional.** Vault restore of slot files. Not on the hot path.
7. **Gate.** Isolated HOME + synthetic tokens; live test is opt-in + restore.

### Where each CLI actually reads auth (this host, names only)

| Provider | Live file / env the CLI uses | Second store on this host? |
|---|---|---|
| Codex | `~/.codex/auth.json` (`auth_mode=chatgpt`) | no (`OPENAI_API_KEY` unset) |
| Grok | `~/.grok/auth.json` (OIDC) | no (`XAI_API_KEY` unset in the tray path; management prepaid is a *different* key, not a second OAuth) |
| Kimi | `~/.kimi-code/credentials/*.json` (one file) | no (`moonshotai` in config.toml is API, not a second OAuth) |
| Cursor | `~/.config/cursor/auth.json` | **yes** — `cursor-oauth-swap` parks copies under `~/.config/cursor-oauth/identities/` |
| Token Plan | `keys/$active` + `~/.bailian/config.json` | **yes** — `team` / `gmail` / `infnet` |

Never `op` on right-click. Never print tokens. Never rewrite
`~/.local/share/omarchy/`.

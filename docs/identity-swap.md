# Identity swap

Right-click on the Waybar chip cycles **identities inside the selected
provider**. Left-click / scroll still cycle **providers**.

## Token Plan (shipped)

This is the only adapter with a live swap on this host.

- Keys (mode 0600): `~/.config/alibaba-token-plan/keys/{team,gmail}`
- Live slot: `~/.config/alibaba-token-plan/active`
- Swap helper: `token-plan-swap` (`status|team|gmail|toggle|due|pull`)
- `toggle` / `team` / `gmail` / `due` rewrite `~/.bailian/config.json`
  locally. No `op`, no `bl login`.
- `pull` is the only 1Password path (rotate vault keys into the local files).
- Codex / xask Token Plan calls `token-plan-key`, which reads `keys/$active`.
  They follow the toggle without a second write.

`ai-usage identity next` execs `token-plan-swap toggle`, re-reads `active`
(never the key files), blanks Token Plan meters until the next probe, and
prints the slot id.

## OAuth / extra API keys (outline only)

This host runs **one** OAuth per provider (Codex ChatGPT, Grok OIDC, Kimi
OAuth). There is nothing to cycle, so right-click is a no-op there. Do not
build a swapper without a second store to overfit.

When someone else has two live identities for the **same** provider, copy
the Token Plan shape. Do not invent a plugin framework.

1. **Inventory, names only.** Count stores. If count &lt; 2, keep the no-op.
2. **Slots file without secrets.** Same idea as `alibaba-token-plan/slots`:
   id, title, maybe an `op://` ref for *pull*. Never put tokens in the tray
   repo or in Waybar JSON.
3. **`active` pointer.** One small file the chip can read on every render.
4. **A helper that writes what the CLI actually reads.** Token Plan’s helper
   rewrites `~/.bailian/config.json` from `keys/$id`. An OAuth helper must
   atomic-replace the **live auth file** the CLI already uses (examples
   below), then leave the previous file under `slots/$id/` or similar.
   Right-click only calls that helper.
5. **Display from `active`.** Suffix the logo (`C work`, `G home`). Blank
   that provider’s `used_pct` on switch (`reason=switched` so
   `keep_last_good` cannot resurrect the previous fill).
6. **`pull` optional.** Vault restore of slot files. Not on the hot path.
7. **Gate.** Isolated HOME + synthetic tokens; live test is opt-in + restore.
   This repo will not empirically test a second OAuth on plazir.

### Where each CLI actually reads auth (this host, names only)

| Provider | Live file / env the CLI uses | Second store on this host? |
|---|---|---|
| Codex | `~/.codex/auth.json` (`auth_mode=chatgpt`) | no (`OPENAI_API_KEY` unset) |
| Grok | `~/.grok/auth.json` (OIDC) | no (`XAI_API_KEY` unset in the tray path; management prepaid is a *different* key, not a second OAuth) |
| Kimi | `~/.kimi-code/credentials/*.json` (one file) | no (`moonshotai` in config.toml is API, not a second OAuth) |
| Token Plan | `keys/$active` + `~/.bailian/config.json` | **yes** — `team` / `gmail` |

A future Codex dual-OAuth would likely be: keep `auth.json` as the live slot
and `~/.codex/identities/{id}/auth.json` as the store; helper copies the
chosen file into `auth.json` (mode 0600) and writes `active`. Same for Grok
(`~/.grok/auth.json`) and Kimi (the credentials json the CLI lists).

Never `op` on right-click. Never print tokens. Never rewrite
`~/.local/share/omarchy/`.

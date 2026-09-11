# Plan — Devin usage provider for ai-usage + ship repo upstream

**Session:** 0 | **Dispatched by:** ufo | **Date:** 2026-09-11

## Phase 0 — State map

### Exists
- `bin/ai-usage` (3018 lines, single file, Python 3.14, `tomllib` already imported at line 24).
- `PROVIDERS` tuple at line 41: `("codex","Codex","C")`, `("token-plan","Token Plan","T")`, `("grok","Grok","G")`, `("kimi","Kimi","K")`, `("cursor","Cursor","R")`. `PROVIDER_INDEX` derived at line 48.
- `PROBERS` dict at line 2525; `probe_one()` at 2534 passes `fixture` only for `codex`/`cursor`; `cmd_probe()` at 2555 repeats that gate (`fixture if pid in ("codex","cursor") else None`); `--fixture` help text at 2979 says "Codex or Cursor".
- Cursor provider (lines 1645–1856) is the reference pattern: `_cursor_auth_path()` honors `CURSOR_AUTH_FILE` env, `_cursor_read_token()` honors `CURSOR_OAUTH_TOKEN` env, `_cursor_http()` GET with cookie, `normalize_cursor()` builds `windows` list, `probe_cursor(fixture)` wraps every failure into `empty_provider()` / `attach_cursor_identity()`. `_KimiUnauth` (line 915) is the shared 401/403 sentinel.
- `empty_provider()` (line 153) emits placeholder windows `weekly` + `special`.
- `cmd_waybar()` (2711): `mark` + `meter(weekly.used_pct)` + `extra_txt` where `extra = extra_window(rec)` (special → credits → session, else `{}`). `meter(None)` returns `"—"` (line 2581) — a single-window provider renders `D <meter> —`, acceptable.
- `render_dashboard()` (2333) iterates `rec["windows"]` generically; footer line 2444 hardcodes `h/l or 1-5 switch`; `_tui_loop()` line 2504 hardcodes `ch in "12345"`.
- `cmd_identity()` (2841): falls through to `"{selected}: no identity cycle configured"` for providers without a branch — devin needs nothing.
- `cmd_validate()` (2917): accepts status `ok|unauth|unknown`, checks `used_pct` numeric — devin fits as-is.
- Fixture convention: `fixtures/<pid>.<variant>.json` (codex.pro, cursor.ultra, cursor.ondemand, kimi.remaining); `probe_<pid>(fixture)` accepts either a raw API payload or a cache-shaped `{"providers":{pid:rec}}` envelope (see `probe_cursor` lines 1828–1839).
- Test convention (`tests/test-cursor-fixture.sh`, `tests/test-token-plan-omp.sh`): bash, `set -euo pipefail`, `mktemp -d` + trap, isolated `AI_USAGE_CACHE`/`AI_USAGE_SELECTED`/HOME, `jq` assertions on `waybar` JSON, terminal `echo <NAME>_OK`.
- Devin credentials live at `~/.local/share/devin/credentials.toml` — verified present, keys: `windsurf_api_key`, `api_server_url` (`https://server.codeium.com`), `devin_webapp_host`, `devin_api_url`.
- Uncommitted work in tree (must ship): `README.md`, `bin/ai-usage` (+419: token-plan OMP metering, codex-titanium fallback, identity attach), `docs/identity-swap.md`, `tests/test-identity*.sh`, new `tests/test-token-plan-omp.sh`. Remote `origin` = `git@github.com:VeigaPunk/omarchy-usage-tray.git`, last commit `cca072a`.

### Verified live today (2026-09-11, real call)
POST `https://server.codeium.com/exa.seat_management_pb.SeatManagementService/GetUserStatus`
with `Authorization: Bearer <windsurf_api_key>`, `Content-Type: application/json`, body
`{"metadata":{"apiKey":<key>,"ideName":"devin","ideVersion":"1.0.0","extensionVersion":"1.0.0","sessionId":<uuid4>,"requestId":<uint64 string>,"locale":"en_US","os":"linux","appVersion":"1.0.0"}}`
returns `userStatus.planStatus`:
- `planInfo.planName` = `"Max"`, `planInfo.teamsTier` = `TEAMS_TIER_DEVIN_MAX`, `planInfo.hideDailyQuota` = `true`, `planInfo.monthlyPromptCredits` = `-1` (unlimited — do NOT surface as a credits window).
- `planStart`/`planEnd` ISO strings (`2026-09-11T20:21:39Z` → `2026-10-11T20:21:39Z`).
- `dailyQuotaRemainingPercent` = `100`, `weeklyQuotaRemainingPercent` = `100` (numbers, not strings).
- `dailyQuotaResetAtUnix` = `"1789200000"`, `weeklyQuotaResetAtUnix` = `"1789286400"` (uint64 **as strings** — must coerce; `iso_from_unix` at line 98 already handles digit strings).

### Missing
- `devin` entry in `PROVIDERS`, `PROBERS`, `probe_one`, `cmd_probe` fixture gate, `--fixture` help.
- `probe_devin`/`normalize_devin`/`_devin_*` helpers (~120 lines, cursor-shaped).
- `fixtures/devin.max.json` + `tests/test-devin-fixture.sh`.
- TUI `"12345"` → `"123456"` and footer `1-5` → `1-6`.
- README provider list + docs/identity-swap.md auth-table row.
- Commits + push of all pending work.

### Risk
- Connect endpoint may reject requests without exact metadata fields — mitigated: verified live today; keep the verified body verbatim.
- `hideDailyQuota` semantics: on this Max account daily data exists but the flag says the plan doesn't meter it — suppressing is the intended behavior; a future non-Max account exercises the daily path via fixture test.
- `requestId`/`sessionId` may need to be strings of uint64/uuid — verified working with `str(random.getrandbits(63))` / `str(uuid.uuid4())`.

## WWKD

1. **What:** Add `devin` as the 6th provider in `bin/ai-usage` — probe `GetUserStatus`, normalize to a `weekly` window (+ `session` daily when not hidden), render in chip/TUI — then commit and push all pending work to `origin main`. Success boundary: `ai-usage probe devin` prints `devin ok … weekly=<n>` and `ai-usage waybar` shows the `D` chip; `git status` clean and `origin/main` == HEAD.
2. **Why:** The repo already has a proven single-file provider pattern (cursor is the nearest neighbor: local credential file → HTTP → normalize → `empty_provider` error funnel). The Devin endpoint is verified live, so the only invention is field mapping — everything else is pattern-following.
3. **Assumptions/Risks:** (a) `hideDailyQuota` means "don't show daily" not "daily is zero" — honored by omission, not zeroing. (b) Quota percents arrive as numbers but reset times as strings — normalize defensively through `as_pct`/`iso_from_unix`. (c) No second devin identity exists → `cmd_identity` no-op is correct, no swap helper.
4. **How:** M1 skeleton (probe→cache→waybar end-to-end, live call) → M2 overfit the real Max response (exact field mapping, hideDailyQuota) → M3 wire-in (PROVIDERS/PROBERS/fixture/TUI/docs) → M4 ship (tests, two commits, push).
5. **Escalation points:** (a) If the live probe regresses (endpoint drift) — judge decides whether to ship fixture-only. (b) Commit granularity for the pre-existing uncommitted work — plan recommends one commit for prior work + one for devin; judge may squash. (c) Logo letter `D` — free, no conflict (C/T/G/K/R taken).

## Decisions (pre-made, executor implements as written)

- **Daily window kind = `session`, label `Daily`.** `extra_window()` precedence is special→credits→session; `session` is the semantic fit for a short-cycle meter and lands in the secondary slot without competing with a future `special`. When `planInfo.hideDailyQuota` is true, **omit the window entirely** — the chip renders `D <weekly> —` (verified: `meter(None)` → `"—"`, `extra_window` → `{}`, no crash). Do not emit a placeholder daily window on success; placeholders belong to `empty_provider` only.
- **Error/empty shape:** add `_empty_devin(reason)` mirroring `_empty_token_plan` — windows `[weekly placeholder, session "Daily" placeholder]` so the error state matches the success layout. Do NOT reuse `empty_provider` (its `special` placeholder mislabels the secondary slot).
- **Env overrides (cursor pattern):** `DEVIN_API_KEY` (explicit key, like `CURSOR_OAUTH_TOKEN`), `DEVIN_CREDENTIALS_FILE` (like `CURSOR_AUTH_FILE`), `DEVIN_API_SERVER` (host override; default from `api_server_url` in the toml, fallback `https://server.codeium.com`).
- **Normalization:** `used_pct = 100 - float(remainingPercent)` via `as_pct`; `resets_at = iso_from_unix(weeklyQuotaResetAtUnix)` (handles string digits); `rec["plan"] = planInfo.planName`; `rec["status"]="ok"` iff weekly `used_pct` present, else `unknown`/`no_used_pct` (cursor convention).
- **HTTP:** stdlib `urllib.request` POST, JSON body, 15s timeout, `redact()` on all error strings; 401/403 → `_KimiUnauth` → `unauth`/`need_devin_login`; missing creds → `unauth`/`need_devin_login`; other failures → `unknown` + bounded redacted message.
- **Fixture:** `probe_devin(fixture)` accepts raw `GetUserStatus` JSON or `{"providers":{"devin":…}}` envelope; add `"devin"` to the fixture gates in `probe_one` and `cmd_probe`; update `--fixture` help to "Codex, Cursor, or Devin snapshot JSON (no network)".
- **New imports:** `uuid`, `random` (stdlib, top of file).
- **Logo:** `"D"`, name `"Devin"`, appended last in `PROVIDERS` (position 6, TUI key `6`).

## Milestones

| # | Title | Gate command | Expected output | Executor |
|---|---|---|---|---|
| M01 | Skeleton: devin probe end-to-end (live) | `bin/ai-usage probe devin && bin/ai-usage select devin && bin/ai-usage waybar` | stdout `devin ok … weekly=<pct>`; waybar JSON `.text` starts with `D ` and contains `bgcolor`, `.alt=="devin"`, `.class` contains `ok` | kx-executor-devin |
| M02 | Overfit: real Max response normalized bit-for-bit | `bin/ai-usage probe devin --fixture fixtures/devin.max.json && python3 -c 'import json,sys; r=json.load(open("'$AI_USAGE_CACHE'"))["providers"]["devin"]; w=r["windows"]; assert r["plan"]=="Max" and r["status"]=="ok"; assert w[0]["kind"]=="weekly" and abs(w[0]["used_pct"]-(100-<fixtureWeekly>))<0.01 and w[0]["resets_at"]; assert len(w)==1'` | exits 0; weekly used_pct = 100 − fixture `weeklyQuotaRemainingPercent`; `resets_at` = ISO of `weeklyQuotaResetAtUnix`; daily suppressed (hideDailyQuota=true) | kx-executor-devin |
| M03 | Wire-in: PROVIDERS/PROBERS/fixture/TUI/docs | `bin/ai-usage probe --fixture fixtures/devin.max.json devin; bin/ai-usage tui --dump \| grep -n 'Devin\|1-6'; bin/ai-usage validate` | probe accepts fixture for devin; TUI dump lists `Devin` chip and footer `1-6`; `validate` prints `VALID`; `grep -n '"devin"' bin/ai-usage` hits PROVIDERS+PROBERS+probe_one+cmd_probe | kx-executor-devin |
| M04 | Ship: tests + commit + push | `bash tests/test-devin-fixture.sh && bash tests/test-cursor-fixture.sh && bash tests/test-token-plan-omp.sh && bash tests/test-skeleton.sh && git status --short && git push origin main && git rev-parse HEAD origin/main` | all tests print their `_OK` marker; `git status` empty; both revs equal | kx-executor-devin |

### M01 — Skeleton (end-to-end, live)
**Does:** Add `("devin","Devin","D")` to `PROVIDERS`; add `_devin_credentials()` (tomllib read of `DEVIN_CREDENTIALS_FILE` or `~/.local/share/devin/credentials.toml`, `DEVIN_API_KEY` env wins), `_devin_user_status()` (verified POST body verbatim), `normalize_devin()` (weekly window only for now), `probe_devin()`, `PROBERS["devin"]`. Minimal viable: even if normalize only maps weekly, the whole pipeline runs.
**Gate:** `bin/ai-usage probe devin` → `devin ok … weekly=…`; `bin/ai-usage select devin && bin/ai-usage waybar` → `.alt=="devin"`, text `D <meter> —`.
**Touches:** `bin/ai-usage` only.
**Out-of-scope:** daily window, hideDailyQuota, fixture support, TUI keys, docs.

### M02 — Overfit one real instance (this Max account)
**Does:** Capture the live response into `fixtures/devin.max.json` (redact nothing — response contains no secrets, but strip `email`/`name`/`userId`/`teamId`/`orgId` fields to keep the fixture anonymous); finish `normalize_devin`: plan name, `resets_at` from string-unix, `session`/`Daily` window gated on `!planInfo.hideDailyQuota`, `_empty_devin`, full error funnel (`need_devin_login`, `bad_payload`, `http_<code>`).
**Gate:** fixture probe → cache record exactly: `status=ok`, `plan=Max`, `windows=[{kind:weekly, used_pct:100−weeklyQuotaRemainingPercent, resets_at:ISO(weeklyQuotaResetAtUnix)}]`, no daily window. Second fixture variant `fixtures/devin.daily.json` (hand-edited: `hideDailyQuota:false`, `dailyQuotaRemainingPercent:40`) → two windows, `session` used_pct=60.
**Touches:** `bin/ai-usage`, `fixtures/devin.max.json`, `fixtures/devin.daily.json`.

### M03 — Wire-in (one axis: integration surface)
**Does:** `probe_one` + `cmd_probe` fixture gates add `"devin"`; `--fixture` help text; `_tui_loop` `"12345"`→`"123456"`; footer `1-5`→`1-6`; `tests/test-devin-fixture.sh` (clone of `test-cursor-fixture.sh`: fixture→cache→waybar, mode-600 check, `D` logo, `Devin` tooltip, `ok` class, daily-variant tooltip shows `Daily`); README line 3 provider list + a short Devin bullet (credentials path, env overrides); `docs/identity-swap.md` auth-table row (`~/.local/share/devin/credentials.toml`, second store: no).
**Gate:** `tests/test-devin-fixture.sh` prints `DEVIN_FIXTURE_OK`; `bin/ai-usage tui --dump` shows `[Devin]` chip row and `1-6` footer; `bin/ai-usage validate` → `VALID`.
**Touches:** `bin/ai-usage`, `tests/test-devin-fixture.sh`, `README.md`, `docs/identity-swap.md`.

### M04 — Ship
**Does:** Run the relevant test subset (`test-devin-fixture`, `test-cursor-fixture`, `test-token-plan-omp`, `test-skeleton`, `test-identity-cycle` — skip live/network-gated ones); commit pending work as two commits: (1) `Add Token Plan OMP metering, codex-titanium fallback, and identity cycle fixes` (the pre-existing diff), (2) `Add Devin usage provider (Codeium GetUserStatus weekly/daily quota)`; `git push origin main`.
**Gate:** `git status --short` empty; `git rev-parse HEAD` == `git rev-parse origin/main`; `git log origin/main -2` shows both commits.
**Touches:** git only.

## Dependencies

M01 → M02 → M03 → M04 (strictly sequential — each gate assumes the previous passed; M03's TUI key `6` is meaningless before M01's PROVIDERS entry; M04 ships everything).

## Notes for executor

- Do NOT add a `credits` window: `monthlyPromptCredits: -1` means unlimited on Max; a `$-1` or fabricated credit meter is worse than none.
- Do NOT touch `cmd_identity` — fallthrough already prints `devin: no identity cycle configured` and returns 0.
- `keep_last_good`/`upsert`/`export_quattro` are provider-agnostic — no changes needed.
- The systemd timer runs `ai-usage probe` (all providers) — devin joins automatically via `PROVIDERS`; no `deploy/` or `systemd/` changes needed (verified: no per-provider config there).
- Fixture files must not contain real `email`, `name`, `userId`, `teamId`, `orgId` — strip when capturing.

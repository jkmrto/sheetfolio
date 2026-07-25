# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

Sheetfolio is a single-user Elixir/Phoenix portfolio dashboard. It reads holdings from a Google Sheet, reconstructs the operation history from MyInvestor confirmation emails in Gmail, fetches market prices, and stores daily snapshots in MongoDB Atlas. Deployed on Fly.io (`sheetfolio.fly.dev`, Amsterdam). There is no Ecto/SQL database. Tests cover the pure calculation layer only (money parsing, position replay, Urbanitae rollups); everything involving the UI or an external API is verified by running the app.

## Commands

- `make run` — start the app locally with `iex -S mix phx.server`. Required: it loads secrets from `.env` (Google credentials, `SPREADSHEET_ID`, `MONGODB_URI`, Gmail/Wise tokens). A bare `mix phx.server` will crash in `runtime.exs`.
- `mix credo` — lint; must stay clean (see Quality gate).
- `mix compile --warnings-as-errors` — quick sanity check; must stay clean.
- `mix test` — pure-function tests. Needs no secrets: the test env starts no services (`start_services: false`), and `runtime.exs` skips its secret lookups there.
- `mix assets.build` — esbuild bundle of `assets/js/app.js` (there is no npm build; charts are hand-rolled JS/SVG in LiveView hooks).
- `mix parse_myinvestor_emails` — dry run: fetch and parse all MyInvestor operation emails.
- `mix wise_operations [days]` — dry run: fetch Wise balances and activities (needs `.env`, so use `make wise-operations`).
- `fly deploy` — deploy to production.
- One-off backfills live in `scripts/*.exs` (run with `mix run`).

CI (GitHub Actions) runs `mix compile --warnings-as-errors`, `mix credo`, `mix test`, `mix hex.audit`, and `mix sobelow --config`.

## End-of-task routine
When a task that changed code is complete and verified, always finish by:

1. Making exactly one git commit for the task (don't batch unrelated tasks into it).
2. Running `fly deploy` and checking production stays healthy.
3. Pushing to GitHub (`git push origin master`).

This is standing authorization — don't ask for confirmation.

A Stop hook in `.claude/settings.json` blocks ending the turn while the working tree is dirty.

## Quality gate
`mix credo` must stay clean before committing (also enforced in CI). `.credo.exs` loads a custom check, `Sheetfolio.Checks.NestedCase` (`checks/nested_case.ex`), which forbids a `case` nested inside another `case` — extract the inner one into a function with one clause per pattern.

## Architecture

### Supervision tree (`lib/sheetfolio/application.ex`)
- **Goth** — Google service-account auth for the Sheets API (Gmail uses a separate OAuth refresh-token flow in `GmailClient`).
- **Mongo** (`:mongo`) — MongoDB Atlas; collections include `portfolio_snapshots`, `cash_snapshots`, `wise_activities`.
- **`EarningsServer`** — caches current/historical prices and FX rates; LiveViews request computations via `cast` with a `caller_pid` and receive results as messages (async, non-blocking UI).
- **`OperationsServer`** — at boot, loads the full operation history by fetching and parsing MyInvestor Gmail emails (slow: minutes); serves it from memory afterwards. `get_operations/1` blocks until loaded; `reload/0` refetches.
- **`SnapshotRecorder`** — writes a per-position portfolio snapshot to Mongo at boot and daily at 22:00 UTC; upserts by date.

### Data flow
1. `GmailClient` searches MyInvestor confirmation emails; `MyinvestorParser` extracts operations (buys, sells, traspasos).
2. `SyntheticOperations` (hardcoded ops missing from Gmail) and `OperationOverrides` (per-`{fecha, isin}` corrections, `skip: true` to exclude) patch the parsed history. This is the standard mechanism when an email is missing or wrong — add entries there, don't special-case downstream.
3. `Positions` replays operations into per-ISIN positions using average-cost basis and computes realized P&L events (sells beyond recorded buy history are "uncovered" and realize nothing).
4. `PriceFetcher` resolves ISIN → ticker (Yahoo Finance search, OpenFIGI fallback) and fetches EUR prices; `lib/sheetfolio/prices_api/` holds the Yahoo/Stooq/OpenFIGI clients. Problem ISINs are handled via `@ticker_overrides` / `@stooq_overrides` in `PriceFetcher`.
5. `GoogleSheetsClient` reads the spreadsheet; `Urbanitae` derives a manual position from spreadsheet columns. ISINs come from the parsed emails, not from the sheet.
6. `WiseClient` + `WiseExpenses` pull spending by category from the Wise activities endpoint (statements/SCA are unavailable for personal accounts), caching activity details in Mongo.

### Web layer (`lib/sheetfolio_web/`)
- Everything is LiveView; routes in `router.ex`. All pages sit behind `AuthPlug` (single password, `APP_PASSWORD`).
- Routes under the `live_session :authenticated` block mount `LoadingHook`, which redirects to `/loading` until `OperationsServer` has finished its boot load. Pages that need operation history belong inside that block.
- LiveViews are self-contained: markup, inline CSS, and chart JS live in each `*_live.ex` file. Follow that pattern rather than extracting shared components.

## Conventions

- Spreadsheet/domain vocabulary is Spanish (`fecha`, `precio`, `cantidad`, `importe`, `traspaso`, "Reembolso"/"Suscripción"); dates are `dd/mm/yyyy` strings. Keep field names consistent with `MyinvestorParser` output.
- No `try/rescue`; no `with` nested inside `case` — use function clauses instead.
- Amounts are parsed from strings like `"1499.91 EUR"`; prices are converted to EUR using FX rates from `EarningsServer`.

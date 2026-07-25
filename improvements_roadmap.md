# Improvements roadmap

Findings from a read-through of the supervision tree, the Gmail ingest path, the
price pipeline, the Mongo-backed modules and the LiveViews (July 2026). Ordered
by value, not by effort.

Status legend: `[ ]` pending, `[x]` done.

---

## 1. Bugs

### 1.1 Synthetic operations are silently not applied `[x]`

`Sheetfolio.SyntheticOperations` is referenced by nothing in `lib/`. It used to
be wired into the ingest path — `MyinvestorEmails.fetch_all/0` ended with:

```elixir
{:ok, ops ++ traspasos ++ Sheetfolio.SyntheticOperations.all()}
```

Commit `6386c4a` ("Restore DCA Impact and Control pages from stale worktree",
2026-07-05) rewrote that function to add the progress callback and dropped the
concatenation. Since then the two AXA Trésor Court Terme reembolsos
(1499.91 EUR on 28/10/2024 and 1000.19 EUR on 26/11/2024) have been missing
from the operation history, which shifts realized P&L and the uncovered-units
count on `/earnings`.

### 1.2 The `skip: true` override does nothing `[x]`

`OperationOverrides.apply/1` only merges the override map into the operation, so
`skip: true` just adds a `skip` key and the operation still flows into
`Positions.replay`. Nothing anywhere filters on it, even though both the module
comment and `CLAUDE.md` document it as the way to exclude an operation.

---

## 2. Boot time

Boot costs **two sequential HTTPS round-trips per email**: `GmailClient.get_message/1`
calls `fetch_token/0`, which does a full OAuth refresh POST against
`oauth2.googleapis.com` for every single message. `MyinvestorEmails.fetch_all/1`
then walks the id list with `Enum.flat_map`, so there is no concurrency either.
That is why boot takes minutes.

### 2.1 Cache the access token, fan out the fetches `[x]`

Hold the token in a small GenServer keyed to its `expires_in`, refreshing
shortly before expiry, and replace `Enum.flat_map` with
`Task.async_stream(max_concurrency: 8)`. No schema, no migration, no Mongo —
this alone takes boot from minutes to seconds. The progress callback has to
count completions rather than index the stream.

### 2.2 Cache emails in MongoDB `[x]`

Collection `myinvestor_emails`, `_id` = the Gmail message id (stable, and these
emails are immutable, so invalidation is trivial). Store subject, raw HTML body
and `fetched_at`. Boot reads the collection and is ready immediately; a
background task then lists ids via `search_messages` (cheap — 100 per page, no
per-message fetch), diffs against what is stored, and fetches only new ones.

**Design constraint: cache raw HTML, apply overrides at serve time.** Today
`fetch_and_parse/1` calls `OperationOverrides.apply/1` before the operation
leaves the module. Caching post-override operations would mean that correcting a
cost basis in `operation_overrides.ex` requires blowing away the cache and
refetching everything from Gmail. Keeping the cache as "what Gmail said" and
layering overrides plus synthetic operations in `OperationsServer` makes
corrections a restart instead of a refetch.

Side effects: Gmail being down at boot degrades to last-known-good instead of
`operations: []` (today `handle_info({:load_done, {:error, _}})` sets
`status: :ready` with an empty list, so the whole dashboard silently shows a
zeroed portfolio), and `/loading` stops appearing in the normal case.

---

## 3. Stale prices and FX `[x]`

`EarningsServer.init/1` sends itself `:fetch_fx` once and never reschedules.
`fly.toml` has `auto_stop_machines = 'off'` with `min_machines_running = 1`, so
the machine runs until the next deploy — meaning every USD and CAD conversion
uses the exchange rate from whenever the app was last deployed.

`price_cache` has the same problem: no TTL, emptied only by the manual button on
`/control`.

Fix: periodic `:fetch_fx` (hourly) and a timestamped price cache with a ~15
minute TTL.

---

## 4. EarningsServer serializes all network I/O `[x]`

Every price fetch happens inside `handle_cast` in the single `EarningsServer`
process. When `/summary` mounts it casts one request per ISIN and those are
processed strictly one at a time, each doing a Yahoo search plus a quote request
(plus an OpenFIGI fallback when Yahoo misses). Rows trickle in.

Worse: `get_fx_rates/0` is a `GenServer.call` with the default 5s timeout, and
`SnapshotRecorder.record/0` calls it at boot — exactly when `EarningsServer` is
most likely to be mid-fetch. That call can exit and take the boot snapshot with
it.

Fix: keep `EarningsServer` as a cache coordinator and move the HTTP into spawned
tasks. On a miss, register the caller as waiting, spawn a `Task`, reply to
everyone waiting on that ISIN when it returns (which also dedupes concurrent
requests for the same ISIN). The GenServer then never blocks on the network.

---

## 5. Redundant price-pipeline work `[x]`

`PriceFetcher.fetch_prices/1` re-fetches both FX pairs on every call, and
`resolve_ticker/1` re-does the Yahoo search per ISIN per call. ISIN→ticker
mappings are permanent — persisting them in a small Mongo collection removes two
HTTP calls per position per snapshot and lets `@ticker_overrides` become data
rather than source.

---

## 6. Snapshots silently record partial data `[x]`

In `SnapshotRecorder.record/0` a position whose price fetch fails gets
`value: nil` and is then filtered out of `valued`, so it contributes to neither
`total_invested` nor `total_value`. A transient Yahoo failure on a large
position writes a permanently understated point into `portfolio_snapshots`,
showing up as a fake dip in the portfolio chart that never self-corrects (the
next day's run writes a different date).

Fix: carry forward the previous snapshot's price for the missing ISIN, and mark
the document `partial: true` when that happens. Minor, same function:
`Mongo.create_indexes` runs on every record — move it to `init/1`.

---

## 7. Tests `[x]`

`mix test` does not run at all: there is no `config/test.exs`, so it dies
loading config, and `test/sheetfolio_test.exs` asserts
`Sheetfolio.hello() == :world` against a `lib/sheetfolio.ex` that does not
exist.

The LiveViews are fine to verify by running the app. But three pure code paths
are where a silent regression corrupts money numbers rather than breaking a page
visibly:

- `MyinvestorParser.parse/2` and `parse_traspaso/2`
- `Positions.replay` — average-cost basis, covered/uncovered sell split
- `UrbanitaeTransactions.rollup_by_project/2` and `time_series/1`

The email cache makes parser tests nearly free: once raw HTML bodies are in
Mongo, dump a handful into `test/fixtures/` and pin the parser output.

Add `mix test` and `mix compile --warnings-as-errors` to the credo workflow.

---

## 8. Cleanups `[x]`

- `PortfolioCalculator` is not just dead, it is broken — it references
  `Sheetfolio.SheetData`, a module that does not exist in the repo. Deleting it,
  `OperationsController` and `operations_html` also orphans `Sheetfolio.Assets`,
  since `PortfolioCalculator` is its only caller. Note this means the
  "Participaciones" sheet is no longer the runtime source of truth for
  asset→ISIN mapping (ISINs come from parsed emails), so that line in
  `CLAUDE.md` is stale.
- `Positions.parse_number/1` and `EarningsServer.parse_number/1` are
  character-for-character identical; `to_eur/4` exists three times (Positions,
  PriceFetcher, EarningsServer), as does the `precio` regex parse. One
  `Sheetfolio.Money` module removes ~60 duplicated lines from the code that
  decides what the portfolio is worth.
- `SessionController.create/2` compares the password with `==`.
  `Plug.Crypto.secure_compare/2` is a drop-in replacement. Low stakes behind a
  random password, but free.

---

## Not doing

Extracting shared components out of the LiveViews. `CLAUDE.md` says LiveViews
are deliberately self-contained (markup, inline CSS and chart JS in each
`*_live.ex`), so the duplicated styling stays.

---

## Measured outcomes

All of the above shipped. Numbers against the real mailbox and MongoDB Atlas:

| | before | after |
|---|---|---|
| Boot to serving the history | minutes | 908ms |
| 10 Gmail messages | 2772ms | 416ms |
| Full 252-email download | ~140s (estimated) | 7.0s |
| Background sync finding nothing new | n/a | 2.8s |

The cached mailbox is 252 emails, about 780KB gzipped, and parses in ~100ms.
Parsed output was checked to be identical to fetching straight from Gmail.

One incidental confirmation of the staleness problem: production's snapshot for
2026-07-24 was missing the operations from 20, 22 and 23 July, because its
`OperationsServer` had loaded at boot days earlier and only refreshes on a
manual reload. The background sync fixes that.

---

## Still open

- **Parser fixtures.** `MyinvestorParser` is still untested. The natural
  fixtures are now sitting in the `myinvestor_emails` collection, but a raw
  confirmation email likely carries name, address and account identifiers, so
  it needs redacting before it can land in the repo.
- **Cost basis is recomputed at today's FX rate.** `Positions.build/3` takes the
  current `eur_usd`/`eur_cad` and applies them while replaying the whole
  history, so the reported *invested* amount for USD and CAD positions drifts
  every day even when nothing is bought or sold — Humacyte moved 2973.02 →
  2987.40 between two consecutive snapshots on no activity. Cost basis should
  arguably use the rate at the time of each operation. Pre-existing, unrelated
  to anything changed here, and it changes historical numbers, so it wants a
  deliberate decision rather than a drive-by fix.
- **Three same-day duplicate operations** appear in the history (one on
  23/09/2024, 04/07/2023 and 02/09/2025). They come from genuinely distinct
  Gmail messages and predate all of this work, so they're most likely two real
  purchases of the same size on the same day — worth an eyeball, not a fix.

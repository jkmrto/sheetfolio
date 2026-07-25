# Plan: Bitcoin DCA subtab + automatic Wise balance tracking

Two independent pieces of work. Do them as **two separate tasks with one commit
each**, per the end-of-task routine in `CLAUDE.md` (commit, then `fly deploy`).

Everything below was checked against the live system on 2026-07-25; the facts in
"Verified" boxes don't need re-deriving.

---

# Task 1 — Split DCA Impact into "S&P 500" and "Bitcoin" subtabs

## What exists today

`/summary/dca` is `SheetfolioWeb.DcaLive`, a single page hardcoded to the S&P 500:

- `@base_amount 250.0`, `@sp500_isins ~w[IE0032126645 IE00BYX5MX67]`
- Each purchase is split into **base** (first 250 €) and **extra** (the rest),
  the page's whole thesis being "did the extra I invested when the market dipped
  pay off?"
- A modal recommends this week's amount from how far `^GSPC` is below its 5y ATH
- Chart via the `DcaChart` hook in `assets/js/app.js` (4 series: baseline,
  actual, S&P500, invested)

## Target

Two subtabs under the existing "DCA Impact" nav item. The S&P 500 subtab is the
current page, unchanged. The Bitcoin subtab is new and **does not** use the
base/extra model — the user's Bitcoin buys are a steady ~100 €/week, so there is
no discretionary "extra" to measure. It shows DCA performance against Bitcoin
itself.

> **Verified — the Bitcoin DCA history**
> ISIN `GB00BJYDH287` ("WISDOMTREE BITCOIN"). 53 buys, roughly weekly, of whole
> units (6–8) costing ~90–105 € each. Recent: 22/07 7u/96.90 €, 17/07 7u/92.08 €,
> 08/07 8u/105.11 €, 02/07 8u/102.64 €. Position at last snapshot: 313 units,
> 6255.03 € invested.

## Structure: separate routes and modules

Add a route and a new LiveView rather than branching inside `DcaLive`:

```elixir
# router.ex, inside live_session :authenticated
live "/summary/dca", DcaLive
live "/summary/dca/bitcoin", DcaBitcoinLive
```

Rationale: the two subtabs share no state, and keeping `DcaLive` untouched means
zero regression risk on the working S&P 500 page. It also matches the CLAUDE.md
convention that LiveViews are self-contained. The subtab bar is ~6 lines of
markup duplicated in both files — that is the intended trade-off here, do not
extract it into a shared component.

### Subtab bar

Copy the visual pattern from `ExpensesLive` (`.expenses-subtabs`, around line 91
of `expenses_live.ex`) into both DCA LiveViews, renamed `.dca-subtabs`:

```heex
<div class="dca-subtabs">
  <.link navigate="/summary/dca" class={if @subtab == "sp500", do: "active", else: ""}>S&amp;P 500</.link>
  <.link navigate="/summary/dca/bitcoin" class={if @subtab == "bitcoin", do: "active", else: ""}>Bitcoin</.link>
</div>
```

Use `navigate`, not `patch` — these are different LiveView modules.
Set `subtab: "sp500"` / `subtab: "bitcoin"` in each module's `mount`.

### Nav highlight

`lib/sheetfolio_web/components/layouts/root.html.heex` currently does an exact
match, so the nav item would go dark on the Bitcoin subtab:

```heex
<a href="/summary/dca" class={if current_path(assigns) == "/summary/dca", do: "active", else: ""}>DCA Impact</a>
```

Change that one condition to `String.starts_with?(current_path(assigns), "/summary/dca")`.
Leave the other nav entries alone.

## `DcaBitcoinLive` — data

Mount follows the same shape as the other LiveViews (auth check, `connected?`
guard, request prices via `EarningsServer`, receive `{:price_result, isin, price}`).

```elixir
@btc_isin "GB00BJYDH287"
```

**Per-buy rows.** Reuse the existing helpers rather than reimplementing:

```elixir
qty = Sheetfolio.Positions.parse_cantidad(op.cantidad)
eur = Sheetfolio.Positions.amount_in_eur(op.importe_with_comision, op.precio, qty, eur_usd, eur_cad)
```

Filter `op.isin == @btc_isin and op.tipo in ["Compra", "Suscripcion"] and not op.traspaso`,
then group by `op.fecha` and sum, so two buys on one day become one row (same as
`DcaLive.build_operations/3` does). Newest first.

Row fields: `fecha`, `units`, `invested`, `unit_cost` (invested / units),
`value_now`, `pnl`, `pnl_pct`. The last three fill in when the price arrives.

**Cards:** Total invested, Current value, P&L (€), P&L (%), Units held,
Average cost per unit, Number of buys.

**Chart:** three series.

| Series | Axis | Source |
|---|---|---|
| Invested (€), cumulative | left `y` | running sum of `invested` |
| Value (€), cumulative | left `y` | `cumulative_units(t) × etf_price_eur(t)` |
| Bitcoin (USD) | right `y1` | `BTC-USD` close |

> **Verified — price series**
> `YahooFinance.fetch_series("BTCW.L", from, to)` returns `{:ok, %{Date => close}, "USD"}`.
> `BTCW.L` is the existing `@ticker_overrides` entry for this ISIN in
> `PriceFetcher`, and it quotes in **USD** — so the existing `eur_usd` rate is
> enough and no new FX pair is needed. Spot check: BTCW.L 15.305 USD,
> BTC-USD 63987.9.

Resolve the ticker through `Sheetfolio.PriceFetcher.resolve_ticker(@btc_isin)`
rather than hardcoding `"BTCW.L"`, so the override stays the single source of truth.

Yahoo only returns trading days. Copy the gap-filling trick from
`DcaLive.attach_sp500_prices/2` — look back up to 4 days for the nearest close:

```elixir
Enum.find_value(0..4, fn offset -> Map.get(prices, Date.add(date, -offset)) end)
```

Convert with `Sheetfolio.Money.to_eur(price, "USD", eur_usd, eur_cad)`; don't
open-code the division.

## `DcaBitcoinChart` hook

`Hooks.DcaChart` in `assets/js/app.js` hardcodes the S&P 500 labels and axes, so
add a sibling `Hooks.DcaBitcoinChart` handling a `update_btc_dca_chart` event
with `{labels, invested, value, btc}`. Copy `DcaChart`'s options block and change:

- dataset labels to `Invested (€)`, `Value (€)`, `Bitcoin (USD)`
- the tooltip callback (it currently special-cases the string `'S&P500 (USD)'`)
- drop the unused `y2` axis

Register it in the `Hooks` object the same way and re-run `mix assets.build`.

## Pure functions to unit-test

Keep the aggregation out of the LiveView so it can be tested (see
`test/sheetfolio/` for the established style):

- `build_buys(operations, eur_usd, eur_cad)` → per-day rows. Test: two buys on
  one date merge; a `traspaso` is excluded; a sell is excluded.
- `cumulative_series(buys, prices_by_date)` → chart points. Test: cumulative
  invested is monotonic; a date missing from `prices_by_date` falls back to the
  most recent earlier close within 4 days.

---

# Task 2 — Record the Wise balance automatically

## What exists today

- `WiseClient.balances(profile_id)` already exists and works, but is only called
  by the `mix wise_operations` dry-run task — nothing in the app uses it.
- The Cash page (`CashLive`) has a `Wise` figure among
  `["Bankinter", "MyInvestor", "Wise", "Ibercaja"]`, but it is **typed in by hand**
  and written to `cash_snapshots` on form submit.
- `CashLive.handle_event("save", ...)` already carries values forward:
  `parse_number(params[name]) || latest[name]`, so a blank field reuses the last
  known amount.

> **Verified — what the API returns**
> Profile 13675836 (PERSONAL), 7 STANDARD balances. Only EUR is non-zero:
> **1961.14 EUR**. The rest are zero travel currencies (CNY, DKK, MAD, PLN, USD, VND).

## Target

Wise is recorded automatically every day; the other three sources stay manual and
carry forward; anything typed into the form still wins.

### New: `Sheetfolio.WiseBalance`

```elixir
@doc "Total Wise money in EUR, or {:error, reason} if Wise can't be reached."
def current_eur() :: {:ok, float} | {:error, term}
```

- first profile from `WiseClient.profiles()`, then `WiseClient.balances/1`
- sum `balance["amount"]["value"]` converting by `balance["amount"]["currency"]`
- EUR at face value; USD and CAD via `EarningsServer.get_fx_rates/0`
- any **other** currency with a non-zero balance: fetch `EUR<CUR>=X` from
  `YahooFinance.fetch_price/1`; if that fails, skip it and `Logger.warning`.
  Zero balances are skipped without a lookup — otherwise this makes six pointless
  HTTP calls a day for the travel currencies.

Extract the arithmetic as a pure `sum_eur(balances, rates)` so it can be tested
without the network.

### New: `Sheetfolio.CashRecorder`

Model it directly on `SnapshotRecorder` — same skeleton, and follow the two
corrections that module recently received:

- `Mongo.create_indexes` goes in `init/1`, not in the record function
  (`%{key: %{date: 1}, name: "date_unique", unique: true}` on `cash_snapshots`)
- when the source data is unavailable, **carry forward and mark it**, don't write
  a hole

```elixir
@collection "cash_snapshots"
@daily_hour_utc 21   # an hour before SnapshotRecorder's 22:00, so they don't contend
```

`record/0`:

1. read the most recent `cash_snapshots` doc
2. carry every source forward from it
3. overwrite the `Wise` entry with `WiseBalance.current_eur()`
4. on `{:error, _}`: keep the carried-forward Wise value, set `wise_stale: true`
   on the document, and `Logger.warning` — same pattern as `partial` on
   portfolio snapshots
5. recompute `total`, upsert by `date`

Register in `application.ex` **after** `EarningsServer` (it needs FX rates) and
after `Mongo`. Add a one-line comment in the children list like the neighbours have.

### `CashLive` changes

Small, and keep them small:

- On `connected?` mount, `send(self(), :fetch_wise)` and fetch in a
  `handle_info` — do **not** block `mount` on an HTTP call.
- Use the live balance as the `Wise` field's placeholder instead of the last
  saved amount. The other three keep their current placeholders.
- Leave the save semantics exactly as they are. Blank Wise then falls through to
  `latest["Wise"]`, which is now the auto-recorded figure — which is the desired
  "typed value wins, otherwise use what we recorded" behaviour, with no extra code.

---

# Conventions that will trip you up

From `CLAUDE.md` and the current state of the codebase:

- **`mix credo` must stay clean**, and a custom check forbids a `case` nested
  inside another `case` — use function clauses with one head per pattern.
- **No `try`/`rescue`**, and no `with` nested inside a `case`.
  (`DcaLive.fetch_sp500_ath/0` has a `try` — it predates the rule; don't copy it.)
- **`mix compile --warnings-as-errors` must stay clean.** CI now enforces this.
- **`mix test` must stay green** and must not need secrets or network — the test
  env starts no services (`start_services: false` in `config/test.exs`) and
  `runtime.exs` skips secret lookups there. Don't write a test that hits Mongo,
  Gmail, Yahoo or Wise.
- LiveViews stay self-contained: markup, inline CSS and chart JS per file. Don't
  extract shared components even where it looks tempting.
- Spanish domain vocabulary (`fecha`, `precio`, `cantidad`, `importe`, `traspaso`)
  in anything touching parsed operations.
- Money parsing goes through `Sheetfolio.Money` (`parse_number/1`,
  `parse_price/1`, `to_eur/4`). Don't add a fourth copy.

# Verification

`make run` (needs `.env`), then check in a browser at **`http://localhost:4000`** —
not `127.0.0.1`, which fails the endpoint's `check_origin` and silently breaks the
LiveView socket, leaving pages rendered but empty. `APP_PASSWORD` is unset
locally, so submit the login form empty.

- `/summary/dca` — unchanged: base/extra table, recommendation modal, 4-series chart
- `/summary/dca/bitcoin` — cards, per-buy table (53 rows), 3-series chart; nav
  "DCA Impact" stays highlighted on both
- `/cash` — Wise field pre-filled with ~1961 €; saving with it blank keeps that
  value; saving with a typed value overrides it
- Boot log shows `CashRecorder` writing a document, and the `/cash` chart gains a
  point for today

Then `mix compile --warnings-as-errors`, `mix credo`, `mix test`, commit, `fly deploy`.

Note `fly` needs the token exported explicitly in this environment:

```
export FLY_API_TOKEN="$(awk -F': ' '/access_token/ {print $2}' ~/.fly/config.yml | tr -d '"'"'"' \r')"
```

Ignore the post-deploy warning that the app "is not listening on the expected
address" — the smoke check runs before Bandit binds. Confirm with
`curl https://sheetfolio.fly.dev/` (302 to `/login`).

---
name: urbanitae-ingest
description: Ingest Urbanitae Movimientos screenshots into the urbanitae_transactions Mongo collection, and keep the urbanitae_projects collection up to date. Trigger when the user shares screenshots of the Urbanitae mobile app's Movimientos feed or the "Crowdfunding inmobiliario" overview.
---

# Urbanitae ingestion

Urbanitae has no API. The user shares screenshots of the mobile app; each
row on screen is one movement (Movimientos view) or one project rollup
(Crowdfunding inmobiliario overview).

Two collections back the `/urbanitae` page:

- **`urbanitae_transactions`** — INVERSIÓN + REEMBOLSO events. Each REEMBOLSO
  carries a `repayment_kind`: `"yield"` (interest/rent/interim distribution)
  or `"principal"` (return of capital, typically at project closure).
- **`urbanitae_projects`** — one doc per project with `type`
  (`plusvalia` | `alquiler` | `prestamo`). Type controls how future
  repayments default (see below).

## Movimientos row anatomy

| Field | Example | Notes |
|---|---|---|
| Green pill | `Crowd`, `Ingreso` | Product family |
| Title | `Inversión en el proyecto Valencia \| Proyecto Montesano` | See title formats below |
| Date | `23 may. 2024` | es-ES abbreviated month |
| Uppercase label | `INVERSIÓN` / `REEMBOLSO` / `INGRESO` / `TRANSFERENCIA` | Movement kind |
| Amount | `10.000 €`, `5.851,95 €` | es-ES: `.` thousands, `,` decimals |

### Title formats

| Kind | Title | Extract |
|---|---|---|
| INVERSIÓN | `Inversión en el proyecto {City} \| Proyecto {Name}` | city, project |
| REEMBOLSO | `Reembolso {City} \| Proyecto {Name}` | city, project |
| INGRESO | `Ingreso de dinero` | — (skip) |
| TRANSFERENCIA | `Transferencia a cuenta` | — (skip) |

## Crowdfunding inmobiliario overview

When the user shares the overview screen ("Crowdfunding inmobiliario" title,
sections `Plusvalía` / `Alquiler` / `Préstamo` under "Distribución de la
inversión en curso"), that's a chance to update the projects collection with
each project's type. Do this before ingesting the transactions so the
per-project defaults kick in.

## What to record

Ingest **INVERSIÓN → `investment`** and **REEMBOLSO → `repayment`** only.
Skip INGRESO and TRANSFERENCIA — wallet ↔ bank movements with no earnings
signal.

## Steps

1. **Read every screenshot** the user attached, top to bottom, left to right.
   Extract every visible row.
2. **Update project types** (only if an overview screenshot was shared):
   for each project in the En curso view, upsert to `urbanitae_projects` via
   `Sheetfolio.UrbanitaeProjects.upsert(%{project_key: ..., city: ..., project: ..., type: ...})`.
   Types come from the section header (`Plusvalía` → `"plusvalia"`,
   `Alquiler` → `"alquiler"`, `Préstamo` → `"prestamo"`).
3. **Normalize** each transaction row into the document shape:
   - `date`: parse `23 may. 2024` → `"2024-05-23"` (ISO string). Spanish
     months: `ene feb mar abr may jun jul ago sep oct nov dic`.
   - `kind`: `"investment"` for INVERSIÓN, `"repayment"` for REEMBOLSO.
   - `city`, `project`: from the title.
   - `project_key`: `Sheetfolio.UrbanitaeTransactions.project_key(city, project)`.
   - `amount`: parse es-ES number → float.
   - For repayments — `repayment_kind`: default per project type
     (see table below), but ask the user to confirm when it looks like a
     closure event (amount ≥ remaining outstanding).
   - `raw_title`: exact title string.
   - `captured_at`: `DateTime.utc_now()`.
4. **Dedupe** each parsed row via
   `Sheetfolio.UrbanitaeTransactions.find_matching/1` (natural key:
   `date + kind + project_key + amount`).
   - Exact match → drop silently, tally as `= duplicate`.
   - New → add to insert list.
   - Same `(date, kind, project_key)` but different amount →
     surface as `⚠ partial match`.
5. **New project?** If a transaction references a project not yet in
   `urbanitae_projects`, ask the user for its type before insert.
   Never silently insert a transaction whose project has no type — the
   rollup falls back to "Untyped" and the numbers get harder to read.
6. **Preview** as a compact table before writing:
   ```
   + 2026-07-16  investment  Oporto      Francos III       1.000,00 €
   + 2026-07-13  repayment   Barcelona   Golf Terraces     5.851,95 €  [principal]
   + 2026-04-28  repayment   Valencia    Pérez Galdós         81,25 €  [yield]
   = 2026-01-28  repayment   Valencia    Pérez Galdós         81,25 €  (already recorded)
   ```
   Followed by totals: `N new (K yield, L principal), M duplicates`.
7. **Wait for user confirmation.** No auto-insert.
8. **Insert** via `Sheetfolio.UrbanitaeTransactions.insert_many/1`.

## Repayment kind defaults (by project type)

| Project type | Default `repayment_kind` | Principal signal |
|---|---|---|
| `alquiler` | `yield` (rent) | Only the closure event returns principal — usually the amount is close to the invested amount, plus any final rent instalment. |
| `prestamo` | `yield` (interest) | Closure: amount ≈ outstanding principal + last interest tranche. Some loans amortize (each payment is part yield / part principal) but Urbanitae rarely surfaces that split; leave as yield unless user says otherwise. |
| `plusvalia` | Ambiguous — ask. | Plusvalía projects usually have a single closure event returning principal + capital gain in one payment. Interim distributions are rare but do happen. When you see a Plusvalía repayment, ask the user whether it's interim yield or the closure. |

## Anti-patterns

- **Don't ingest INGRESO / TRANSFERENCIA even "for context".** `/cash`
  handles the wallet-side view.
- **Don't rebuild the collection.** Ingest is additive. Fix a bad row with a
  targeted update, not a wipe.
- **Don't create projects on the fly without a type.** Ask.
- **Don't invent a project type when the overview isn't in this batch.**
  Ask; then when the user next shares an overview screenshot you can confirm.
- **Don't try to split principal vs interest inside a single repayment**
  (partial principal + partial interest). Urbanitae doesn't expose that;
  we keep a single `repayment_kind` per row. Small error is acceptable
  compared to the complexity of maintaining a split.

## Related

- Collection: `urbanitae_transactions` — `lib/sheetfolio/urbanitae_transactions.ex`.
- Collection: `urbanitae_projects` — `lib/sheetfolio/urbanitae_projects.ex`.
- Cross-check: `mix parse_urbanitae_emails` — Urbanitae's own mail confirms
  investments, funding closes and repayment dates, and flags anything missing
  from Mongo. It can't replace the screenshots: distribution emails never say
  how much *you* received.
- Page: `/urbanitae` — `SheetfolioWeb.UrbanitaeLive`.
- Legacy `Sheetfolio.Urbanitae` (Vision global / Ganancias sheet columns)
  still feeds the daily portfolio snapshot; the new page is additive.

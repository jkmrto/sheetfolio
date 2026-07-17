---
name: urbanitae-ingest
description: Ingest Urbanitae Movimientos screenshots into the urbanitae_transactions Mongo collection. Trigger when the user shares screenshots of the Urbanitae mobile app's Movimientos feed.
---

# Urbanitae ingestion

Urbanitae has no API. The user shares screenshots of the mobile app's
**Movimientos** feed; each row on screen is one movement.

## Row anatomy

| Field | Example | Notes |
|---|---|---|
| Icon color | grey up-arrow / green down-arrow | Direction, informational only |
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

## What to record

Ingest **INVERSIÓN → `investment`** and **REEMBOLSO → `repayment`** only.
Skip INGRESO and TRANSFERENCIA — those are wallet ↔ bank movements and
carry no earnings signal.

## Steps

1. **Read every screenshot** the user attached, top to bottom, left to right.
   Extract every visible row into an in-memory list, even truncated / cut-off
   ones at the bottom edge — but flag any amount that looks partial (e.g.
   `9.94...` with a `+` button overlapping it) and ask the user for the full
   value before inserting.
2. **Normalize** each row into the document shape:
   - `date`: parse `23 may. 2024` → `"2024-05-23"` (ISO string). Spanish month
     abbreviations: `ene feb mar abr may jun jul ago sep oct nov dic`.
   - `kind`: `"investment"` for INVERSIÓN, `"repayment"` for REEMBOLSO.
   - `city`, `project`: extracted from the title.
   - `project_key`: `Sheetfolio.UrbanitaeTransactions.project_key(city, project)`.
     Don't recompute manually — call the function so slug rules stay in one
     place.
   - `amount`: parse es-ES number → float (`5.851,95 €` → `5851.95`).
   - `raw_title`: the exact title string.
   - `captured_at`: `DateTime.utc_now()`.
3. **Dedupe** each parsed row against Mongo with
   `Sheetfolio.UrbanitaeTransactions.find_matching/1` (natural key:
   `date + kind + project_key + amount`).
   - Exact match → drop silently, tally as `= duplicate`.
   - New → add to insert list.
   - Same `(date, kind, project_key)` but different amount → surface as
     `⚠ partial match` so the user can decide (usually means a typo in an
     earlier ingest, not a legit second event).
4. **Preview** as a compact table before writing:
   ```
   + 2026-07-16  investment  Oporto       Francos III           1.000,00 €
   + 2026-07-13  repayment   Barcelona    Golf Terraces         5.851,95 €
   = 2026-04-28  repayment   Valencia     Pérez Galdós             81,25 €   (already recorded)
   ⚠ 2025-05-27  investment  Málaga      El Higuerón TB65      1.060,00 €   (existing has 1.600,00)
   ```
   Followed by a totals line: `N new, M duplicates, K flagged`.
5. **Wait for the user to confirm** before any Mongo write. Do not
   auto-insert.
6. **Insert** the confirmed batch with
   `Sheetfolio.UrbanitaeTransactions.insert_many/1` via a `mix run` one-liner
   (needs the app running so the Mongo pool is up). Report the resulting
   collection size afterwards.

## Anti-patterns

- **Don't invent project types.** All movements observed so far are `Crowd`
  (crowdlending). The pill's not persisted — we only track kind. If a truly
  different family appears (equity, savings…), stop and ask before extending
  the schema.
- **Don't try to split principal vs interest.** The screenshots don't
  distinguish them; keep repayments as a single `repayment` kind. Net P&L
  is derivable at close (`returned − invested`).
- **Don't ingest INGRESO / TRANSFERENCIA even "for context".** The user
  explicitly rejected those. `/cash` handles the wallet-side view.
- **Don't rebuild the collection.** Ingest is additive. If the user wants
  to fix a bad row, delete it directly in Mongo — don't wipe and reingest.

## Related

- Collection: `urbanitae_transactions` — see
  `lib/sheetfolio/urbanitae_transactions.ex` for the schema comment and CRUD.
- Page: `/urbanitae` — `SheetfolioWeb.UrbanitaeLive`.
- The legacy `Sheetfolio.Urbanitae` module (which reads "Vision global" and
  "Ganancias" from the spreadsheet) still feeds the daily portfolio snapshot
  and is not affected by this ingest.

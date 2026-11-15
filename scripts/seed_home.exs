# Records the flat on Av. de la Cruz del Campo 33 (Sevilla, 41005) in `homes`.
#
#     mix run scripts/seed_home.exs
#
# Safe to re-run: it upserts by name. To refresh later, edit the figures
# here (add a valuation, replace the mortgage statement) and run it again.
#
# Bought from Clikalia in September 2025: listed at 325.000 €, agreed at
# 315.000 €, renovated, 80 m², fourth floor, exterior, lift, and an
# unnumbered surface parking space. Shared 50/50, as is the mortgage.
# Out of pocket at purchase, down payment plus costs: 60.000 € each.
#
# The November 2026 valuation is an estimate: the Notariado's 41005
# second-hand flat average (2.914 €/m²), Fotocasa comparables in Nervión
# with a lift (3.750–4.500 €/m² asking, the low end here for being by Los
# Pájaros), and the purchase price grown 4–6%. Range 310.000–330.000 €.

alias Sheetfolio.Homes

:ok =
  Homes.upsert(%{
    name: "Av. Cruz del Campo 33",
    share: 0.5,
    purchase: %{date: "2025-09-01", price: 315_000, cash_paid: 120_000},
    valuations: [
      %{date: "2025-09-01", value: 315_000, note: "Purchase price"},
      %{
        date: "2026-11-15",
        value: 320_000,
        note: "Notariado 41005 + Fotocasa comparables, edge of Nervión"
      }
    ],
    mortgage: %{as_of: "2026-10-01", balance: 212_000, monthly_payment: 740, monthly_interest: 240}
  })

IO.puts("Recorded #{length(Homes.all())} home(s)")

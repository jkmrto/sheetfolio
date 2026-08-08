# Seeds Equito from the app's screenshots — properties from "Mis propiedades",
# movements from "Historial".
#
#     mix run scripts/seed_equito.exs
#
# Safe to re-run: properties upsert by code, and each movement is checked
# against its natural key (date + code + kind + amount) before insert, so
# overlapping screenshots top the ledger up instead of duplicating it.
#
# INCOMPLETE — still missing from the Historial, so the totals this produces
# understate the real position:
#
#   * EQT-0103's COMPRA (its first rent lands 01/01/2026 at a part month)
#   * EQT-0070's COMPRA day (March 2025, cropped in the screenshot)
#   * August 2025 rents, if there were any
#   * April–May 2025, between the March purchases and the first rent seen
#   * anything newer than 01/07/2026

alias Sheetfolio.{EquitoProperties, EquitoTransactions}

properties = [
  %{code: "EQT-0010", kind: "Apartment", surface_m2: 85, city: "Valencia", status: "Alquilado", yield_pct: 10.03, distributed_pct: 8.02},
  %{code: "EQT-0070", kind: "Apartment", surface_m2: 96, city: "Albal", status: "Alquilado", yield_pct: 9.22, distributed_pct: 8.32},
  %{code: "EQT-0072", kind: "Apartment", surface_m2: 94, city: "Alicante", status: "Alquilado", yield_pct: 9.87, distributed_pct: 8.54},
  %{code: "EQT-0074", kind: "Apartment", surface_m2: 86, city: "Alaquas", status: "Alquilado", yield_pct: 9.65, distributed_pct: 8.49},
  %{code: "EQT-0103", kind: "Apartment", surface_m2: 82, city: "Alicante", status: "Alquilado", yield_pct: 9.68, distributed_pct: 8.50},
  %{code: "EQT-0104", kind: "Apartment", surface_m2: 94, city: "Torrent", status: "Alquilado", yield_pct: 9.66, distributed_pct: 8.46}
]

# Every holding is 2 tokens at 100 €.
purchases = [
  {"2025-03-20", "EQT-0072"},
  {"2025-03-27", "EQT-0074"},
  {"2025-08-25", "EQT-0104"},
  {"2025-08-26", "EQT-0010"}
]

rewards = [{"2025-03-13", 10.00}]

# One entry per payout date: {date, [{code, renta, retención}]}. Both legs
# arrive as their own row in the app and are kept that way here.
distributions = [
  {"2025-06-01", [{"EQT-0070", 0.69, -0.13}]},
  {"2025-07-01", [{"EQT-0072", 1.42, -0.27}, {"EQT-0070", 1.38, -0.26}]},
  {"2025-09-01", [{"EQT-0074", 1.41, -0.27}, {"EQT-0072", 1.42, -0.27}, {"EQT-0070", 1.38, -0.26}, {"EQT-0010", 0.21, -0.04}]},
  {"2025-10-01", [{"EQT-0074", 1.41, -0.27}, {"EQT-0072", 1.42, -0.27}, {"EQT-0070", 1.38, -0.26}, {"EQT-0010", 1.33, -0.25}]},
  {"2025-11-01", [{"EQT-0074", 1.41, -0.27}, {"EQT-0072", 1.42, -0.27}, {"EQT-0070", 1.38, -0.26}, {"EQT-0010", 1.33, -0.25}]},
  {"2025-12-01", [{"EQT-0074", 1.41, -0.27}, {"EQT-0072", 1.42, -0.27}, {"EQT-0070", 1.38, -0.26}, {"EQT-0010", 1.33, -0.25}]},
  {"2026-01-01", [{"EQT-0104", 0.70, -0.13}, {"EQT-0103", 0.70, -0.13}, {"EQT-0074", 1.41, -0.27}, {"EQT-0072", 1.42, -0.27}, {"EQT-0070", 1.38, -0.26}, {"EQT-0010", 1.33, -0.25}]},
  {"2026-02-01", [{"EQT-0104", 1.40, -0.27}, {"EQT-0103", 1.41, -0.27}, {"EQT-0074", 1.41, -0.27}, {"EQT-0072", 1.42, -0.27}, {"EQT-0070", 1.38, -0.26}, {"EQT-0010", 1.33, -0.25}]},
  {"2026-03-01", [{"EQT-0104", 1.40, -0.27}, {"EQT-0103", 1.41, -0.27}, {"EQT-0074", 1.41, -0.27}, {"EQT-0072", 1.42, -0.27}, {"EQT-0070", 1.38, -0.26}, {"EQT-0010", 1.33, -0.25}]},
  {"2026-04-01", [{"EQT-0104", 1.40, -0.26}, {"EQT-0103", 1.41, -0.26}, {"EQT-0074", 1.41, -0.26}, {"EQT-0072", 1.42, -0.26}, {"EQT-0070", 1.38, -0.26}, {"EQT-0010", 1.33, -0.25}]},
  {"2026-05-01", [{"EQT-0104", 1.40, -0.26}, {"EQT-0103", 1.41, -0.26}, {"EQT-0074", 1.41, -0.26}, {"EQT-0072", 1.42, -0.26}, {"EQT-0070", 1.38, -0.26}, {"EQT-0010", 1.33, -0.25}]},
  {"2026-06-01", [{"EQT-0104", 1.40, -0.26}, {"EQT-0103", 1.41, -0.26}, {"EQT-0074", 1.41, -0.26}, {"EQT-0072", 1.42, -0.26}, {"EQT-0070", 1.38, -0.26}, {"EQT-0010", 1.33, -0.25}]},
  {"2026-07-01", [{"EQT-0104", 1.40, -0.26}, {"EQT-0103", 1.41, -0.26}, {"EQT-0074", 1.41, -0.26}, {"EQT-0072", 1.42, -0.26}, {"EQT-0070", 1.38, -0.26}, {"EQT-0010", 1.33, -0.25}]}
]

now = DateTime.utc_now()

purchase_docs =
  Enum.map(purchases, fn {date, code} ->
    %{date: date, code: code, kind: "purchase", tokens: 2, amount: -200.00, raw_label: "COMPRA"}
  end)

reward_docs =
  Enum.map(rewards, fn {date, amount} ->
    %{date: date, code: nil, kind: "reward", tokens: nil, amount: amount, raw_label: "RECOMPENSA"}
  end)

distribution_docs =
  Enum.flat_map(distributions, fn {date, rows} ->
    Enum.flat_map(rows, fn {code, renta, retencion} ->
      [
        %{date: date, code: code, kind: "rent", tokens: 2, amount: renta, raw_label: "RENTA"},
        %{date: date, code: code, kind: "tax", tokens: 2, amount: retencion, raw_label: "RET. FISCAL"}
      ]
    end)
  end)

Enum.each(properties, &EquitoProperties.upsert/1)
IO.puts("#{length(properties)} properties upserted")

{new, seen} =
  (purchase_docs ++ reward_docs ++ distribution_docs)
  |> Enum.split_with(&is_nil(EquitoTransactions.find_matching(&1)))

:ok = EquitoTransactions.insert_many(Enum.map(new, &Map.put(&1, :captured_at, now)))

IO.puts("#{length(new)} movements inserted, #{length(seen)} already recorded")

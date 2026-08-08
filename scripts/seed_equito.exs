# Seeds Equito from the app's screenshots — properties from "Mis propiedades",
# movements from "Historial".
#
#     mix run scripts/seed_equito.exs
#
# Safe to re-run: properties upsert by code, and each movement is checked
# against its natural key (date + code + kind + amount) before insert, so
# overlapping screenshots top the ledger up instead of duplicating it.
#
# All six purchases are confirmed from the per-property detail screens.
# Two gaps remain in the rent stream, so the distributions still understate
# what has actually been paid out:
#
#   * August 2025 — EQT-0070 and EQT-0072 were both letting by then, but the
#     Historial screenshots jump from July to September
#   * August 2026 — the detail screens show the net (EQT-0010 1.08 €,
#     0070 1.12, 0072 1.16, 0074 1.15, 0103 1.15, 0104 1.14) but not the
#     RENTA / RET. FISCAL split those nets come from
#
# April–May 2025 look genuinely empty rather than missing: each property's
# first rent trails its purchase by a couple of months, and the part-month
# amounts line up with a tenancy starting then (EQT-0070's 0.69 € in June,
# EQT-0010's 0.21 € after a 26/08 purchase).

alias Sheetfolio.{EquitoProperties, EquitoTransactions}

properties = [
  %{code: "EQT-0010", kind: "Apartment", surface_m2: 85, city: "Valencia", status: "Alquilado", yield_pct: 10.03, distributed_pct: 8.02},
  %{code: "EQT-0070", kind: "Apartment", surface_m2: 96, city: "Albal", status: "Alquilado", yield_pct: 9.22, distributed_pct: 8.32},
  %{code: "EQT-0072", kind: "Apartment", surface_m2: 94, city: "Alicante", status: "Alquilado", yield_pct: 9.87, distributed_pct: 8.54},
  %{code: "EQT-0074", kind: "Apartment", surface_m2: 86, city: "Alaquas", status: "Alquilado", yield_pct: 9.65, distributed_pct: 8.49},
  %{code: "EQT-0103", kind: "Apartment", surface_m2: 82, city: "Alicante", status: "Alquilado", yield_pct: 9.68, distributed_pct: 8.50},
  %{code: "EQT-0104", kind: "Apartment", surface_m2: 94, city: "Torrent", status: "Alquilado", yield_pct: 9.66, distributed_pct: 8.46}
]

# Every holding is 2 tokens at 100 €, dated from each property's detail screen.
purchases = [
  {"2025-03-13", "EQT-0070"},
  {"2025-03-20", "EQT-0072"},
  {"2025-03-27", "EQT-0074"},
  {"2025-08-25", "EQT-0103"},
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

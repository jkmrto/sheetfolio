# Seeds the Equito properties read off the "Mis propiedades" screenshots.
# Rentabilidad / Distribuido are Equito's own published figures, recorded as
# shown rather than recomputed.
#
#     mix run scripts/seed_equito.exs
#
# Upserts by code, so re-running after a fresh screenshot just refreshes the
# percentages. The Historial movements load separately, once the full history
# is captured, into `equito_transactions`.

alias Sheetfolio.EquitoProperties

properties = [
  %{code: "EQT-0010", kind: "Apartment", surface_m2: 85, city: "Valencia", status: "Alquilado", yield_pct: 10.03, distributed_pct: 8.02},
  %{code: "EQT-0070", kind: "Apartment", surface_m2: 96, city: "Albal", status: "Alquilado", yield_pct: 9.22, distributed_pct: 8.32},
  %{code: "EQT-0072", kind: "Apartment", surface_m2: 94, city: "Alicante", status: "Alquilado", yield_pct: 9.87, distributed_pct: 8.54},
  %{code: "EQT-0074", kind: "Apartment", surface_m2: 86, city: "Alaquas", status: "Alquilado", yield_pct: 9.65, distributed_pct: 8.49},
  %{code: "EQT-0103", kind: "Apartment", surface_m2: 82, city: "Alicante", status: "Alquilado", yield_pct: 9.68, distributed_pct: 8.50},
  %{code: "EQT-0104", kind: "Apartment", surface_m2: 94, city: "Torrent", status: "Alquilado", yield_pct: 9.66, distributed_pct: 8.46}
]

Enum.each(properties, fn property ->
  :ok = EquitoProperties.upsert(property)
  IO.puts("upserted #{property.code} — #{property.city}")
end)

IO.puts("\n#{length(properties)} properties in equito_properties")

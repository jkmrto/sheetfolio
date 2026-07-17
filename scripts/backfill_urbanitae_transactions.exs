defmodule BackfillUrbanitaeTransactions do
  @moduledoc """
  Seeds urbanitae_transactions from the initial batch of Movimientos
  screenshots (INVERSIÓN + REEMBOLSO only; ingresos/transferencias skipped).

  Dry-run by default — prints what would be inserted vs. skipped and stops.
  Pass `--commit` to actually write.

      set -a && . ./.env && set +a && mix run scripts/backfill_urbanitae_transactions.exs
      set -a && . ./.env && set +a && mix run scripts/backfill_urbanitae_transactions.exs --commit
  """

  alias Sheetfolio.UrbanitaeTransactions

  @rows [
    {"2024-05-23", :investment, "Valencia", "Montesano", 10_000.00},
    {"2024-10-02", :repayment, "Valencia", "Montesano", 10_614.25},
    {"2024-10-31", :investment, "Barcelona", "Golf Terraces", 5_000.00},
    {"2024-11-08", :investment, "Barcelona", "Soler i Cortada", 600.00},
    {"2024-11-21", :investment, "Oporto", "Julio Dinis", 5_000.00},
    {"2024-12-18", :investment, "Valencia", "Pérez Galdós", 5_000.00},
    {"2025-03-24", :investment, "Madrid", "Somosaguas", 5_000.00},
    {"2025-05-07", :repayment, "Valencia", "Pérez Galdós", 67.70},
    {"2025-05-13", :investment, "Estepona", "The Privilege", 1_000.00},
    {"2025-05-27", :investment, "Málaga", "El Higuerón TB65", 1_060.00},
    {"2025-07-28", :repayment, "Valencia", "Pérez Galdós", 81.25},
    {"2025-10-03", :repayment, "Barcelona", "Soler i Cortada", 123.07},
    {"2025-10-07", :repayment, "Barcelona", "Soler i Cortada", 123.07},
    {"2025-10-30", :repayment, "Valencia", "Pérez Galdós", 81.25},
    {"2025-10-31", :investment, "Málaga", "El Maro", 1_080.00},
    {"2026-01-28", :repayment, "Valencia", "Pérez Galdós", 81.25},
    {"2026-04-28", :repayment, "Valencia", "Pérez Galdós", 81.25},
    {"2026-07-13", :repayment, "Barcelona", "Golf Terraces", 5_851.95},
    {"2026-07-16", :investment, "Oporto", "Francos III", 1_000.00}
  ]

  def run(args) do
    commit? = "--commit" in args
    now = DateTime.utc_now()

    {to_insert, dupes} =
      @rows
      |> Enum.map(&build_doc(&1, now))
      |> Enum.split_with(&(UrbanitaeTransactions.find_matching(atom_keys(&1)) == nil))

    IO.puts("== Backfill plan ==")
    IO.puts("New:        #{length(to_insert)}")
    IO.puts("Duplicates: #{length(dupes)}")
    IO.puts("")
    Enum.each(to_insert, &print_row("+", &1))
    Enum.each(dupes, &print_row("=", &1))

    if commit? do
      :ok = UrbanitaeTransactions.insert_many(to_insert)
      total = length(UrbanitaeTransactions.all())
      IO.puts("\nInserted #{length(to_insert)} rows. Collection now has #{total} docs.")
    else
      IO.puts("\nDry run — pass --commit to write.")
    end
  end

  defp build_doc({date, kind, city, project, amount}, now) do
    kind_str = Atom.to_string(kind)

    %{
      date: date,
      kind: kind_str,
      city: city,
      project: project,
      project_key: UrbanitaeTransactions.project_key(city, project),
      amount: amount,
      raw_title: raw_title(kind, city, project),
      captured_at: now
    }
  end

  defp raw_title(:investment, city, project),
    do: "Inversión en el proyecto #{city} | Proyecto #{project}"

  defp raw_title(:repayment, city, project),
    do: "Reembolso #{city} | Proyecto #{project}"

  defp atom_keys(doc) do
    %{date: doc.date, kind: doc.kind, project_key: doc.project_key, amount: doc.amount}
  end

  defp print_row(marker, doc) do
    IO.puts(
      "#{marker} #{doc.date}  #{String.pad_trailing(doc.kind, 10)} " <>
        "#{String.pad_trailing(doc.city, 10)} #{String.pad_trailing(doc.project, 22)} " <>
        "#{:erlang.float_to_binary(doc.amount, decimals: 2)} €"
    )
  end
end

BackfillUrbanitaeTransactions.run(System.argv())

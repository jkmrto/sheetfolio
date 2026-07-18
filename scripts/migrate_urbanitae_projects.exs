defmodule MigrateUrbanitaeProjects do
  @moduledoc """
  One-shot migration to introduce project types and reclassify existing
  repayments after the schema change that added `project_type` and
  `repayment_kind`.

  Reads project types from the Urbanitae "Crowdfunding inmobiliario"
  overview screenshots. Reclassifies every existing repayment as `yield`
  by default, then flips the two known closure events (Montesano and
  Golf Terraces) to `principal`.

  Dry-run by default; pass `--commit` to write.

      set -a && . ./.env && set +a && mix run scripts/migrate_urbanitae_projects.exs
      set -a && . ./.env && set +a && mix run scripts/migrate_urbanitae_projects.exs --commit
  """

  alias Sheetfolio.{UrbanitaeProjects, UrbanitaeTransactions}

  # Types taken from Urbanitae's "En curso" / "Reembolsado" overview screenshots.
  # Closed projects (Montesano, Golf Terraces) aren't shown in "En curso" so
  # their type is my best guess from the short duration + return pattern; the
  # user can update via the ingest skill later.
  @projects [
    {"Barcelona", "Soler i Cortada", "plusvalia"},
    {"Oporto", "Julio Dinis", "plusvalia"},
    {"Málaga", "El Higuerón TB65", "plusvalia"},
    {"Oporto", "Francos III", "plusvalia"},
    {"Valencia", "Pérez Galdós", "alquiler"},
    {"Madrid", "Somosaguas", "prestamo"},
    {"Estepona", "The Privilege", "prestamo"},
    {"Málaga", "El Maro", "prestamo"},
    # Closed — inferred from repayment pattern; adjust if wrong.
    {"Valencia", "Montesano", "prestamo"},
    {"Barcelona", "Golf Terraces", "prestamo"}
  ]

  # Repayments that returned principal (project closure). Everything else
  # marked as yield.
  @principal_repayments [
    {"2024-10-02", "valencia-montesano", 10_614.25},
    {"2026-07-13", "barcelona-golf-terraces", 5_851.95}
  ]

  def run(args) do
    commit? = "--commit" in args

    IO.puts("== Projects to seed ==")

    project_docs =
      Enum.map(@projects, fn {city, project, type} ->
        %{
          project_key: UrbanitaeTransactions.project_key(city, project),
          city: city,
          project: project,
          type: type
        }
      end)

    Enum.each(project_docs, fn d ->
      IO.puts("  #{String.pad_trailing(d.type, 10)} #{d.city} | #{d.project}")
    end)

    IO.puts("\n== Repayments to mark as principal ==")

    principal_targets =
      Enum.map(@principal_repayments, fn {date, pk, amount} ->
        %{date: date, project_key: pk, amount: amount}
      end)

    Enum.each(principal_targets, fn t ->
      IO.puts("  #{t.date}  #{t.project_key}  #{:erlang.float_to_binary(t.amount, decimals: 2)}")
    end)

    IO.puts("\n(All other repayments become `yield`.)")

    if commit? do
      Enum.each(project_docs, &UrbanitaeProjects.upsert/1)

      set_all_repayments_to("yield")
      Enum.each(principal_targets, &UrbanitaeTransactions.set_repayment_kind(&1, "principal"))

      IO.puts("\nMigration applied.")
    else
      IO.puts("\nDry run — pass --commit to write.")
    end
  end

  # Bulk-set repayment_kind on every repayment doc.
  defp set_all_repayments_to(kind) do
    {:ok, %{modified_count: n}} =
      Mongo.update_many(
        :mongo,
        "urbanitae_transactions",
        %{"kind" => "repayment"},
        %{"$set" => %{"repayment_kind" => kind}}
      )

    IO.puts("Set repayment_kind=#{kind} on #{n} docs.")
  end
end

MigrateUrbanitaeProjects.run(System.argv())

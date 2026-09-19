defmodule Sheetfolio.UrbanitaeProjects do
  @moduledoc """
  Metadata for Urbanitae projects. One document per project, keyed by the
  same `project_key` used in `urbanitae_transactions`.

      { project_key: "valencia-perez-galdos",
        city: "Valencia",
        project: "Pérez Galdós",
        type: "alquiler",              # plusvalia | alquiler | prestamo
        status: "pending",             # optional: funded, investors not yet given entry
        captured_at: <DateTime> }

  Type drives how repayments are interpreted in the rollup: `alquiler` and
  `prestamo` repayments default to yield (interest / rent), `plusvalia`
  repayments are typically the closure and lean toward principal.

  `status: "pending"` marks a project whose round closed but which Urbanitae
  hasn't yet listed under "Mis inversiones" (the investor entry is still
  being formalized). The money is committed, so it counts as outstanding;
  the page only shows a different pill. Clear it with `status: nil`.
  """

  @collection "urbanitae_projects"
  @types ~w(plusvalia alquiler prestamo)

  def types, do: @types

  def all do
    Mongo.find(:mongo, @collection, %{}) |> Enum.to_list()
  end

  def by_key(project_key) do
    Mongo.find_one(:mongo, @collection, %{"project_key" => project_key})
  end

  @doc """
  Upsert by project_key. Preserves captured_at on the initial insert;
  updates city/project/type/status on subsequent calls.
  """
  def upsert(%{project_key: pk} = doc) do
    now = DateTime.utc_now()
    fields = doc |> Map.take([:city, :project, :type, :status]) |> Map.put(:updated_at, now)

    {:ok, _} =
      Mongo.update_one(:mongo, @collection, %{"project_key" => pk}, %{
        "$set" => fields,
        "$setOnInsert" => %{"project_key" => pk, "captured_at" => now}
      }, upsert: true)

    :ok
  end

  @doc """
  Returns `%{project_key => type_string}` for fast lookup during rollup.
  """
  def types_by_key do
    all()
    |> Enum.reduce(%{}, fn doc, acc -> Map.put(acc, doc["project_key"], doc["type"]) end)
  end

  @doc """
  Keys of the projects flagged `status: "pending"`.
  """
  def pending_keys do
    Mongo.find(:mongo, @collection, %{"status" => "pending"}, projection: %{project_key: 1})
    |> MapSet.new(& &1["project_key"])
  end
end

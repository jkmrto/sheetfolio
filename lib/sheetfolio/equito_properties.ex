defmodule Sheetfolio.EquitoProperties do
  @moduledoc """
  Metadata for the Equito properties, one document per property, keyed by the
  code the app shows ("EQT-0072"). Equito has no API, so these come from
  "Mis propiedades" screenshots.

      { code: "EQT-0072",
        kind: "Apartment",
        surface_m2: 94,
        city: "Alicante",
        status: "Alquilado",
        yield_pct: 9.87,               # "Rentabilidad" as the app shows it
        distributed_pct: 8.54,         # "Distribuido"
        captured_at: <DateTime> }

  `yield_pct` and `distributed_pct` are Equito's own figures, kept as
  published rather than recomputed: they're the projected gross yield and the
  share actually distributed so far, which the movement history alone can't
  reconstruct.
  """

  @collection "equito_properties"

  def all do
    Mongo.find(:mongo, @collection, %{}, sort: %{code: 1}) |> Enum.to_list()
  end

  def by_code(code) do
    Mongo.find_one(:mongo, @collection, %{"code" => code})
  end

  @doc """
  Upsert by code. Keeps captured_at from the first sighting.
  """
  def upsert(%{code: code} = doc) do
    now = DateTime.utc_now()

    fields =
      doc
      |> Map.take([:kind, :surface_m2, :city, :status, :yield_pct, :distributed_pct])
      |> Map.put(:updated_at, now)

    {:ok, _} =
      Mongo.update_one(
        :mongo,
        @collection,
        %{"code" => code},
        %{"$set" => fields, "$setOnInsert" => %{"code" => code, "captured_at" => now}},
        upsert: true
      )

    :ok
  end

  @doc """
  Returns `%{code => document}` for fast lookup while rolling up movements.
  """
  def by_code_map do
    all() |> Enum.reduce(%{}, fn doc, acc -> Map.put(acc, doc["code"], doc) end)
  end
end

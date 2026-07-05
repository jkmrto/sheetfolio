defmodule BackfillUrbanitae do
  @moduledoc """
  Adds the Urbanitae position (from the spreadsheet's invested balance and
  cumulative gain, carried forward) to every existing portfolio snapshot and
  recomputes the totals.

  Run with: set -a && . ./.env && set +a && mix run scripts/backfill_urbanitae.exs
  """

  @collection "portfolio_snapshots"

  def run do
    {:ok, history} = Sheetfolio.Urbanitae.fetch_history()

    docs = Mongo.find(:mongo, @collection, %{}, sort: %{date: 1}) |> Enum.to_list()
    IO.puts("Updating #{length(docs)} snapshots...")

    Enum.each(docs, fn doc ->
      date = Date.from_iso8601!(doc["date"])

      positions =
        Enum.reject(doc["positions"], &(&1["isin"] == "URBANITAE")) ++
          case Sheetfolio.Urbanitae.position_at(history, date) do
            nil -> []
            position -> [Map.new(position, fn {k, v} -> {Atom.to_string(k), v} end)]
          end

      valued = Enum.filter(positions, &(&1["value"] && &1["isin"] != "URBANITAE"))
      total_invested = Enum.reduce(valued, 0.0, &(&1["invested"] + &2)) |> Float.round(2)
      total_value = Enum.reduce(valued, 0.0, &(&1["value"] + &2)) |> Float.round(2)

      {:ok, _} =
        Mongo.update_one(:mongo, @collection, %{date: doc["date"]}, %{
          "$set" => %{
            positions: positions,
            total_invested: total_invested,
            total_value: total_value
          }
        })
    end)

    IO.puts("Done.")
  end
end

BackfillUrbanitae.run()

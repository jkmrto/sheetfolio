defmodule BackfillRealized do
  @moduledoc """
  Computes cumulative realized P&L per date from the operations history and
  stores it as total_realized on every existing portfolio snapshot.

  Run with: set -a && . ./.env && set +a && mix run scripts/backfill_realized.exs
  """

  @collection "portfolio_snapshots"

  def run do
    IO.puts("Loading operations (waits for the Gmail load to finish)...")
    operations = Sheetfolio.OperationsServer.get_operations(:infinity) || []
    {eur_usd, eur_cad} = Sheetfolio.EarningsServer.get_fx_rates()

    ops =
      operations
      |> Enum.map(&Map.put(&1, :date, parse_fecha(&1.fecha)))
      |> Enum.filter(& &1.date)

    docs =
      Mongo.find(:mongo, @collection, %{}, sort: %{date: 1}, projection: %{date: 1})
      |> Enum.to_list()

    IO.puts("Updating #{length(docs)} snapshots...")

    Enum.each(docs, fn doc ->
      date = Date.from_iso8601!(doc["date"])

      total_realized =
        ops
        |> Enum.filter(&(Date.compare(&1.date, date) != :gt))
        |> Sheetfolio.Positions.build(eur_usd, eur_cad)
        |> Map.values()
        |> Enum.reduce(0.0, &(&1.realized + &2))
        |> Float.round(2)

      {:ok, _} =
        Mongo.update_one(:mongo, @collection, %{date: doc["date"]}, %{
          "$set" => %{total_realized: total_realized}
        })
    end)

    IO.puts("Done.")
  end

  defp parse_fecha(fecha) do
    with [d, m, y] <- String.split(fecha, "/"),
         {day, _} <- Integer.parse(d),
         {month, _} <- Integer.parse(m),
         {year, _} <- Integer.parse(y),
         {:ok, date} <- Date.new(year, month, day) do
      date
    else
      _ -> nil
    end
  end
end

BackfillRealized.run()

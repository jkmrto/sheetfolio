defmodule RebuildPositionSnapshots do
  @moduledoc """
  Rebuilds one holding across the snapshots that are missing it, from the full
  operation history and the ISIN's own price series.

  Units and cost come from replaying every operation up to each snapshot date,
  so the position appears exactly for the dates it was held, at the cost basis
  the recorder would have written. Snapshots that already carry the ISIN are
  left alone, prices included.

  Run with: set -a && . ./.env && set +a && mix run scripts/rebuild_position_snapshots.exs ISIN
  Pass --dry-run to report what would change without writing.
  """

  alias Sheetfolio.{Positions, PriceFetcher}
  alias Sheetfolio.PricesApi.YahooFinance

  @collection "portfolio_snapshots"
  @run_up_days 14
  @closed_below 1.0e-6

  def run(isin, dry_run?) do
    operations =
      (Sheetfolio.OperationsServer.get_operations(:infinity) || [])
      |> Enum.filter(&(&1.isin == isin))

    docs = Mongo.find(:mongo, @collection, %{}, sort: %{date: 1}) |> Enum.to_list()
    [first | _] = docs
    from = first["date"] |> Date.from_iso8601!() |> Date.add(-@run_up_days)
    to = docs |> List.last() |> Map.fetch!("date") |> Date.from_iso8601!()

    IO.puts("#{isin}: #{length(operations)} operations, #{length(docs)} snapshots")

    prices = prices_for(isin, from, to)
    updated = docs |> Enum.map(&rebuild(&1, isin, operations, prices, dry_run?)) |> Enum.count(& &1)

    IO.puts(if dry_run?, do: "\nWould update #{updated} snapshots.", else: "\nUpdated #{updated} snapshots.")
  end

  defp rebuild(doc, isin, operations, prices, dry_run?) do
    already? = Enum.any?(doc["positions"] || [], &(&1["isin"] == isin))

    case {already?, position_at(doc, isin, operations, prices)} do
      {true, _} -> false
      {false, nil} -> false
      {false, entry} -> apply_entry(doc, entry, dry_run?)
    end
  end

  defp position_at(doc, isin, operations, prices) do
    asset =
      operations
      |> Enum.filter(&(iso_of(&1.fecha) <= doc["date"]))
      |> Positions.build(1.0, 1.0)
      |> Map.get(isin)

    with true <- asset != nil and asset.net_qty > @closed_below,
         price when not is_nil(price) <- price_at(prices, Date.from_iso8601!(doc["date"])) do
      %{
        "isin" => isin,
        "asset" => asset.asset,
        "units" => Float.round(asset.net_qty, 8),
        "invested" => Float.round(asset.cost_basis, 2),
        "value" => Float.round(asset.net_qty * price, 2),
        "stale_price" => false
      }
    else
      _unheld_or_unpriced -> nil
    end
  end

  defp apply_entry(doc, entry, dry_run?) do
    total_value = Float.round((doc["total_value"] || 0.0) + entry["value"], 2)
    total_invested = Float.round((doc["total_invested"] || 0.0) + entry["invested"], 2)

    if rem(:erlang.phash2(doc["date"]), 45) == 0 do
      IO.puts("  #{doc["date"]}  #{entry["units"]} units  value #{entry["value"]}  (total #{doc["total_value"]} -> #{total_value})")
    end

    unless dry_run? do
      {:ok, _} =
        Mongo.update_one(:mongo, @collection, %{"date" => doc["date"]}, %{
          "$set" => %{
            "positions" => (doc["positions"] || []) ++ [entry],
            "total_value" => total_value,
            "total_invested" => total_invested
          }
        })
    end

    true
  end

  defp prices_for(isin, from, to) do
    {:ok, ticker} = PriceFetcher.resolve_ticker(isin)
    {:ok, prices, currency} = YahooFinance.fetch_series(ticker, from, to)
    IO.puts("  #{ticker}: #{map_size(prices)} points #{currency}")

    if currency == "EUR", do: prices, else: raise("#{ticker} quotes in #{currency}, add a conversion")
  end

  defp price_at(prices, date) do
    prices
    |> Enum.filter(fn {price_date, _price} -> Date.compare(price_date, date) != :gt end)
    |> Enum.max_by(fn {price_date, _price} -> Date.to_erl(price_date) end, fn -> nil end)
    |> case do
      nil -> nil
      {_price_date, price} -> price
    end
  end

  defp iso_of(fecha) do
    [day, month, year] = String.split(fecha, "/")
    "#{year}-#{month}-#{day}"
  end
end

case System.argv() |> Enum.reject(&String.starts_with?(&1, "--")) do
  [isin] -> RebuildPositionSnapshots.run(isin, "--dry-run" in System.argv())
  _missing -> IO.puts("usage: mix run scripts/rebuild_position_snapshots.exs ISIN [--dry-run]")
end

defmodule BackfillTrading212Snapshots do
  @moduledoc """
  Adds the Trading212 holdings to the snapshots recorded while they were still
  open, and recomputes those snapshots' totals.

  Trading212 never emailed MyInvestor, so its operations reached the history
  only as `synthetic_operations`, and only after the daily recorder had already
  written most of the snapshot history. The positions were therefore missing
  from every snapshot they were open in: the past understated both value and
  cost basis, and the January 2026 liquidation showed up as money appearing
  from nowhere.

  Units and cost come from replaying the Trading212 operations as of each
  snapshot date — the same `Positions.build/3` the recorder uses — so a
  position appears exactly for the dates it was held. Prices come from each
  ISIN's own series, converted at the day's EUR/USD where the listing is in
  dollars, and carried forward over days the series doesn't publish.

  Run with: set -a && . ./.env && set +a && mix run scripts/backfill_trading212_snapshots.exs
  Pass --dry-run to report what would change without writing.
  """

  alias Sheetfolio.{Positions, PriceFetcher, SyntheticOperations}
  alias Sheetfolio.PricesApi.YahooFinance

  @collection "portfolio_snapshots"
  @fx_ticker "EURUSD=X"

  # Start the price series before the first snapshot so that day has a close to
  # carry forward. Without the run-up the earliest point available is the *next*
  # trading day, and the first snapshot silently gets a price from the future —
  # a fortnight covers New Year and any other market holiday.
  @run_up_days 14

  @doc """
  Takes the Trading212 positions back out, so a corrected run can put them
  back. The recorder never wrote these ISINs itself — they only ever reached a
  snapshot through this script — so removing every occurrence is safe.
  """
  def reset do
    isins = SyntheticOperations.trading212_isins()

    removed =
      Mongo.find(:mongo, @collection, %{}, sort: %{date: 1})
      |> Enum.to_list()
      |> Enum.map(&strip(&1, isins))
      |> Enum.count(& &1)

    IO.puts("Removed the Trading212 positions from #{removed} snapshots.\n")
  end

  defp strip(doc, isins) do
    {mine, theirs} = Enum.split_with(doc["positions"] || [], &(&1["isin"] in isins))

    if mine == [] do
      false
    else
      value = Enum.reduce(mine, 0.0, &((&1["value"] || 0.0) + &2))
      invested = Enum.reduce(mine, 0.0, &((&1["invested"] || 0.0) + &2))

      {:ok, _} =
        Mongo.update_one(:mongo, @collection, %{"date" => doc["date"]}, %{
          "$set" => %{
            "positions" => theirs,
            "total_value" => Float.round(doc["total_value"] - value, 2),
            "total_invested" => Float.round(doc["total_invested"] - invested, 2)
          }
        })

      true
    end
  end

  def run(dry_run?) do
    isins = SyntheticOperations.trading212_isins()
    operations = Enum.filter(SyntheticOperations.all(), &(&1.isin in isins))

    docs = Mongo.find(:mongo, @collection, %{}, sort: %{date: 1}) |> Enum.to_list()
    [first | _] = docs
    last = List.last(docs)
    from = first["date"] |> Date.from_iso8601!() |> Date.add(-@run_up_days)
    to = Date.from_iso8601!(last["date"])

    IO.puts("#{length(docs)} snapshots (#{first["date"]} → #{last["date"]})")

    held = held_isins(operations, docs)
    IO.puts("Trading212 ISINs open inside that window: #{inspect(MapSet.to_list(held))}")

    fx = series(@fx_ticker, from, to)
    prices = Map.new(held, &{&1, prices_for(&1, from, to, fx)})

    updated = docs |> Enum.map(&backfill(&1, operations, prices, dry_run?)) |> Enum.count(& &1)

    IO.puts(if dry_run?, do: "\nWould update #{updated} snapshots.", else: "\nUpdated #{updated} snapshots.")
  end

  # Only the ISINs actually held on at least one snapshot date are worth
  # pricing; the rest were liquidated before the history starts.
  defp held_isins(operations, docs) do
    docs
    |> Enum.flat_map(fn doc -> doc |> positions_at(operations) |> Enum.map(& &1.isin) end)
    |> MapSet.new()
  end

  # A fully sold position doesn't land on exactly zero units — subtracting the
  # sale from the purchase leaves float dust — so anything under a millionth of
  # a unit counts as closed rather than as a position worth 0.00 €.
  @closed_below 1.0e-6

  defp positions_at(doc, operations) do
    operations
    |> Enum.filter(&(iso_of(&1.fecha) <= doc["date"]))
    |> Positions.build(1.0, 1.0)
    |> Map.values()
    |> Enum.filter(&(&1.net_qty > @closed_below))
  end

  defp backfill(doc, operations, prices, dry_run?) do
    existing = MapSet.new(doc["positions"] || [], & &1["isin"])

    doc
    |> positions_at(operations)
    |> Enum.reject(&MapSet.member?(existing, &1.isin))
    |> Enum.map(&entry(&1, prices, doc["date"]))
    |> Enum.reject(&is_nil/1)
    |> case do
      [] -> false
      entries -> apply_entries(doc, entries, dry_run?)
    end
  end

  defp entry(asset, prices, date) do
    case prices |> Map.get(asset.isin, %{}) |> price_at(Date.from_iso8601!(date)) do
      nil ->
        nil

      price ->
        %{
          "isin" => asset.isin,
          "asset" => asset.asset,
          "units" => Float.round(asset.net_qty, 8),
          "invested" => Float.round(asset.cost_basis, 2),
          "value" => Float.round(asset.net_qty * price, 2),
          "stale_price" => false
        }
    end
  end

  defp apply_entries(doc, entries, dry_run?) do
    value = Enum.reduce(entries, 0.0, &(&1["value"] + &2))
    invested = Enum.reduce(entries, 0.0, &(&1["invested"] + &2))
    total_value = Float.round((doc["total_value"] || 0.0) + value, 2)
    total_invested = Float.round((doc["total_invested"] || 0.0) + invested, 2)

    report(doc, entries, total_value)

    unless dry_run? do
      {:ok, _} =
        Mongo.update_one(:mongo, @collection, %{"date" => doc["date"]}, %{
          "$set" => %{
            "positions" => (doc["positions"] || []) ++ entries,
            "total_value" => total_value,
            "total_invested" => total_invested
          }
        })
    end

    true
  end

  # A EUR listing is used as published; a dollar one is divided by the day's
  # EUR/USD, so the position is valued the way the rest of the portfolio is.
  defp prices_for(isin, from, to, fx) do
    {:ok, ticker} = PriceFetcher.resolve_ticker(isin)

    case YahooFinance.fetch_series(ticker, from, to) do
      {:ok, prices, "EUR"} ->
        IO.puts("  #{isin} #{ticker}: #{map_size(prices)} points EUR")
        prices

      {:ok, prices, currency} ->
        IO.puts("  #{isin} #{ticker}: #{map_size(prices)} points #{currency}, converting")
        Map.new(prices, fn {date, price} -> {date, price / rate_at(fx, date)} end)

      {:error, reason} ->
        IO.puts("  #{isin} #{ticker}: no series (#{inspect(reason)})")
        %{}
    end
  end

  defp series(ticker, from, to) do
    {:ok, prices, _currency} = YahooFinance.fetch_series(ticker, from, to)
    prices
  end

  defp rate_at(fx, date) do
    price_at(fx, date) || raise("no EUR/USD rate on or before #{date}")
  end

  # The most recent price on or before the date, so weekends and holidays carry
  # the last close forward; the earliest one for a date before the series
  # starts, rather than leaving the position unpriced.
  defp price_at(prices, _date) when map_size(prices) == 0, do: nil

  defp price_at(prices, date) do
    prices
    |> Enum.filter(fn {price_date, _price} -> Date.compare(price_date, date) != :gt end)
    |> Enum.max_by(fn {price_date, _price} -> Date.to_erl(price_date) end, fn -> nil end)
    |> case do
      nil -> prices |> Enum.min_by(fn {d, _p} -> Date.to_erl(d) end) |> elem(1)
      {_price_date, price} -> price
    end
  end

  defp iso_of(fecha) do
    [day, month, year] = String.split(fecha, "/")
    "#{year}-#{month}-#{day}"
  end

  # Every 45th day plus the first few, so a long run stays readable.
  defp report(doc, entries, total_value) do
    if rem(:erlang.phash2(doc["date"]), 45) == 0 or doc["date"] <= "2025-01-03" do
      names = Enum.map_join(entries, ", ", &"#{&1["asset"]} #{&1["value"]}")
      IO.puts("  #{doc["date"]}  +#{length(entries)}: #{names}  (total #{doc["total_value"]} -> #{total_value})")
    end
  end
end

if "--reset" in System.argv(), do: BackfillTrading212Snapshots.reset()
BackfillTrading212Snapshots.run("--dry-run" in System.argv())

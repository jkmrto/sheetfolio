defmodule BackfillCoinbaseSnapshots do
  @moduledoc """
  Adds the Coinbase BTC holding (COINBASE-BTC) to the snapshots recorded before
  the wallet was captured, and recomputes their totals.

  The coins were bought long before the snapshot history. The three purchases
  Coinbase lists are:

      2019/2020   0.00455811 BTC    38.05 €   (implied: the total minus the two
                                               buys the app's date filter still
                                               shows — a pre-2021 purchase)
      06/12/2021  0.00897     BTC  400.00 €
      25/06/2024  0.00666     BTC  388.08 €
      --------------------------------------
                  0.02018811  BTC  826.13 €

  So the position sat at its full 0.02018811 BTC / 826.13 € cost across the whole
  snapshot window. It only entered the daily snapshot when the wallet was
  captured on 2026-08-01, which showed as an 826 € step in the Bitcoin line — and
  as a phantom money-in on the comparison — rather than the coins it always was.
  Units and cost come from replaying the purchases as of each date; the value
  from the BTC-EUR series, carried forward over days it didn't publish.

  Run with: set -a && . ./.env && set +a && mix run scripts/backfill_coinbase_snapshots.exs
  Pass --dry-run to report what would change without writing.
  """

  alias Sheetfolio.PricesApi.YahooFinance

  @collection "portfolio_snapshots"
  @isin "COINBASE-BTC"
  @asset "BTC (COINBASE)"

  # {date, units, cost EUR}, accumulated up to a snapshot's date.
  @purchases [
    {"2019-06-01", 0.00455811, 38.05},
    {"2021-12-06", 0.00897, 400.00},
    {"2024-06-25", 0.00666, 388.08}
  ]

  def run(dry_run?) do
    docs = Mongo.find(:mongo, @collection, %{}, sort: %{date: 1}) |> Enum.to_list()
    [first | _] = docs
    last = List.last(docs)

    {:ok, prices, _currency} =
      YahooFinance.fetch_series(
        "BTC-EUR",
        Date.from_iso8601!(first["date"]),
        Date.from_iso8601!(last["date"])
      )

    IO.puts("#{map_size(prices)} BTC-EUR points, #{length(docs)} snapshots (#{first["date"]} → #{last["date"]})")

    updated = docs |> Enum.map(&backfill(&1, prices, dry_run?)) |> Enum.count(& &1)

    IO.puts(if dry_run?, do: "\nWould update #{updated} snapshots.", else: "\nUpdated #{updated} snapshots.")
  end

  # Snapshots recorded after the wallet was captured already hold the position,
  # so leave those and the price the recorder used alone.
  defp backfill(doc, prices, dry_run?) do
    if Enum.any?(doc["positions"] || [], &(&1["isin"] == @isin)),
      do: false,
      else: apply_position(doc, prices, dry_run?)
  end

  defp apply_position(doc, prices, dry_run?) do
    date = Date.from_iso8601!(doc["date"])

    case position_at(prices, date) do
      nil ->
        false

      position ->
        positions = (doc["positions"] || []) ++ [position]
        report(doc, position)
        unless dry_run?, do: write(doc["date"], positions)
        true
    end
  end

  defp position_at(prices, date) do
    {units, cost} = held_at(date)

    with true <- units > 0.0,
         price when not is_nil(price) <- price_at(prices, date) do
      %{
        "isin" => @isin,
        "asset" => @asset,
        "units" => Float.round(units, 8),
        "invested" => Float.round(cost, 2),
        "value" => Float.round(units * price, 2),
        "stale_price" => false
      }
    else
      _ -> nil
    end
  end

  # Cumulative units and cost of the purchases on or before the date.
  defp held_at(date) do
    @purchases
    |> Enum.filter(fn {d, _u, _c} -> Date.compare(Date.from_iso8601!(d), date) != :gt end)
    |> Enum.reduce({0.0, 0.0}, fn {_d, u, c}, {units, cost} -> {units + u, cost + c} end)
  end

  # The most recent BTC-EUR price on or before the date; the earliest one for a
  # snapshot that predates the series rather than leaving it unpriced.
  defp price_at(prices, date) do
    prices
    |> Enum.filter(fn {price_date, _price} -> Date.compare(price_date, date) != :gt end)
    |> Enum.max_by(fn {price_date, _price} -> Date.to_erl(price_date) end, fn -> nil end)
    |> case do
      nil -> earliest(prices)
      {_price_date, price} -> price
    end
  end

  defp earliest(prices) do
    prices
    |> Enum.min_by(fn {price_date, _price} -> Date.to_erl(price_date) end, fn -> nil end)
    |> case do
      nil -> nil
      {_price_date, price} -> price
    end
  end

  # Every 60th day, plus the first few, so a long run stays readable.
  defp report(doc, position) do
    if rem(:erlang.phash2(doc["date"]), 60) == 0 or doc["date"] <= "2025-01-05" do
      IO.puts(
        "  #{doc["date"]}  units #{position["units"]}  invested #{position["invested"]}" <>
          "  value #{position["value"]}" <>
          "  (total_value #{doc["total_value"]} -> #{Float.round(doc["total_value"] + position["value"], 2)})"
      )
    end
  end

  defp write(date, positions) do
    # Urbanitae is charted as its own line; totals track only market positions.
    valued = Enum.filter(positions, &(&1["value"] && &1["isin"] != "URBANITAE"))

    {:ok, _} =
      Mongo.update_one(:mongo, @collection, %{date: date}, %{
        "$set" => %{
          positions: positions,
          total_invested: valued |> Enum.reduce(0.0, &(&1["invested"] + &2)) |> Float.round(2),
          total_value: valued |> Enum.reduce(0.0, &(&1["value"] + &2)) |> Float.round(2)
        }
      })
  end
end

BackfillCoinbaseSnapshots.run("--dry-run" in System.argv())

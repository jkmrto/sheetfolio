defmodule BackfillSnapshots do
  @moduledoc """
  Backfills daily portfolio snapshots into MongoDB from @from until today.

  Fetches each asset's full daily close series once (Yahoo, Stooq fallback),
  rebuilds positions per day from the operations history, and upserts one
  document per date into portfolio_snapshots.

  Run with: set -a && . ./.env && set +a && mix run scripts/backfill_snapshots.exs
  """

  alias Sheetfolio.{Positions, PriceFetcher}
  alias Sheetfolio.PricesApi.{YahooFinance, Stooq}

  @from ~D[2025-01-01]
  @collection "portfolio_snapshots"
  # Carry a close forward at most this many days (weekends/holidays).
  @max_carry_days 10

  # Funds with no historical series anywhere: synthesize daily prices by geometric
  # interpolation from NAV + YTD/2025 returns (MyInvestor fact sheets, 2026-07-03).
  # iShares ERNE is not in the MyInvestor catalog (ETF): anchor is its price in the
  # 2026-07-05 snapshot, rates proxied from DWS (same category, RF Ultra Corto Plazo EUR).
  @synthetic %{
    "LU0080237943" => %{nav: 85.2, nav_date: ~D[2026-07-03], ytd: 1.24, y2025: 2.77},
    "LU0090865873" => %{nav: 478.5963, nav_date: ~D[2026-07-03], ytd: 0.94, y2025: 2.05},
    "IE000RHYOR04" => %{nav: 5.5865, nav_date: ~D[2026-07-05], ytd: 1.24, y2025: 2.77}
  }

  def run do
    to = Date.utc_today()

    IO.puts("Loading operations (waits for the Gmail load to finish)...")
    operations = Sheetfolio.OperationsServer.get_operations(:infinity) || []
    {eur_usd_now, eur_cad_now} = Sheetfolio.EarningsServer.get_fx_rates()

    ops =
      operations
      |> Enum.map(&Map.put(&1, :date, parse_fecha(&1.fecha)))
      |> Enum.filter(& &1.date)

    assets = ops |> Enum.map(&{&1.isin, &1.asset}) |> Enum.uniq_by(&elem(&1, 0))

    IO.puts("Fetching price series for #{length(assets)} assets (#{@from} → #{to})...")

    series_from = Date.add(@from, -@max_carry_days)

    series =
      Map.new(assets, fn {isin, name} ->
        s = fetch_series(isin, series_from, to)
        IO.puts("  #{name} (#{isin}): #{describe(s)}")
        {isin, s}
      end)

    fx_usd = fx_series("EURUSD=X", series_from, to)
    fx_cad = fx_series("EURCAD=X", series_from, to)

    dates = Date.range(@from, to)
    IO.puts("Writing #{Enum.count(dates)} daily snapshots...")

    Enum.each(Enum.with_index(dates, 1), fn {date, idx} ->
      write_snapshot(date, ops, series, fx_usd, fx_cad, eur_usd_now, eur_cad_now)
      if rem(idx, 50) == 0, do: IO.puts("  #{idx}/#{Enum.count(dates)} (#{date})")
    end)

    count = Mongo.count_documents!(:mongo, @collection, %{})
    IO.puts("Done. #{count} documents in #{@collection}.")
  end

  defp write_snapshot(date, ops, series, fx_usd, fx_cad, eur_usd_now, eur_cad_now) do
    date_ops = Enum.filter(ops, &(Date.compare(&1.date, date) != :gt))

    position_docs =
      Positions.build(date_ops, eur_usd_now, eur_cad_now)
      |> Map.values()
      |> Enum.filter(&(&1.net_qty > 0.001 and &1.cost_basis > 0))
      |> Enum.map(fn p ->
        value =
          case price_at(series[p.isin], date) do
            nil -> nil
            {price, currency} -> Float.round(p.net_qty * to_eur(price, currency, date, fx_usd, fx_cad), 2)
          end

        %{
          isin: p.isin,
          asset: p.asset,
          units: p.net_qty,
          invested: Float.round(p.cost_basis, 2),
          value: value
        }
      end)

    valued = Enum.filter(position_docs, & &1.value)
    total_invested = Enum.reduce(valued, 0.0, &(&1.invested + &2)) |> Float.round(2)
    total_value = Enum.reduce(valued, 0.0, &(&1.value + &2)) |> Float.round(2)

    doc = %{
      date: Date.to_iso8601(date),
      recorded_at: DateTime.utc_now(),
      total_invested: total_invested,
      total_value: total_value,
      positions: position_docs
    }

    {:ok, _} =
      Mongo.update_one(:mongo, @collection, %{date: doc.date}, %{"$set" => doc}, upsert: true)
  end

  defp fetch_series("Bitcoin", from, to), do: yahoo_series("BTC-USD", from, to)

  defp fetch_series(isin, from, to) when is_map_key(@synthetic, isin),
    do: {synthetic_series(@synthetic[isin], from, to), "EUR"}

  defp fetch_series(isin, from, to) do
    yahoo =
      case PriceFetcher.resolve_ticker(isin) do
        {:ok, ticker} -> yahoo_series(ticker, from, to)
        _ -> nil
      end

    yahoo || stooq_series(isin, from, to)
  end

  defp yahoo_series(ticker, from, to) do
    case YahooFinance.fetch_series(ticker, from, to) do
      {:ok, map, currency} when map_size(map) > 0 -> {map, currency}
      _ -> nil
    end
  end

  defp stooq_series(isin, from, to) do
    with ticker when not is_nil(ticker) <- PriceFetcher.stooq_ticker(isin),
         {:ok, map, currency} <- Stooq.fetch_series(ticker, from, to) do
      {map, currency}
    else
      _ -> nil
    end
  end

  defp synthetic_series(%{nav: nav, nav_date: nav_date, ytd: ytd, y2025: y2025}, from, to) do
    nav_dec25 = nav / (1 + ytd / 100)
    nav_dec24 = nav_dec25 / (1 + y2025 / 100)
    ytd_days = Date.diff(nav_date, ~D[2025-12-31])

    Map.new(Date.range(from, to), fn date ->
      price =
        if Date.compare(date, ~D[2025-12-31]) == :gt do
          nav_dec25 * :math.pow(1 + ytd / 100, Date.diff(date, ~D[2025-12-31]) / ytd_days)
        else
          nav_dec24 * :math.pow(1 + y2025 / 100, Date.diff(date, ~D[2024-12-31]) / 365)
        end

      {date, price}
    end)
  end

  defp fx_series(pair, from, to) do
    case yahoo_series(pair, from, to) do
      {map, _} -> map
      nil -> %{}
    end
  end

  defp price_at(nil, _date), do: nil

  defp price_at({map, currency}, date) do
    Enum.find_value(0..@max_carry_days, fn back ->
      case Map.get(map, Date.add(date, -back)) do
        nil -> nil
        price -> {price, currency}
      end
    end)
  end

  defp to_eur(price, "USD", date, fx_usd, _fx_cad), do: price / fx_at(fx_usd, date)
  defp to_eur(price, "CAD", date, _fx_usd, fx_cad), do: price / fx_at(fx_cad, date)
  defp to_eur(price, _currency, _date, _fx_usd, _fx_cad), do: price

  defp fx_at(map, date) do
    Enum.find_value(0..@max_carry_days, 1.0, fn back ->
      Map.get(map, Date.add(date, -back))
    end)
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

  defp describe(nil), do: "NO DATA — values will be blank"
  defp describe({map, currency}), do: "#{map_size(map)} closes (#{currency})"
end

BackfillSnapshots.run()

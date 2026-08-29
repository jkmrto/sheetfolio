defmodule Sheetfolio.SnapshotRecorder do
  @moduledoc """
  Records a daily portfolio snapshot (per-position valuations) into MongoDB.
  Runs once shortly after boot, then daily at 22:00 UTC. Upserts by date, so
  same-day re-runs refresh that day's document.
  """
  use GenServer

  require Logger

  alias Sheetfolio.CryptoHoldings
  alias Sheetfolio.PricesApi.YahooFinance

  @collection "portfolio_snapshots"
  @daily_hour_utc 22
  @repair_days 30

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, nil, name: __MODULE__)
  end

  def record_now, do: GenServer.call(__MODULE__, :record, :infinity)

  @impl true
  def init(nil) do
    Mongo.create_indexes(:mongo, @collection, [
      %{key: %{date: 1}, name: "date_unique", unique: true}
    ])

    send(self(), :record)
    {:ok, nil}
  end

  @impl true
  def handle_info(:record, state) do
    record()
    Process.send_after(self(), :record, ms_until_next_run())
    {:noreply, state}
  end

  @impl true
  def handle_call(:record, _from, state) do
    {:reply, record(), state}
  end

  defp record do
    operations = Sheetfolio.OperationsServer.get_operations(:infinity) || []
    {eur_usd, eur_cad} = Sheetfolio.EarningsServer.get_fx_rates()

    assets = Sheetfolio.Positions.build(operations, eur_usd, eur_cad) |> Map.values()

    # Cumulative realized P&L, including fully settled positions.
    total_realized = Enum.reduce(assets, 0.0, &(&1.realized + &2)) |> Float.round(2)

    positions = Enum.filter(assets, &(&1.net_qty > 0.001 and &1.cost_basis > 0))

    prices =
      positions
      |> Map.new(&{&1.isin, &1.isin})
      |> Sheetfolio.PriceFetcher.fetch_prices()

    carry_forward = previous_prices()

    position_docs =
      Enum.map(positions, &position_doc(&1, prices, carry_forward)) ++
        crypto_positions(carry_forward)

    warn_about_stale_prices(position_docs)

    position_docs = position_docs ++ urbanitae_positions()

    # Urbanitae is charted as its own line; totals track only market positions.
    valued = Enum.filter(position_docs, &(&1.value && &1.isin != "URBANITAE"))
    total_invested = Enum.reduce(valued, 0.0, &(&1.invested + &2)) |> Float.round(2)
    total_value = Enum.reduce(valued, 0.0, &(&1.value + &2)) |> Float.round(2)

    date = Date.utc_today() |> Date.to_iso8601()

    doc = %{
      date: date,
      recorded_at: DateTime.utc_now(),
      total_invested: total_invested,
      total_value: total_value,
      total_realized: total_realized,
      partial: Enum.any?(position_docs, &(&1[:stale_price] || is_nil(&1.value))),
      positions: position_docs
    }

    case Mongo.update_one(:mongo, @collection, %{date: date}, %{"$set" => doc}, upsert: true) do
      {:ok, _} ->
        Logger.info("SnapshotRecorder: recorded #{date} (#{length(position_docs)} positions)")
        repair_recent(operations, {eur_usd, eur_cad})
        {:ok, doc}

      {:error, reason} = err ->
        Logger.error("SnapshotRecorder: failed to record #{date}: #{inspect(reason)}")
        err
    end
  end

  # A confirmation email that arrives days after the order leaves the snapshots
  # written in between short of the purchase, which then reads as money in on
  # the day the email landed. Now that the operation is known, fill them.
  defp repair_recent(operations, rates) do
    since = Date.utc_today() |> Date.add(-@repair_days)

    case Sheetfolio.SnapshotRepair.repair(operations, rates, since: since) do
      [] ->
        :ok

      changes ->
        dates = changes |> Enum.map(& &1.date) |> Enum.uniq() |> length()
        Logger.info("SnapshotRecorder: filled #{length(changes)} late-confirmed positions across #{dates} snapshots")
    end
  end

  defp position_doc(position, prices, carry_forward) do
    {value, stale} =
      position_value(
        position.net_qty,
        Map.get(prices, position.isin),
        Map.get(carry_forward, position.isin)
      )

    %{
      isin: position.isin,
      asset: position.asset,
      units: position.net_qty,
      invested: Float.round(position.cost_basis, 2),
      value: value,
      stale_price: stale
    }
  end

  @doc """
  A position's value as `{value, price_was_carried_forward?}`, given today's
  price and the previous snapshot's per-unit price. Falls back to the previous
  price when today's quote is missing, and to nothing when neither exists.
  """
  def position_value(_qty, nil, nil), do: {nil, false}
  def position_value(qty, nil, previous_price), do: {Float.round(qty * previous_price, 2), true}
  def position_value(qty, price, _previous), do: {Float.round(qty * price, 2), false}

  # Per-unit prices from the most recent earlier snapshot. Without this, a
  # transient Yahoo failure drops the position out of the day's totals entirely
  # and leaves a permanent fake dip in the portfolio chart.
  defp previous_prices do
    today = Date.utc_today() |> Date.to_iso8601()
    query = %{date: %{"$lt" => today}}

    case Mongo.find_one(:mongo, @collection, query, sort: %{date: -1}) do
      nil -> %{}
      doc -> unit_prices(doc["positions"] || [])
    end
  end

  @doc "Per-unit prices from a stored snapshot's position list."
  def unit_prices(positions) do
    positions
    |> Enum.filter(&(&1["value"] && &1["units"] && &1["units"] > 0))
    |> Map.new(&{&1["isin"], &1["value"] / &1["units"]})
  end

  defp warn_about_stale_prices(position_docs) do
    case Enum.filter(position_docs, & &1.stale_price) do
      [] -> :ok
      stale -> Logger.warning("SnapshotRecorder: no quote for #{Enum.map_join(stale, ", ", & &1.isin)}, carried forward the previous snapshot's price")
    end
  end

  # Coins held on an exchange have no ISIN and no operation history, so they
  # can't come through Positions: the cost basis is captured from the exchange
  # and the value is quoted live against the coin's EUR pair. Unlike Urbanitae
  # these are ordinary market positions, so they do count in the day's
  # invested/value totals.
  defp crypto_positions(carry_forward) do
    Enum.map(CryptoHoldings.all(), &crypto_position_doc(&1, carry_forward))
  end

  defp crypto_position_doc(holding, carry_forward) do
    isin = crypto_isin(holding["platform"], holding["symbol"])

    {value, stale} =
      position_value(
        holding["units"] * 1.0,
        spot_price(holding["symbol"]),
        Map.get(carry_forward, isin)
      )

    %{
      isin: isin,
      asset: "#{String.upcase(holding["symbol"])} (#{String.upcase(holding["platform"])})",
      units: holding["units"] * 1.0,
      invested: Float.round(holding["cost_basis"] * 1.0, 2),
      value: value,
      stale_price: stale
    }
  end

  @doc "Synthetic identifier for an exchange holding, e.g. `COINBASE-BTC`."
  def crypto_isin(platform, symbol), do: String.upcase("#{platform}-#{symbol}")

  defp spot_price(symbol) do
    case YahooFinance.fetch_price("#{symbol}-EUR") do
      {:ok, price, "EUR"} -> price
      _ -> nil
    end
  end

  # Urbanitae has no market price: the position is the capital still committed
  # to open projects, which the transaction ledger tracks. Yield that has been
  # repaid has left Urbanitae and shows up as cash, so counting it here — as
  # the spreadsheet's invested-plus-gains figure used to — overstates property
  # and double-counts it against the cash snapshot.
  defp urbanitae_positions do
    {outstanding, _earnings} =
      Sheetfolio.UrbanitaeTransactions.all()
      |> Sheetfolio.UrbanitaeTransactions.state_at(Date.to_iso8601(Date.utc_today()))

    urbanitae_position(Float.round(outstanding, 2))
  end

  defp urbanitae_position(outstanding) when outstanding > 0 do
    [
      %{
        isin: "URBANITAE",
        asset: "Urbanitae",
        units: 1.0,
        invested: outstanding,
        value: outstanding,
        stale_price: false
      }
    ]
  end

  defp urbanitae_position(_outstanding), do: []

  defp ms_until_next_run do
    now = DateTime.utc_now()
    today_run = %{now | hour: @daily_hour_utc, minute: 0, second: 0, microsecond: {0, 6}}

    next_run =
      if DateTime.compare(now, today_run) == :lt do
        today_run
      else
        DateTime.add(today_run, 1, :day)
      end

    DateTime.diff(next_run, now, :millisecond)
  end
end

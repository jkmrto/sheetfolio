defmodule Sheetfolio.SnapshotRecorder do
  @moduledoc """
  Records a daily portfolio snapshot (per-position valuations) into MongoDB.
  Runs once shortly after boot, then daily at 22:00 UTC. Upserts by date, so
  same-day re-runs refresh that day's document.
  """
  use GenServer

  require Logger

  @collection "portfolio_snapshots"
  @daily_hour_utc 22

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
    position_docs = Enum.map(positions, &position_doc(&1, prices, carry_forward))
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
        {:ok, doc}

      {:error, reason} = err ->
        Logger.error("SnapshotRecorder: failed to record #{date}: #{inspect(reason)}")
        err
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

  defp urbanitae_positions do
    with {:ok, history} <- Sheetfolio.Urbanitae.fetch_history(),
         position when not is_nil(position) <-
           Sheetfolio.Urbanitae.position_at(history, Date.utc_today()) do
      [position]
    else
      nil ->
        []

      {:error, reason} ->
        Logger.warning("SnapshotRecorder: Urbanitae sheet read failed: #{inspect(reason)}")
        []
    end
  end

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

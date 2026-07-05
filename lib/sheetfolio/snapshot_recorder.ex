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

    Mongo.create_indexes(:mongo, @collection, [
      %{key: %{date: 1}, name: "date_unique", unique: true}
    ])

    positions =
      Sheetfolio.Positions.build(operations, eur_usd, eur_cad)
      |> Map.values()
      |> Enum.filter(&(&1.net_qty > 0.001 and &1.cost_basis > 0))

    prices =
      positions
      |> Map.new(&{&1.isin, &1.isin})
      |> Sheetfolio.PriceFetcher.fetch_prices()

    position_docs =
      Enum.map(positions, fn p ->
        value =
          case Map.get(prices, p.isin) do
            nil -> nil
            price -> Float.round(p.net_qty * price, 2)
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

    date = Date.utc_today() |> Date.to_iso8601()

    doc = %{
      date: date,
      recorded_at: DateTime.utc_now(),
      total_invested: total_invested,
      total_value: total_value,
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

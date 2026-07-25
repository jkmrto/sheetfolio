defmodule Sheetfolio.CashRecorder do
  @moduledoc """
  Records a daily cash snapshot into MongoDB. Wise's balance is fetched live
  and recorded automatically every day; the other sources (typed in by hand
  on /cash) are carried forward unchanged from the previous day until the
  user updates them there. Runs once shortly after boot, then daily at
  21:00 UTC — an hour before SnapshotRecorder, so the two don't contend for
  Mongo/EarningsServer at the same moment. Upserts by date, so same-day
  re-runs refresh that day's document.
  """
  use GenServer

  require Logger

  alias Sheetfolio.WiseBalance

  @collection "cash_snapshots"
  @daily_hour_utc 21
  @wise_source "Wise"

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
    {sources, wise_stale} = with_wise_balance(previous_sources())
    date = Date.utc_today() |> Date.to_iso8601()

    doc = %{
      date: date,
      recorded_at: DateTime.utc_now(),
      total: sources |> Enum.map(& &1.amount) |> Enum.sum() |> Float.round(2),
      sources: sources,
      wise_stale: wise_stale
    }

    case Mongo.update_one(:mongo, @collection, %{date: date}, %{"$set" => doc}, upsert: true) do
      {:ok, _} ->
        Logger.info("CashRecorder: recorded #{date} (#{length(sources)} sources)")
        {:ok, doc}

      {:error, reason} = err ->
        Logger.error("CashRecorder: failed to record #{date}: #{inspect(reason)}")
        err
    end
  end

  defp with_wise_balance(previous_sources) do
    case WiseBalance.current_eur() do
      {:ok, amount} ->
        {put_source(previous_sources, @wise_source, amount), false}

      {:error, reason} ->
        Logger.warning("CashRecorder: could not fetch Wise balance: #{inspect(reason)}")
        {previous_sources, true}
    end
  end

  @doc "Replaces `name`'s amount in `sources`, or appends it if not present yet."
  def put_source(sources, name, amount) do
    if Enum.any?(sources, &(&1.name == name)) do
      Enum.map(sources, &replace_source(&1, name, amount))
    else
      sources ++ [%{name: name, amount: amount}]
    end
  end

  defp replace_source(%{name: name}, name, amount), do: %{name: name, amount: amount}
  defp replace_source(source, _name, _amount), do: source

  defp previous_sources do
    case Mongo.find_one(:mongo, @collection, %{}, sort: %{date: -1}) do
      nil -> []
      doc -> Enum.map(doc["sources"] || [], &%{name: &1["name"], amount: &1["amount"]})
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

defmodule Sheetfolio.UrbanitaeEmailSync do
  @moduledoc """
  Keeps the Urbanitae email cache current: once shortly after boot, then daily
  at 23:00 UTC. Only unseen message ids are downloaded, so a run is normally
  two Gmail listing requests and nothing else.

  Syncing is all it does. What the new mail implies lives in
  `Sheetfolio.UrbanitaePending`, which derives the gaps on read — so the
  `/urbanitae` banner reflects the last sync without this server having to
  push anything.
  """
  use GenServer

  require Logger

  alias Sheetfolio.UrbanitaeEmails

  @daily_hour_utc 23

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, nil, name: __MODULE__)
  end

  def sync_now, do: GenServer.call(__MODULE__, :sync, :infinity)

  @impl true
  def init(nil) do
    send(self(), :sync)
    {:ok, nil}
  end

  @impl true
  def handle_info(:sync, state) do
    sync()
    Process.send_after(self(), :sync, ms_until_next_run())
    {:noreply, state}
  end

  @impl true
  def handle_call(:sync, _from, state) do
    {:reply, sync(), state}
  end

  defp sync do
    case UrbanitaeEmails.sync() do
      {:ok, events} ->
        pending = length(Sheetfolio.UrbanitaePending.list())
        Logger.info("[UrbanitaeEmailSync] #{length(events)} events, #{pending} pending")
        {:ok, events}

      {:error, reason} ->
        Logger.warning("[UrbanitaeEmailSync] Sync failed: #{inspect(reason)}")
        {:error, reason}
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

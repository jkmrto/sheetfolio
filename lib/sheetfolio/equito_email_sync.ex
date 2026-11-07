defmodule Sheetfolio.EquitoEmailSync do
  @moduledoc """
  Runs `Sheetfolio.EquitoEmails.sync/0` shortly after boot, then daily at
  12:00 UTC — Equito pays on the 1st and mails the summary that morning.
  """
  use GenServer

  require Logger

  alias Sheetfolio.JobRuns

  @daily_hour_utc 12

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, nil, name: __MODULE__)
  end

  @impl true
  def init(nil) do
    send(self(), :sync)
    {:ok, nil}
  end

  @impl true
  def handle_info(:sync, state) do
    log(Sheetfolio.EquitoEmails.sync())
    Process.send_after(self(), :sync, ms_until_next_run())
    {:noreply, state}
  end

  defp log({:ok, inserted}) do
    Logger.info("[EquitoEmailSync] #{inserted} movements inserted")
    JobRuns.success("equito_emails")
  end

  defp log({:error, reason}) do
    Logger.warning("[EquitoEmailSync] Sync failed: #{inspect(reason)}")
    JobRuns.failure("equito_emails", reason)
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

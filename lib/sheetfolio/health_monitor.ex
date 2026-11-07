defmodule Sheetfolio.HealthMonitor do
  @moduledoc """
  Keeps the overall `DataHealth` status at hand, so every page can mark the
  gear icon without querying Mongo. Checks an hour after each previous check,
  starting a few minutes after boot to give the boot-time syncs a chance to run.
  """
  use GenServer

  alias Sheetfolio.DataHealth

  @first_check_ms 5 * 60 * 1000
  @check_ms 60 * 60 * 1000
  @key {__MODULE__, :status}

  def start_link(_opts), do: GenServer.start_link(__MODULE__, nil, name: __MODULE__)

  @doc "The worst status from the latest check. `:ok` until the first one lands."
  def status, do: :persistent_term.get(@key, :ok)

  @doc "Publishes a report that was just computed, so the gear doesn't lag behind it."
  def publish(rows) do
    worst = DataHealth.worst(rows)
    if status() != worst, do: :persistent_term.put(@key, worst)
    rows
  end

  @impl true
  def init(nil) do
    Process.send_after(self(), :check, @first_check_ms)
    {:ok, nil}
  end

  @impl true
  def handle_info(:check, state) do
    publish(DataHealth.report())
    Process.send_after(self(), :check, @check_ms)
    {:noreply, state}
  end
end

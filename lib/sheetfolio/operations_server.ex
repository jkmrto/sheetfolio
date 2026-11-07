defmodule Sheetfolio.OperationsServer do
  @moduledoc """
  Serves the operation history.

  When the Mongo email cache already has documents, boot reads and parses those
  and is ready straight away, then checks Gmail for new messages in the
  background. Only a genuinely empty cache falls back to blocking on a full
  Gmail load (the `/loading` page).

  If Gmail can't be reached, whatever the cache last held keeps being served
  rather than the history collapsing to an empty list.
  """
  use GenServer
  require Logger

  # Half an hour before SnapshotRecorder, so the day's snapshot sees new operations.
  @daily_hour_utc 21
  @daily_minute_utc 30

  alias Sheetfolio.HistoricalFx
  alias Sheetfolio.HoldingsCheck
  alias Sheetfolio.JobRuns
  alias Sheetfolio.MyinvestorEmails
  alias Sheetfolio.MyinvestorEmailStore
  alias Sheetfolio.OperationHistory
  alias Sheetfolio.Positions

  def start_link(_), do: GenServer.start_link(__MODULE__, nil, name: __MODULE__)

  def get_operations(timeout \\ 120_000), do: GenServer.call(__MODULE__, :get_operations, timeout)
  def get_status, do: GenServer.call(__MODULE__, :get_status)
  def reload, do: GenServer.cast(__MODULE__, :reload)

  def init(_) do
    state = %{status: :loading, operations: [], current: 0, total: 0, pending: [], syncing: false}
    schedule_daily_sync()
    {:ok, state, {:continue, :load}}
  end

  def handle_continue(:load, state) do
    {:noreply, boot(MyinvestorEmailStore.count(), state)}
  end

  defp boot(0, state) do
    Logger.info("[OperationsServer] Email cache empty, loading everything from Gmail")
    sync(state)
  end

  defp boot(cached, state) do
    operations = MyinvestorEmails.cached_operations() |> OperationHistory.patch() |> HistoricalFx.attach_stored()
    Logger.info("[OperationsServer] Serving #{length(operations)} operations from #{cached} cached emails")

    %{state | status: boot_status(operations), operations: operations} |> sync()
  end

  # Serving before the sync has fetched a missing rate would let the boot
  # snapshot convert those operations at today's rate.
  defp boot_status(operations) do
    if Positions.unpinned(operations) == [], do: :ready, else: :loading
  end

  # Everything here is network, so it runs in the sync's task: a slow Yahoo or
  # Sheets must not hold up this process, which every page calls.
  defp load(progress) do
    with {:ok, operations} <- MyinvestorEmails.sync(progress) do
      history = operations |> OperationHistory.patch() |> HistoricalFx.refresh()
      HoldingsCheck.run(history)
      {:ok, history}
    end
  end

  defp sync(state) do
    server = self()

    Task.start(fn ->
      progress = fn current, total -> send(server, {:progress, current, total}) end
      send(server, {:load_done, load(progress)})
    end)

    %{state | syncing: true}
  end

  def handle_info({:progress, current, total}, state) do
    {:noreply, %{state | current: current, total: total}}
  end

  def handle_info(:daily_sync, state) do
    schedule_daily_sync()
    GenServer.cast(self(), :reload)
    {:noreply, state}
  end

  def handle_info({:load_done, {:ok, ops}}, state) do
    JobRuns.success("myinvestor_emails")
    Enum.each(state.pending, &GenServer.reply(&1, ops))
    {:noreply, %{state | status: :ready, operations: ops, pending: [], syncing: false}}
  end

  def handle_info({:load_done, {:error, reason}}, state) do
    Logger.error("[OperationsServer] Gmail sync failed: #{inspect(reason)}")
    JobRuns.failure("myinvestor_emails", reason)
    Enum.each(state.pending, &GenServer.reply(&1, state.operations))
    {:noreply, %{state | status: :ready, pending: [], syncing: false}}
  end

  def handle_call(:get_operations, _from, %{status: :ready, operations: ops} = state) do
    {:reply, ops, state}
  end

  def handle_call(:get_operations, from, %{status: :loading} = state) do
    {:noreply, %{state | pending: [from | state.pending]}}
  end

  def handle_call(:get_status, _from, %{status: :loading, current: c, total: t} = state) do
    {:reply, {:loading, c, t}, state}
  end

  def handle_call(:get_status, _from, %{status: :ready, syncing: true} = state) do
    {:reply, {:syncing, state.current, state.total}, state}
  end

  def handle_call(:get_status, _from, %{status: :ready} = state) do
    {:reply, :ready, state}
  end

  def handle_cast(:reload, %{status: :ready, syncing: false} = state) do
    {:noreply, sync(%{state | current: 0, total: 0})}
  end

  # Already loading or syncing — a second concurrent sync would try to store the
  # same new messages twice.
  def handle_cast(:reload, state), do: {:noreply, state}

  defp schedule_daily_sync, do: Process.send_after(self(), :daily_sync, ms_until_next_run())

  defp ms_until_next_run do
    now = DateTime.utc_now()
    today_run = %{now | hour: @daily_hour_utc, minute: @daily_minute_utc, second: 0, microsecond: {0, 6}}

    next_run =
      if DateTime.compare(now, today_run) == :lt do
        today_run
      else
        DateTime.add(today_run, 1, :day)
      end

    DateTime.diff(next_run, now, :millisecond)
  end
end

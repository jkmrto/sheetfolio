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

  alias Sheetfolio.MyinvestorEmails
  alias Sheetfolio.MyinvestorEmailStore
  alias Sheetfolio.OperationHistory

  def start_link(_), do: GenServer.start_link(__MODULE__, nil, name: __MODULE__)

  def get_operations(timeout \\ 120_000), do: GenServer.call(__MODULE__, :get_operations, timeout)
  def get_status, do: GenServer.call(__MODULE__, :get_status)
  def reload, do: GenServer.cast(__MODULE__, :reload)

  def init(_) do
    state = %{status: :loading, operations: [], current: 0, total: 0, pending: [], syncing: false}
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
    operations = OperationHistory.patch(MyinvestorEmails.cached_operations())
    Logger.info("[OperationsServer] Serving #{length(operations)} operations from #{cached} cached emails")

    %{state | status: :ready, operations: operations} |> sync()
  end

  defp sync(state) do
    server = self()

    Task.start(fn ->
      progress = fn current, total -> send(server, {:progress, current, total}) end
      send(server, {:load_done, MyinvestorEmails.sync(progress)})
    end)

    %{state | syncing: true}
  end

  def handle_info({:progress, current, total}, state) do
    {:noreply, %{state | current: current, total: total}}
  end

  def handle_info({:load_done, {:ok, ops}}, state) do
    ops = OperationHistory.patch(ops)
    Enum.each(state.pending, &GenServer.reply(&1, ops))
    {:noreply, %{state | status: :ready, operations: ops, pending: [], syncing: false}}
  end

  def handle_info({:load_done, {:error, reason}}, state) do
    Logger.error("[OperationsServer] Gmail sync failed: #{inspect(reason)}")
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
end

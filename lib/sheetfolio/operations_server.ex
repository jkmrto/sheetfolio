defmodule Sheetfolio.OperationsServer do
  use GenServer
  require Logger

  def start_link(_), do: GenServer.start_link(__MODULE__, nil, name: __MODULE__)

  def get_operations(timeout \\ 120_000), do: GenServer.call(__MODULE__, :get_operations, timeout)
  def get_status, do: GenServer.call(__MODULE__, :get_status)
  def reload, do: GenServer.cast(__MODULE__, :reload)

  def init(_) do
    state = %{status: :loading, operations: [], current: 0, total: 0, pending: []}
    {:ok, state, {:continue, :load}}
  end

  def handle_continue(:load, state) do
    server = self()

    Task.start(fn ->
      progress = fn current, total -> send(server, {:progress, current, total}) end
      result = Sheetfolio.MyinvestorEmails.fetch_all(progress)
      send(server, {:load_done, result})
    end)

    {:noreply, state}
  end

  def handle_info({:progress, current, total}, state) do
    {:noreply, %{state | current: current, total: total}}
  end

  def handle_info({:load_done, {:ok, ops}}, state) do
    ops = Sheetfolio.OperationHistory.patch(ops)
    Enum.each(state.pending, &GenServer.reply(&1, ops))
    {:noreply, %{state | status: :ready, operations: ops, pending: []}}
  end

  def handle_info({:load_done, {:error, reason}}, state) do
    Logger.error("[OperationsServer] Failed to load: #{inspect(reason)}")
    Enum.each(state.pending, &GenServer.reply(&1, []))
    {:noreply, %{state | status: :ready, operations: [], pending: []}}
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

  def handle_call(:get_status, _from, %{status: :ready} = state) do
    {:reply, :ready, state}
  end

  def handle_cast(:reload, %{status: :ready} = state) do
    server = self()

    Task.start(fn ->
      progress = fn current, total -> send(server, {:progress, current, total}) end
      result = Sheetfolio.MyinvestorEmails.fetch_all(progress)
      send(server, {:load_done, result})
    end)

    {:noreply, %{state | status: :loading, operations: [], current: 0, total: 0}}
  end

  def handle_cast(:reload, state), do: {:noreply, state}
end

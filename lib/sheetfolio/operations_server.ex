defmodule Sheetfolio.OperationsServer do
  use GenServer
  require Logger

  def start_link(_), do: GenServer.start_link(__MODULE__, nil, name: __MODULE__)

  def get_operations, do: GenServer.call(__MODULE__, :get_operations, 60_000)

  def init(_) do
    {:ok, nil, {:continue, :load}}
  end

  def handle_continue(:load, _) do
    operations =
      case Sheetfolio.MyinvestorEmails.fetch_all() do
        {:ok, ops} ->
          ops

        {:error, reason} ->
          Logger.error("[OperationsServer] Failed to load: #{inspect(reason)}")
          []
      end

    {:noreply, operations}
  end

  def handle_call(:get_operations, _from, state) do
    {:reply, state, state}
  end
end

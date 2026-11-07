defmodule Sheetfolio.LoginThrottle do
  @moduledoc """
  Limits password guessing: a few wrong passwords from one address block it for
  the rest of the window, and a higher limit across all addresses covers
  guesses spread over many of them. The owner's existing session keeps working
  through a block, so being locked out of `/login` costs them nothing.

  Held in memory on purpose. Losing the counts on a restart only gives a guesser
  a handful of extra tries.
  """
  use GenServer

  alias Sheetfolio.JobRuns

  @window_seconds 15 * 60
  @address_limit 5
  @global_limit 30

  def start_link(_opts), do: GenServer.start_link(__MODULE__, nil, name: __MODULE__)

  def allowed?(address), do: GenServer.call(__MODULE__, {:allowed?, address})
  def failed(address), do: GenServer.cast(__MODULE__, {:failed, address})
  def succeeded(address), do: GenServer.cast(__MODULE__, {:succeeded, address})

  @doc "Whether this address may try again, given the failures on record."
  def permitted?(failures, address, now) do
    recent = recent(failures, now)
    count_for(recent, address) < @address_limit and length(recent) < @global_limit
  end

  @doc "Failures still inside the window, with this one added."
  def record(failures, address, now), do: [{address, now} | recent(failures, now)]

  @doc "Forgets an address's failures, once it has shown it knows the password."
  def clear(failures, address), do: Enum.reject(failures, &(elem(&1, 0) == address))

  defp recent(failures, now), do: Enum.filter(failures, &(now - elem(&1, 1) < @window_seconds))

  defp count_for(failures, address), do: Enum.count(failures, &(elem(&1, 0) == address))

  defp now, do: System.system_time(:second)

  @impl true
  def init(nil), do: {:ok, []}

  @impl true
  def handle_call({:allowed?, address}, _from, failures) do
    allowed = permitted?(failures, address, now())
    if not allowed, do: JobRuns.failure("login", "Too many wrong passwords")
    {:reply, allowed, failures}
  end

  @impl true
  def handle_cast({:failed, address}, failures), do: {:noreply, record(failures, address, now())}
  def handle_cast({:succeeded, address}, failures), do: {:noreply, clear(failures, address)}
end

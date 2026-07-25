defmodule Sheetfolio.GmailToken do
  @moduledoc """
  Caches the Gmail OAuth access token.

  Gmail uses a refresh-token flow of its own (Goth only covers the Sheets
  service account), and without this every single API call paid for a full
  token refresh round-trip first — which, over a few hundred messages at boot,
  doubled the number of requests.

  Serving from a single GenServer also collapses the concurrent refreshes that
  would otherwise happen when the boot fetch fans out: whoever arrives first
  refreshes, everyone behind them gets the cached token.
  """
  use GenServer

  # Google issues one-hour tokens; renew early so a token can't expire in flight.
  @renew_margin_seconds 300
  @call_timeout 15_000

  def start_link(_opts), do: GenServer.start_link(__MODULE__, nil, name: __MODULE__)

  @doc "Returns {:ok, access_token} or {:error, reason}."
  def fetch, do: GenServer.call(__MODULE__, :fetch, @call_timeout)

  @doc "Drops the cached token, forcing a refresh on the next fetch."
  def invalidate, do: GenServer.cast(__MODULE__, :invalidate)

  @impl true
  def init(nil), do: {:ok, nil}

  @impl true
  def handle_call(:fetch, _from, state), do: reply_with(cached(state), state)

  @impl true
  def handle_cast(:invalidate, _state), do: {:noreply, nil}

  defp reply_with(nil, _state), do: refreshed()
  defp reply_with(token, state), do: {:reply, {:ok, token}, state}

  defp refreshed do
    case refresh() do
      {:ok, token, expires_at} -> {:reply, {:ok, token}, {token, expires_at}}
      {:error, reason} -> {:reply, {:error, reason}, nil}
    end
  end

  defp cached(nil), do: nil

  defp cached({token, expires_at}) do
    if DateTime.compare(DateTime.utc_now(), expires_at) == :lt, do: token
  end

  defp refresh do
    body = [
      grant_type: "refresh_token",
      refresh_token: System.fetch_env!("GMAIL_REFRESH_TOKEN"),
      client_id: System.fetch_env!("GMAIL_CLIENT_ID"),
      client_secret: System.fetch_env!("GMAIL_CLIENT_SECRET")
    ]

    case Req.post("https://oauth2.googleapis.com/token", form: body) do
      {:ok, %{status: 200, body: %{"access_token" => token} = response}} ->
        {:ok, token, expires_at(response["expires_in"])}

      {:ok, %{status: status, body: body}} ->
        {:error, {status, body}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp expires_at(expires_in) when is_integer(expires_in) do
    DateTime.add(DateTime.utc_now(), max(expires_in - @renew_margin_seconds, 0), :second)
  end

  defp expires_at(_), do: DateTime.utc_now()
end

defmodule Sheetfolio.EarningsServer do
  @moduledoc """
  Price and FX cache behind the earnings computations.

  The cache lives in a public ETS table rather than in the process state, and
  every request runs in its own supervised task. Nothing does network I/O inside
  a GenServer callback, so a page that asks for twenty prices fetches them in
  parallel instead of one at a time, and `get_fx_rates/0` can't end up queued
  behind somebody else's slow quote request.

  Current prices expire after 15 minutes and FX rates refresh hourly, because
  the Fly machine never stops — before that, both were fetched once at boot and
  then reused until the next deploy.
  """
  use GenServer

  require Logger

  alias Sheetfolio.Money
  alias Sheetfolio.PriceFetcher
  alias Sheetfolio.PricesApi.YahooFinance

  @table :sheetfolio_price_cache
  @price_ttl_ms 15 * 60 * 1000
  @fx_refresh_ms 60 * 60 * 1000

  def start_link(_), do: GenServer.start_link(__MODULE__, %{}, name: __MODULE__)

  def request(ref, isin, precio, cantidad, caller_pid) do
    run(fn -> send(caller_pid, {:earnings_result, ref, earnings(isin, precio, cantidad)}) end)
  end

  def request_price(isin, caller_pid) do
    run(fn -> send(caller_pid, {:price_result, isin, price(isin)}) end)
  end

  def request_price_at(isin, %Date{} = date, caller_pid) do
    run(fn -> send(caller_pid, price_at_message(isin, date)) end)
  end

  def get_fx_rates, do: GenServer.call(__MODULE__, :get_fx_rates)

  def clear_price_cache, do: GenServer.call(__MODULE__, :clear_price_cache)

  # --- GenServer callbacks ---

  def init(_) do
    :ets.new(@table, [:set, :public, :named_table, read_concurrency: true])
    send(self(), :refresh_fx)
    {:ok, %{eur_usd: 1.0, eur_cad: 1.0}}
  end

  def handle_info(:refresh_fx, state) do
    server = self()
    run(fn -> send(server, {:fx, fetch_fx("EURUSD=X"), fetch_fx("EURCAD=X")}) end)
    Process.send_after(self(), :refresh_fx, @fx_refresh_ms)
    {:noreply, state}
  end

  def handle_info({:fx, eur_usd, eur_cad}, state) do
    {:noreply, %{state | eur_usd: eur_usd, eur_cad: eur_cad}}
  end

  def handle_call(:get_fx_rates, _from, state) do
    {:reply, {state.eur_usd, state.eur_cad}, state}
  end

  def handle_call(:clear_price_cache, _from, state) do
    :ets.match_delete(@table, {{:price, :_}, :_, :_})
    {:reply, :ok, state}
  end

  # --- Work, all of it off the GenServer ---

  defp run(fun), do: Task.Supervisor.start_child(Sheetfolio.TaskSupervisor, fun)

  defp earnings(isin, precio, cantidad) do
    {eur_usd, eur_cad} = get_fx_rates()

    with price_eur when not is_nil(price_eur) <- price(isin),
         {qty, _} <- Money.parse_number(cantidad),
         {purchase_price, currency} <- Money.parse_price(precio) do
      cost = Money.to_eur(purchase_price, currency, eur_usd, eur_cad) * qty
      current = price_eur * qty
      {Float.round(current - cost, 2), Float.round((current - cost) / cost * 100, 2)}
    else
      _ -> nil
    end
  end

  defp price_at_message(isin, date) do
    case price_at(isin, date) do
      {:ok, price} -> {:price_result, isin, price}
      {:estimated, price} -> {:price_estimate, isin, price}
      _ -> {:price_result, isin, nil}
    end
  end

  defp price(isin) do
    cached(:ets.lookup(@table, {:price, isin}), fn -> fetch_price(isin) end)
  end

  defp cached([{_key, value, expires_at}], refetch) do
    if System.monotonic_time(:millisecond) < expires_at, do: value, else: refetch.()
  end

  defp cached([], refetch), do: refetch.()

  defp fetch_price(isin) do
    price = PriceFetcher.fetch_prices(%{isin => isin}) |> Map.get(isin)
    Logger.debug("[EarningsServer] Fetched price for #{isin}: #{inspect(price)}")
    expires_at = System.monotonic_time(:millisecond) + @price_ttl_ms
    :ets.insert(@table, {{:price, isin}, price, expires_at})
    price
  end

  # Historical prices and FX never change, so these entries have no expiry.
  defp price_at(isin, date) do
    key = {:price_at, isin, Date.to_iso8601(date)}

    case :ets.lookup(@table, key) do
      [{_key, result}] -> result
      [] -> compute_and_cache_price_at(key, isin, date)
    end
  end

  defp compute_and_cache_price_at(key, isin, date) do
    {eur_usd, eur_cad} = fx_at(date)
    result = compute_price_at(isin, date, eur_usd, eur_cad)
    :ets.insert(@table, {key, result})
    result
  end

  defp compute_price_at(isin, date, eur_usd, eur_cad) do
    case PriceFetcher.fetch_price_at(isin, date, eur_usd, eur_cad) do
      {:ok, price} -> {:ok, price}
      _ -> estimate_from_current(isin, date)
    end
  end

  # No historical quote available: drift today's price backwards very slightly
  # so the series doesn't show a flat line at today's value.
  defp estimate_from_current(isin, date) do
    days = Date.diff(Date.utc_today(), date)
    estimate(price(isin), days)
  end

  defp estimate(nil, _days), do: nil
  defp estimate(price, 0), do: {:ok, price}
  defp estimate(price, days), do: {:estimated, price * :math.pow(1 - 0.0002, days)}

  defp fx_at(date) do
    key = {:fx_at, Date.to_iso8601(date)}

    case :ets.lookup(@table, key) do
      [{_key, rates}] ->
        rates

      [] ->
        rates = {fetch_fx_at("EURUSD=X", date), fetch_fx_at("EURCAD=X", date)}
        :ets.insert(@table, {key, rates})
        rates
    end
  end

  defp fetch_fx(pair) do
    case YahooFinance.fetch_price(pair) do
      {:ok, rate, _} -> rate
      _ -> 1.0
    end
  end

  defp fetch_fx_at(pair, date) do
    case YahooFinance.fetch_price_at(pair, date) do
      {:ok, rate, _} -> rate
      _ -> 1.0
    end
  end
end

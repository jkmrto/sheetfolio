defmodule Sheetfolio.EarningsServer do
  use GenServer

  require Logger

  alias Sheetfolio.PriceFetcher
  alias Sheetfolio.PricesApi.YahooFinance

  def start_link(_), do: GenServer.start_link(__MODULE__, %{}, name: __MODULE__)

  def request(ref, isin, precio, cantidad, caller_pid) do
    GenServer.cast(__MODULE__, {:compute, ref, isin, precio, cantidad, caller_pid})
  end

  def request_price(isin, caller_pid) do
    GenServer.cast(__MODULE__, {:fetch_price, isin, caller_pid})
  end

  def get_fx_rates do
    GenServer.call(__MODULE__, :get_fx_rates)
  end

  # --- GenServer callbacks ---

  def init(_) do
    send(self(), :fetch_fx)
    {:ok, %{price_cache: %{}, eur_usd: 1.0, eur_cad: 1.0}}
  end

  def handle_info(:fetch_fx, state) do
    eur_usd = fetch_fx("EURUSD=X")
    eur_cad = fetch_fx("EURCAD=X")
    {:noreply, %{state | eur_usd: eur_usd, eur_cad: eur_cad}}
  end

  def handle_cast({:compute, ref, isin, precio, cantidad, caller_pid}, state) do
    {price_eur, state} = get_price(isin, state)

    result =
      with true <- not is_nil(price_eur),
           {qty, _} <- Float.parse(String.replace(cantidad, ",", "")),
           {purchase_price, currency} <- parse_price_with_currency(precio) do
        purchase_eur = to_eur(purchase_price, currency, state.eur_usd, state.eur_cad)
        cost = purchase_eur * qty
        current = price_eur * qty
        abs = Float.round(current - cost, 2)
        pct = Float.round((current - cost) / cost * 100, 2)
        {abs, pct}
      else
        _ -> nil
      end

    send(caller_pid, {:earnings_result, ref, result})
    {:noreply, state}
  end

  def handle_cast({:fetch_price, isin, caller_pid}, state) do
    {price_eur, state} = get_price(isin, state)
    send(caller_pid, {:price_result, isin, price_eur})
    {:noreply, state}
  end

  def handle_call(:get_fx_rates, _from, state) do
    {:reply, {state.eur_usd, state.eur_cad}, state}
  end

  defp get_price(isin, state) do
    case Map.fetch(state.price_cache, isin) do
      {:ok, price} ->
        {price, state}

      :error ->
        price = fetch_price(isin)
        Logger.debug("[EarningsServer] Fetched price for #{isin}: #{inspect(price)}")
        {price, put_in(state.price_cache[isin], price)}
    end
  end

  defp fetch_price(isin) do
    prices = PriceFetcher.fetch_prices(%{isin => isin})
    Map.get(prices, isin)
  end

  defp parse_price_with_currency(precio_str) do
    case Regex.run(~r/([\d.]+)\s+([A-Z]+)/, precio_str) do
      [_, amount, currency] ->
        case Float.parse(amount) do
          {val, _} -> {val, currency}
          :error -> :error
        end
      _ -> :error
    end
  end

  defp to_eur(price, "USD", eur_usd, _), do: price / eur_usd
  defp to_eur(price, "CAD", _, eur_cad), do: price / eur_cad
  defp to_eur(price, _, _, _), do: price

  defp fetch_fx(pair) do
    case YahooFinance.fetch_price(pair) do
      {:ok, rate, _} -> rate
      _ -> 1.0
    end
  end
end

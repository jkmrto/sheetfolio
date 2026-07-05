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

  def request_price_at(isin, %Date{} = date, caller_pid) do
    GenServer.cast(__MODULE__, {:fetch_price_at, isin, date, caller_pid})
  end

  def get_fx_rates do
    GenServer.call(__MODULE__, :get_fx_rates)
  end

  def clear_price_cache do
    GenServer.call(__MODULE__, :clear_price_cache)
  end

  # --- GenServer callbacks ---

  def init(_) do
    send(self(), :fetch_fx)
    {:ok, %{price_cache: %{}, historical_cache: %{}, historical_fx: %{}, eur_usd: 1.0, eur_cad: 1.0}}
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
           {qty, _} <- parse_number(cantidad),
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

  def handle_cast({:fetch_price_at, isin, date, caller_pid}, state) do
    {eur_usd, eur_cad, state} = get_historical_fx(date, state)
    cache_key = {isin, Date.to_iso8601(date)}

    {result, state} =
      case Map.fetch(state.historical_cache, cache_key) do
        {:ok, cached} ->
          {cached, state}

        :error ->
          {result, new_state} = compute_price_at(isin, date, eur_usd, eur_cad, state)
          {result, %{new_state | historical_cache: Map.put(new_state.historical_cache, cache_key, result)}}
      end

    case result do
      {:ok, price} -> send(caller_pid, {:price_result, isin, price})
      {:estimated, price} -> send(caller_pid, {:price_estimate, isin, price})
      _ -> send(caller_pid, {:price_result, isin, nil})
    end

    {:noreply, state}
  end

  def handle_call(:get_fx_rates, _from, state) do
    {:reply, {state.eur_usd, state.eur_cad}, state}
  end

  def handle_call(:clear_price_cache, _from, state) do
    {:reply, :ok, %{state | price_cache: %{}}}
  end

  defp compute_price_at(isin, date, eur_usd, eur_cad, state) do
    case PriceFetcher.fetch_price_at(isin, date, eur_usd, eur_cad) do
      {:ok, price} ->
        {{:ok, price}, state}

      _ ->
        {current_price, new_state} = get_price(isin, state)
        today = Date.utc_today()
        days = Date.diff(today, date)

        result =
          cond do
            is_nil(current_price) -> nil
            days == 0 -> {:ok, current_price}
            true -> {:estimated, current_price * :math.pow(1 - 0.0002, days)}
          end

        {result, new_state}
    end
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
    case Regex.run(~r/([\d.,]+)\s+([A-Z]+)/, precio_str) do
      [_, amount, currency] ->
        case parse_number(amount) do
          {val, _} -> {val, currency}
          :error -> :error
        end
      _ -> :error
    end
  end

  defp parse_number(str) do
    cond do
      String.contains?(str, ".") and String.contains?(str, ",") ->
        last_dot = str |> :binary.matches(".") |> List.last() |> elem(0)
        last_comma = str |> :binary.matches(",") |> List.last() |> elem(0)
        if last_dot > last_comma do
          str |> String.replace(",", "") |> Float.parse()
        else
          str |> String.replace(".", "") |> String.replace(",", ".") |> Float.parse()
        end
      String.contains?(str, ",") ->
        case Regex.run(~r/^[\d,]+,(\d{3})$/, str) do
          [_, _] -> str |> String.replace(",", "") |> Float.parse()
          _ -> str |> String.replace(",", ".") |> Float.parse()
        end
      true ->
        Float.parse(str)
    end
  end

  defp to_eur(price, "USD", eur_usd, _), do: price / eur_usd
  defp to_eur(price, "CAD", _, eur_cad), do: price / eur_cad
  defp to_eur(price, _, _, _), do: price

  defp get_historical_fx(date, state) do
    date_str = Date.to_iso8601(date)

    case Map.fetch(state.historical_fx, date_str) do
      {:ok, {eur_usd, eur_cad}} ->
        {eur_usd, eur_cad, state}

      :error ->
        eur_usd = fetch_fx_at("EURUSD=X", date)
        eur_cad = fetch_fx_at("EURCAD=X", date)
        new_state = %{state | historical_fx: Map.put(state.historical_fx, date_str, {eur_usd, eur_cad})}
        {eur_usd, eur_cad, new_state}
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

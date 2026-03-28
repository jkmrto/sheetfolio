defmodule Sheetfolio.OperationsCache do
  use Agent

  require Logger

  alias Sheetfolio.PricesApi.YahooFinance

  @headers [
    "Fecha", "Asset", "ISIN", "Tipo", "Cantidad", "Precio",
    "Importe", "Comisión", "Importe Neto", "Ganancia (€)", "Ganancia (%)"
  ]

  def start_link(_opts) do
    {:ok, pid} = Agent.start_link(fn -> load() end, name: __MODULE__)
    Task.start(fn -> enrich_with_prices() end)
    {:ok, pid}
  end

  def get, do: Agent.get(__MODULE__, &Map.take(&1, [:headers, :rows]))

  def reload do
    Agent.update(__MODULE__, fn _ -> load() end)
    Task.start(fn -> enrich_with_prices() end)
  end

  defp load do
    case Sheetfolio.MyinvestorEmails.fetch_all() do
      {:ok, operations} ->
        rows =
          operations
          |> Enum.sort_by(&parse_date(&1.fecha), {:desc, Date})
          |> Enum.map(&to_row(&1, %{}, 1.0, 1.0))

        %{headers: @headers, rows: rows, operations: operations}

      {:error, reason} ->
        Logger.error("[OperationsCache] Failed to fetch emails: #{inspect(reason)}")
        %{headers: @headers, rows: [], operations: []}
    end
  end

  defp enrich_with_prices do
    operations = Agent.get(__MODULE__, & &1.operations)

    isin_map = operations |> Enum.map(& &1.isin) |> Enum.uniq() |> Map.new(&{&1, &1})
    current_prices = Sheetfolio.PriceFetcher.fetch_prices(isin_map)

    eur_usd = fetch_fx("EURUSD=X")
    eur_cad = fetch_fx("EURCAD=X")

    Agent.update(__MODULE__, fn state ->
      rows =
        state.operations
        |> Enum.sort_by(&parse_date(&1.fecha), {:desc, Date})
        |> Enum.map(&to_row(&1, current_prices, eur_usd, eur_cad))

      %{state | rows: rows}
    end)
  end

  defp to_row(data, current_prices, eur_usd, eur_cad) do
    {earnings_abs, earnings_pct} = compute_earnings(data, current_prices, eur_usd, eur_cad)

    [
      data.fecha,
      data.asset,
      data.isin,
      data.tipo,
      data.cantidad,
      data.precio,
      data.importe_without_comision,
      data.comision,
      data.importe_with_comision,
      format_abs(earnings_abs),
      format_pct(earnings_pct)
    ]
  end

  defp compute_earnings(data, current_prices, eur_usd, eur_cad) do
    with current_price when not is_nil(current_price) <- Map.get(current_prices, data.isin),
         {cantidad, _} <- Float.parse(String.replace(data.cantidad, ",", "")),
         {purchase_price, currency} <- parse_price_with_currency(data.precio) do
      purchase_price_eur = to_eur(purchase_price, currency, eur_usd, eur_cad)
      cost_eur = purchase_price_eur * cantidad
      current_value_eur = current_price * cantidad
      earnings_abs = current_value_eur - cost_eur
      earnings_pct = earnings_abs / cost_eur * 100
      {earnings_abs, earnings_pct}
    else
      _ -> {nil, nil}
    end
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

  defp format_abs(nil), do: ""
  defp format_abs(val), do: "#{Float.round(val, 2)}"

  defp format_pct(nil), do: ""
  defp format_pct(val), do: "#{Float.round(val, 2)}%"

  defp parse_date(date_str) do
    case String.split(date_str, "/") do
      [d, m, y] ->
        Date.new!(String.to_integer(y), String.to_integer(m), String.to_integer(d))
      _ ->
        ~D[1970-01-01]
    end
  end
end

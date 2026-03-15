defmodule Sheetfolio.PriceFetcher do
  @moduledoc """
  Fetches current prices for assets given their ISIN (or special identifier).
  Resolves ISIN → ticker via Yahoo Finance search, falling back to OpenFIGI.
  Returns prices converted to EUR.
  """

  alias Sheetfolio.PricesApi.{OpenFigi, YahooFinance}

  def fetch_prices(assets_map) do
    eur_usd = fetch_fx("EURUSD=X") || 1.0
    eur_cad = fetch_fx("EURCAD=X") || 1.0

    assets_map
    |> Task.async_stream(
      fn {name, isin} -> {name, fetch_price(isin, eur_usd, eur_cad)} end,
      max_concurrency: 5,
      timeout: 15_000
    )
    |> Enum.reduce(%{}, fn
      {:ok, {name, {:ok, price}}}, acc -> Map.put(acc, name, price)
      _, acc -> acc
    end)
  end

  defp fetch_price("Bitcoin", eur_usd, _eur_cad) do
    case YahooFinance.fetch_price("BTC-USD") do
      {:ok, price, "USD"} -> {:ok, price / eur_usd}
      {:ok, price, _} -> {:ok, price}
      err -> err
    end
  end

  defp fetch_price(isin, eur_usd, eur_cad) do
    with {:ok, ticker} <- resolve_ticker(isin),
         {:ok, price, currency} <- YahooFinance.fetch_price(ticker) do
      {:ok, to_eur(price, currency, eur_usd, eur_cad)}
    end
  end

  @isin_format ~r/^[A-Z]{2}[A-Z0-9]{10}$/

  defp resolve_ticker(value) do
    if Regex.match?(@isin_format, value) do
      case YahooFinance.resolve_ticker(value) do
        {:ok, ticker} -> {:ok, ticker}
        {:error, _} -> OpenFigi.resolve_ticker(value)
      end
    else
      # Value is already a direct Yahoo Finance ticker
      {:ok, value}
    end
  end

  defp to_eur(price, "USD", eur_usd, _eur_cad), do: price / eur_usd
  defp to_eur(price, "CAD", _eur_usd, eur_cad), do: price / eur_cad
  defp to_eur(price, _, _, _), do: price

  defp fetch_fx(pair) do
    case YahooFinance.fetch_price(pair) do
      {:ok, rate, _} -> rate
      _ -> nil
    end
  end
end

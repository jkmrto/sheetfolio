defmodule Sheetfolio.PriceFetcher do
  @moduledoc """
  Fetches current prices for assets given their ISIN (or special identifier).
  Resolves ISIN → ticker via Yahoo Finance search, falling back to OpenFIGI.
  Returns prices converted to EUR.
  """

  alias Sheetfolio.Money
  alias Sheetfolio.PricesApi.{OpenFigi, YahooFinance, Stooq}

  @isin_format ~r/^[A-Z]{2}[A-Z0-9]{10}$/

  @ticker_overrides %{
    "DE000A1E0HS6" => "XAD6.DE",
    "GB00BJYDH287" => "BTCW.L",
    "LU0080237943" => "DI4C.F"
  }

  # ISINs where Yahoo Finance has no historical data — fall back to Stooq (Frankfurt tickers)
  @stooq_overrides %{
    "LU0080237943" => "di4c.de",
    "IE000RHYOR04" => "ie000rhyor04.de"
  }

  def fetch_price_at("Bitcoin", %Date{} = date, eur_usd, _eur_cad) do
    case YahooFinance.fetch_price_at("BTC-USD", date) do
      {:ok, price, "USD"} -> {:ok, price / eur_usd}
      {:ok, price, _} -> {:ok, price}
      err -> err
    end
  end

  def fetch_price_at(isin, %Date{} = date, eur_usd, eur_cad) do
    with {:ok, ticker} <- resolve_ticker(isin),
         {:ok, price, currency} <- fetch_historical(isin, ticker, date) do
      {:ok, to_eur(price, currency, eur_usd, eur_cad)}
    end
  end

  defp fetch_historical(isin, ticker, date) do
    case YahooFinance.fetch_price_at(ticker, date) do
      {:ok, _, _} = ok -> ok
      _ -> fetch_stooq_fallback(isin, date)
    end
  end

  defp fetch_stooq_fallback(isin, date) do
    case Map.get(@stooq_overrides, isin) do
      nil -> {:error, :no_price}
      stooq_ticker -> Stooq.fetch_price_at(stooq_ticker, date)
    end
  end

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

  def stooq_ticker(isin), do: Map.get(@stooq_overrides, isin)

  def resolve_ticker(value) do
    cond do
      Map.has_key?(@ticker_overrides, value) ->
        {:ok, @ticker_overrides[value]}
      Regex.match?(@isin_format, value) ->
        case YahooFinance.resolve_ticker(value) do
          {:ok, ticker} -> {:ok, ticker}
          {:error, _} -> OpenFigi.resolve_ticker(value)
        end
      true ->
        {:ok, value}
    end
  end

  defp to_eur(price, currency, eur_usd, eur_cad), do: Money.to_eur(price, currency, eur_usd, eur_cad)

  defp fetch_fx(pair) do
    case YahooFinance.fetch_price(pair) do
      {:ok, rate, _} -> rate
      _ -> nil
    end
  end
end

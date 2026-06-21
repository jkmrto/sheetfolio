defmodule Sheetfolio.PricesApi.YahooFinance do
  require Logger

  @search_url "https://query1.finance.yahoo.com/v1/finance/search"
  @chart_url "https://query1.finance.yahoo.com/v8/finance/chart"

  @doc "Resolves an ISIN to a Yahoo Finance ticker via the search endpoint."
  def resolve_ticker(isin) do
    case Req.get(@search_url, params: [q: isin, quotesCount: 1, newsCount: 0]) do
      {:ok, %{status: 200, body: %{"quotes" => [%{"symbol" => ticker} | _]}}} ->
        Logger.debug("[YahooFinance] ISIN #{isin} resolved to ticker #{ticker}")
        {:ok, ticker}

      {:ok, %{status: 200, body: %{"quotes" => []}}} ->
        Logger.warning("[YahooFinance] No ticker found for ISIN #{isin}")
        {:error, {:no_ticker, isin}}

      {:ok, %{status: status}} ->
        Logger.warning("[YahooFinance] HTTP #{status} resolving ISIN #{isin}")
        {:error, {:http, status}}

      {:error, reason} ->
        Logger.warning("[YahooFinance] Error resolving ISIN #{isin}: #{inspect(reason)}")
        {:error, reason}
    end
  end

  @doc "Fetches current price and currency for a ticker."
  def fetch_price(ticker) do
    url = "#{@chart_url}/#{URI.encode(ticker)}"

    case Req.get(url, params: [range: "1d", interval: "1d"]) do
      {:ok, %{status: 200, body: body}} ->
        result = parse_chart(body)
        Logger.debug("[YahooFinance] Price for #{ticker}: #{inspect(result)}")
        result

      {:ok, %{status: status}} ->
        Logger.warning("[YahooFinance] HTTP #{status} fetching price for #{ticker}")
        {:error, {:http, status}}

      {:error, reason} ->
        Logger.warning("[YahooFinance] Error fetching price for #{ticker}: #{inspect(reason)}")
        {:error, reason}
    end
  end

  @doc "Fetches daily close prices for a ticker between two Unix timestamps. Returns {:ok, %{Date => price}}."
  def fetch_historical(ticker, period1, period2) do
    url = "#{@chart_url}/#{URI.encode(ticker)}"

    case Req.get(url, params: [period1: period1, period2: period2, interval: "1d"]) do
      {:ok, %{status: 200, body: body}} ->
        parse_historical(body)

      {:ok, %{status: status}} ->
        Logger.warning("[YahooFinance] HTTP #{status} fetching historical for #{ticker}")
        {:error, {:http, status}}

      {:error, reason} ->
        Logger.warning("[YahooFinance] Error fetching historical for #{ticker}: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp parse_historical(body) do
    try do
      result = body["chart"]["result"] |> List.first()
      timestamps = result["timestamp"]
      closes = result["indicators"]["quote"] |> List.first() |> Map.get("close")

      prices =
        Enum.zip(timestamps, closes)
        |> Enum.filter(fn {_, price} -> price != nil end)
        |> Map.new(fn {ts, price} ->
          {DateTime.from_unix!(ts) |> DateTime.to_date(), price}
        end)

      {:ok, prices}
    rescue
      e -> {:error, {:parse_error, Exception.message(e)}}
    end
  end

  defp parse_chart(body) do
    try do
      result = body["chart"]["result"] |> List.first()
      currency = result["meta"]["currency"]

      price =
        result["meta"]["regularMarketPrice"] ||
          result["indicators"]["quote"] |> List.first() |> Map.get("close") |> List.last()

      if price, do: {:ok, price, currency}, else: {:error, :no_price}
    rescue
      e -> {:error, {:parse_error, Exception.message(e)}}
    end
  end
end

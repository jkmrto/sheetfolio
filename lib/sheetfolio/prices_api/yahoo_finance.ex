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
        result = parse_chart_current(body)
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

  @doc "Fetches the closing price on or before `date` for a ticker."
  def fetch_price_at(ticker, %Date{} = date) do
    url = "#{@chart_url}/#{URI.encode(ticker)}"
    # Look back 7 days to handle weekends/holidays; take the last available close.
    period1 = date_to_unix(Date.add(date, -7))
    period2 = date_to_unix(Date.add(date, 1))

    case Req.get(url, params: [period1: period1, period2: period2, interval: "1d"]) do
      {:ok, %{status: 200, body: body}} ->
        result = parse_chart_historical(body)
        Logger.debug("[YahooFinance] Historical price for #{ticker} at #{date}: #{inspect(result)}")
        result

      {:ok, %{status: status}} ->
        Logger.warning("[YahooFinance] HTTP #{status} fetching historical price for #{ticker}")
        {:error, {:http, status}}

      {:error, reason} ->
        Logger.warning("[YahooFinance] Error fetching historical price for #{ticker}: #{inspect(reason)}")
        {:error, reason}
    end
  end

  @doc "Fetches the daily close series between two dates. Returns {:ok, %{Date => close}, currency}."
  def fetch_series(ticker, %Date{} = from, %Date{} = to) do
    url = "#{@chart_url}/#{URI.encode(ticker)}"
    period1 = date_to_unix(from)
    period2 = date_to_unix(Date.add(to, 1))

    case Req.get(url, params: [period1: period1, period2: period2, interval: "1d"]) do
      {:ok, %{status: 200, body: body}} ->
        parse_chart_series(body)

      {:ok, %{status: status}} ->
        Logger.warning("[YahooFinance] HTTP #{status} fetching series for #{ticker}")
        {:error, {:http, status}}

      {:error, reason} ->
        Logger.warning("[YahooFinance] Error fetching series for #{ticker}: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp parse_chart_series(body) do
    with %{"chart" => %{"result" => [result | _]}} <- body,
         %{"meta" => %{"currency" => currency}, "timestamp" => timestamps,
           "indicators" => %{"quote" => [%{"close" => closes} | _]}} <- result do
      series =
        Enum.zip(timestamps, closes)
        |> Enum.filter(fn {_ts, close} -> close end)
        |> Map.new(fn {ts, close} ->
          {DateTime.from_unix!(ts) |> DateTime.to_date(), close}
        end)

      {:ok, series, currency}
    else
      _ -> {:error, :no_price}
    end
  end

  defp parse_chart_current(body) do
    with %{"chart" => %{"result" => [result | _]}} <- body,
         %{"meta" => %{"currency" => currency}} <- result do
      price =
        get_in(result, ["meta", "regularMarketPrice"]) ||
          (result["indicators"]["quote"] |> List.first() |> Map.get("close", []) |> List.last())

      if price, do: {:ok, price, currency}, else: {:error, :no_price}
    else
      _ -> {:error, :no_price}
    end
  end

  defp parse_chart_historical(body) do
    with %{"chart" => %{"result" => [result | _]}} <- body,
         %{"meta" => %{"currency" => currency}, "indicators" => %{"quote" => [%{"close" => closes} | _]}} <- result,
         price when not is_nil(price) <- closes |> Enum.filter(& &1) |> List.last() do
      {:ok, price, currency}
    else
      _ -> {:error, :no_price}
    end
  end

  defp date_to_unix(%Date{} = date) do
    Date.diff(date, ~D[1970-01-01]) * 86400
  end
end

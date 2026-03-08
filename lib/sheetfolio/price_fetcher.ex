defmodule Sheetfolio.PriceFetcher do
  @moduledoc """
  Fetches current prices for a list of ISINs using Yahoo Finance's unofficial API.
  Resolves ISIN → Yahoo Finance ticker via the search endpoint, then fetches the price.
  Returns prices in EUR (converting USD/CAD as needed).
  """

  @search_url "https://query1.finance.yahoo.com/v1/finance/search"
  @chart_url "https://query1.finance.yahoo.com/v8/finance/chart"

  @doc """
  Given a map of %{name => isin_or_atom}, returns %{name => price_in_eur}.
  Skips assets that cannot be resolved.
  """
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
      {:ok, {name, {:ok, price}}} -> Map.put(%{}, name, price)
      {:ok, {_name, {:error, _}}} -> %{}
      {:exit, _} -> %{}
    end)
    |> Enum.reduce(%{}, &Map.merge(&2, &1))
  end

  defp fetch_price("Bitcoin", eur_usd, _eur_cad) do
    case fetch_yahoo_price("BTC-USD") do
      {:ok, price, "USD"} -> {:ok, price / eur_usd}
      {:ok, price, _} -> {:ok, price}
      err -> err
    end
  end

  defp fetch_price(isin, eur_usd, eur_cad) do
    with {:ok, ticker} <- resolve_ticker(isin),
         {:ok, price, currency} <- fetch_yahoo_price(ticker) do
      price_eur =
        case currency do
          "USD" -> price / eur_usd
          "CAD" -> price / eur_cad
          _ -> price
        end

      {:ok, price_eur}
    end
  end

  defp resolve_ticker(isin) do
    case Req.get(@search_url, params: [q: isin, quotesCount: 1, newsCount: 0]) do
      {:ok, %{status: 200, body: %{"quotes" => [%{"symbol" => ticker} | _]}}} ->
        {:ok, ticker}

      {:ok, %{status: 200, body: %{"quotes" => []}}} ->
        {:error, {:no_ticker, isin}}

      {:ok, %{status: status}} ->
        {:error, {:http, status}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp fetch_yahoo_price(ticker) do
    url = "#{@chart_url}/#{URI.encode(ticker)}"

    case Req.get(url, params: [range: "1d", interval: "1d"]) do
      {:ok, %{status: 200, body: body}} ->
        parse_chart(body)

      {:ok, %{status: status}} ->
        {:error, {:http, status}}

      {:error, reason} ->
        {:error, reason}
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
      _ -> {:error, :parse_error}
    end
  end

  defp fetch_fx(pair) do
    case fetch_yahoo_price(pair) do
      {:ok, rate, _} -> rate
      _ -> nil
    end
  end
end

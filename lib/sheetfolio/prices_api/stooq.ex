defmodule Sheetfolio.PricesApi.Stooq do
  require Logger

  @base_url "https://stooq.com/q/d/l/"

  def fetch_price(ticker) do
    today = Date.utc_today()
    fetch_price_at(ticker, today)
  end

  def fetch_price_at(ticker, %Date{} = date) do
    d1 = Date.add(date, -7) |> format_date()
    d2 = format_date(date)

    case Req.get(@base_url, params: [s: ticker, d1: d1, d2: d2, i: "d"]) do
      {:ok, %{status: 200, body: body}} when is_binary(body) ->
        parse_csv(body, ticker)

      {:ok, %{status: status}} ->
        Logger.warning("[Stooq] HTTP #{status} for ticker #{ticker}")
        {:error, {:http, status}}

      {:error, reason} ->
        Logger.warning("[Stooq] Error for ticker #{ticker}: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp parse_csv(body, ticker) do
    rows =
      body
      |> String.split("\n", trim: true)
      |> Enum.drop(1)
      |> Enum.map(&String.split(&1, ","))
      |> Enum.filter(fn cols -> length(cols) >= 5 end)

    case List.last(rows) do
      [_date, _open, _high, _low, close | _] ->
        case Float.parse(String.trim(close)) do
          {price, _} ->
            Logger.debug("[Stooq] Price for #{ticker}: #{price}")
            {:ok, price, "EUR"}

          :error ->
            {:error, :no_price}
        end

      _ ->
        Logger.warning("[Stooq] No data rows for ticker #{ticker}")
        {:error, :no_price}
    end
  end

  defp format_date(%Date{} = date) do
    Calendar.strftime(date, "%Y%m%d")
  end
end

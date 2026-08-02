defmodule Sheetfolio.HistoricalFx do
  @moduledoc """
  Attaches the EUR/USD and EUR/CAD rates of an operation's own date to it.

  MyInvestor sends foreign-currency confirmations with `importe` zeroed and only
  a per-share `precio` in USD or CAD, so `Positions` has to convert price times
  quantity itself. Doing that at today's rate made the cost basis of a 2021
  purchase move every time the euro did: of the 68 cost-basis jumps across the
  stored snapshots, 58 were on the six US and Canadian holdings and were nothing
  but FX drift.

  Two daily series cover the whole history, so this costs two requests at boot
  rather than one per operation. If either fetch fails the operations come back
  untouched and `Positions` falls back to the rate it was passed, which is the
  behaviour this replaces.
  """

  require Logger

  alias Sheetfolio.PricesApi.YahooFinance

  # Rates only exist on trading days, so a weekend or holiday operation takes
  # the last rate published before it.
  @max_lookback 7

  def attach([]), do: []

  def attach(operations) do
    case operations |> Enum.map(&parse_date(&1.fecha)) |> Enum.reject(&is_nil/1) do
      [] -> operations
      dates -> attach_over(operations, Enum.min(dates, Date))
    end
  end

  defp attach_over(operations, from) do
    usd = series("EURUSD=X", from)
    cad = series("EURCAD=X", from)

    if map_size(usd) == 0 or map_size(cad) == 0 do
      Logger.warning("[HistoricalFx] No FX series available, falling back to current rates")
      operations
    else
      Enum.map(operations, &attach_one(&1, usd, cad))
    end
  end

  defp series(pair, from) do
    case YahooFinance.fetch_series(pair, from, Date.utc_today()) do
      {:ok, rates, _currency} -> rates
      _error -> %{}
    end
  end

  defp attach_one(operation, usd, cad) do
    with date when not is_nil(date) <- parse_date(operation.fecha),
         rate_usd when is_number(rate_usd) <- nearest(usd, date),
         rate_cad when is_number(rate_cad) <- nearest(cad, date) do
      Map.merge(operation, %{fx_usd: rate_usd, fx_cad: rate_cad})
    else
      _ -> operation
    end
  end

  defp nearest(rates, date) do
    Enum.find_value(0..@max_lookback, fn offset -> Map.get(rates, Date.add(date, -offset)) end)
  end

  defp parse_date(fecha) do
    with [d, m, y] <- String.split(fecha, "/"),
         {day, _} <- Integer.parse(d),
         {month, _} <- Integer.parse(m),
         {year, _} <- Integer.parse(y),
         {:ok, date} <- Date.new(year, month, day) do
      date
    else
      _ -> nil
    end
  end
end

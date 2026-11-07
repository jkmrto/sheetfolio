defmodule Sheetfolio.HistoricalFx do
  @moduledoc """
  Attaches the EUR/USD and EUR/CAD rates of an operation's own date to it.

  MyInvestor sends foreign-currency confirmations with `importe` zeroed and only
  a per-share `precio` in USD or CAD, so `Positions` has to convert price times
  quantity itself. Doing that at today's rate made the cost basis of a 2021
  purchase move every time the euro did: of the 68 cost-basis jumps across the
  stored snapshots, 58 were on the six US and Canadian holdings and were nothing
  but FX drift.

  A past rate never changes, so each one is kept in `fx_rates`, one document per
  operation date:

      { _id: "2026-01-09", usd: 1.1643, cad: 1.6197 }

  That makes `attach_stored/1` safe to call without the network, and means a
  Yahoo outage only affects operations new enough to have no stored rate. Those
  fall back to the rate `Positions` is passed until a later `refresh/1` fills
  them in, and the failure shows on the data health panel.
  """

  require Logger

  alias Sheetfolio.JobRuns
  alias Sheetfolio.Positions
  alias Sheetfolio.PricesApi.YahooFinance

  @collection "fx_rates"
  @job "historical_fx"

  # Rates only exist on trading days, so a weekend or holiday operation takes
  # the last rate published before it.
  @max_lookback 7

  @doc "Attaches the rates already stored. Touches Mongo, never Yahoo."
  def attach_stored(operations), do: pin(operations, stored())

  @doc """
  Fetches the rates still missing, stores the settled ones, and attaches
  everything known. Network calls, so this doesn't belong in a GenServer callback.
  """
  def refresh(operations) do
    rates = stored()
    pinned = pin(operations, rates)

    case missing_dates(pinned) do
      [] -> finish(pinned)
      dates -> pin_fetched(pinned, dates)
    end
  end

  @doc "Attaches `%{date => {usd, cad}}` to the operations it covers."
  def pin(operations, rates), do: Enum.map(operations, &pin_one(&1, rates))

  @doc """
  The `{usd, cad}` rate for each date, from two daily series. A date neither
  series covers within the lookback is left out.
  """
  def resolve(dates, usd, cad) do
    for date <- dates,
        rate_usd = nearest(usd, date),
        rate_cad = nearest(cad, date),
        into: %{},
        do: {date, {rate_usd, rate_cad}}
  end

  defp pin_one(operation, rates) do
    case Map.get(rates, parse_date(operation.fecha)) do
      {usd, cad} -> Map.merge(operation, %{fx_usd: usd, fx_cad: cad})
      nil -> operation
    end
  end

  defp missing_dates(operations) do
    operations
    |> Positions.unpinned()
    |> Enum.map(&parse_date(&1.fecha))
    |> Enum.reject(&is_nil/1)
    |> Enum.uniq()
  end

  defp pin_fetched(operations, dates) do
    from = Enum.min(dates, Date)
    fetched = resolve(dates, series("EURUSD=X", from), series("EURCAD=X", from))

    store(fetched)
    finish(pin(operations, fetched))
  end

  defp finish(operations) do
    report(length(Positions.unpinned(operations)))
    operations
  end

  defp report(0), do: JobRuns.success(@job)

  defp report(count) do
    Logger.warning("[HistoricalFx] #{count} operations have no rate of their own")
    JobRuns.failure(@job, "#{count} operations converted at today's rate")
  end

  # Today's rate is still moving, so only settled days are worth keeping.
  defp store(rates) do
    today = Date.utc_today()

    docs =
      for {date, {usd, cad}} <- rates, Date.compare(date, today) == :lt do
        %{_id: Date.to_iso8601(date), usd: usd, cad: cad}
      end

    if docs != [], do: Mongo.insert_many(:mongo, @collection, docs, ordered: false)
  end

  defp stored do
    :mongo
    |> Mongo.find(@collection, %{})
    |> Map.new(&{Date.from_iso8601!(&1["_id"]), {&1["usd"], &1["cad"]}})
  end

  defp series(pair, from) do
    case YahooFinance.fetch_series(pair, from, Date.utc_today()) do
      {:ok, rates, _currency} -> rates
      _error -> %{}
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

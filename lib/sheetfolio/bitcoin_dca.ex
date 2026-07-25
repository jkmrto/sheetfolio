defmodule Sheetfolio.BitcoinDca do
  @moduledoc """
  Pure aggregation behind the Bitcoin DCA subtab: per-day net-purchase rows
  and the cumulative invested/value/benchmark series behind its chart.

  Built on `Positions.history/3`'s average-cost-basis replay rather than
  summing raw buy operations directly. This account has one same-day buy
  immediately undone by a sell (100 units bought and 100 sold on
  07/10/2025) — summing buys alone would count that buy as a permanent
  6255 EUR-and-counting addition to "invested" that was never actually kept.
  Positions already nets a sell against the running cost basis correctly for
  every other page in this app; reusing it here keeps that the single place
  average-cost accounting happens.

  Unlike the S&P 500 DCA page, there is no base/extra split — the Bitcoin
  buys are a steady weekly amount with no discretionary top-up, so this just
  tracks DCA performance against Bitcoin itself.
  """

  alias Sheetfolio.Money
  alias Sheetfolio.Positions

  @isin "GB00BJYDH287"

  def isin, do: @isin

  @doc """
  This ISIN's cumulative `%{fecha, net_qty, cost_basis}` after each date with
  activity, oldest first. The last entry is the current position.
  """
  def state_history(operations, eur_usd, eur_cad) do
    operations
    |> Enum.filter(&(&1.isin == @isin))
    |> Positions.history(eur_usd, eur_cad)
    |> Enum.map(&isin_state/1)
  end

  defp isin_state({fecha, assets}) do
    state = Map.get(assets, @isin, %{net_qty: 0.0, cost_basis: 0.0})
    %{fecha: fecha, net_qty: state.net_qty, cost_basis: state.cost_basis}
  end

  @doc """
  One row per date with a net-positive purchase, newest first — the day's
  change in units and cost basis, not the raw operations recorded that day.
  A date whose sells net out or exceed its buys contributes no row.
  """
  def build_buys(state_history) do
    state_history
    |> deltas()
    |> Enum.filter(&(&1.units > 0.0001))
  end

  # Prepends as it folds over the oldest-first history, so rows come back
  # newest-first, which is the order the table wants.
  defp deltas(state_history) do
    {rows, _last} =
      Enum.reduce(state_history, {[], {0.0, 0.0}}, fn state, {rows, previous} ->
        {row, next} = delta_row(state, previous)
        {[row | rows], next}
      end)

    rows
  end

  defp delta_row(%{fecha: fecha, net_qty: net_qty, cost_basis: cost_basis}, {prev_qty, prev_cost}) do
    units = net_qty - prev_qty
    invested = cost_basis - prev_cost

    row = %{
      fecha: fecha,
      units: units,
      invested: invested,
      unit_cost: unit_cost(invested, units),
      value_now: nil,
      pnl: nil,
      pnl_pct: nil
    }

    {row, {net_qty, cost_basis}}
  end

  defp unit_cost(_invested, units) when units <= 0.0, do: 0.0
  defp unit_cost(invested, units), do: invested / units

  @doc "Fills in value_now/pnl/pnl_pct on every row from a single current EUR price."
  def price_buys(buys, price_eur) do
    Enum.map(buys, fn buy ->
      value_now = Float.round(buy.units * price_eur, 2)
      pnl = Float.round(value_now - buy.invested, 2)
      pnl_pct = pnl_pct(pnl, buy.invested)
      %{buy | value_now: value_now, pnl: pnl, pnl_pct: pnl_pct}
    end)
  end

  defp pnl_pct(_pnl, invested) when invested <= 0, do: nil
  defp pnl_pct(pnl, invested), do: Float.round(pnl / invested * 100, 2)

  @doc """
  Chart points in date order: cumulative invested (the running cost basis —
  average-cost accounting, so a same-day buy undone by a sell doesn't
  inflate it), cumulative value (net units held × the ETF's EUR price on
  that date, from `etf_prices_usd`), and the raw Bitcoin benchmark price on
  that date (from `btc_prices_usd`). Both price maps are `%{Date =>
  usd_price}`; a date missing from either falls back to the nearest earlier
  price within 4 days, since Yahoo only returns trading days.
  """
  def cumulative_series(state_history, etf_prices_usd, btc_prices_usd, eur_usd, eur_cad) do
    Enum.map(state_history, fn %{fecha: fecha, net_qty: net_qty, cost_basis: cost_basis} ->
      date = parse_date(fecha)

      %{
        date: iso_date(fecha),
        invested: Float.round(cost_basis, 2),
        value: value_at(net_qty, etf_prices_usd, date, eur_usd, eur_cad),
        btc: nearest_price(btc_prices_usd, date)
      }
    end)
  end

  defp value_at(units, prices, date, eur_usd, eur_cad) do
    case nearest_price(prices, date) do
      nil -> nil
      price_usd -> Float.round(units * Money.to_eur(price_usd, "USD", eur_usd, eur_cad), 2)
    end
  end

  @doc "The price on `date`, or the nearest earlier price within 4 days."
  def nearest_price(prices, date) do
    Enum.find_value(0..4, fn offset -> Map.get(prices, Date.add(date, -offset)) end)
  end

  defp parse_date(fecha) do
    [d, m, y] = String.split(fecha, "/")
    Date.new!(String.to_integer(y), String.to_integer(m), String.to_integer(d))
  end

  defp iso_date(fecha) do
    [d, m, y] = String.split(fecha, "/")
    "#{y}-#{m}-#{d}"
  end
end
